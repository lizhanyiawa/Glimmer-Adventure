#!/usr/bin/env node
/**
 * Godot MCP 代理
 * ------------------------------------------------------------------
 * 问题：Trae 只注册每个 MCP 服务器 tools/list 返回的前 40 个工具，
 *       而 @yanhuifair/godot-mcp 提供 386 个（按字母序排列），
 *       第 41 个 create_noise_texture 起全部被静默丢弃。
 *
 * 方案：本代理接在 Trae 和真实服务器之间，只向 Trae 暴露 35 个工具：
 *   - 33 个常用 Godot 工具：原样转发给子进程
 *   - godot_search：在全部 386 个工具里按关键词检索名称与参数 schema
 *   - godot_call  ：按名字调用任意一个工具（含被裁剪掉的 353 个）
 *       这样 386 个能力一个不丢，且工具数永远低于 40 的上限。
 *
 * 子进程启动命令可用环境变量 GODOT_MCP_CHILD_CMD 覆盖；
 * 项目路径可用 GODOT_PROJECT_PATH 覆盖（默认 d:\The adventure\godot）。
 */

const { spawn } = require("child_process");
const readline = require("readline");

const PROJECT_PATH = process.env.GODOT_PROJECT_PATH || "D:\\The adventure\\godot";
const CHILD_CMD =
  process.env.GODOT_MCP_CHILD_CMD ||
  `npx -y @yanhuifair/godot-mcp -p "${PROJECT_PATH}"`;

// 直接暴露给 Trae 的常用工具（顺序即注册顺序，务必保持在 40 以内）
const CORE_TOOLS = [
  // 诊断 / 发现
  "get_status",
  "search_tools",
  // 项目与文件
  "list_project_files",
  "list_scenes",
  "list_scripts",
  "read_project_config",
  "search_in_project",
  // 读
  "read_scene",
  "read_script",
  "read_resource",
  // 写
  "create_scene",
  "create_script",
  "create_resource",
  "write_script",
  "write_resource",
  // 节点
  "add_node",
  "modify_node",
  "remove_node",
  "rename_node",
  "clone_node",
  "set_node_position",
  "find_nodes_in_scenes",
  // 脚本 / 信号
  "attach_script",
  "connect_signal",
  "validate_script",
  // 编辑器
  "editor_get_errors",
  "editor_run_gdscript",
  "editor_save_all",
  "editor_play",
  "editor_stop",
  "editor_take_screenshot",
  // 运行时
  "runtime_get_tree",
  "runtime_screenshot",
];

const META_TOOLS = [
  {
    name: "godot_search",
    description:
      "在 Godot MCP 的全部 386 个工具中按关键词检索（匹配工具名与描述），返回匹配项的名称、说明和完整参数 schema。用于发现未被直接暴露的工具（本客户端只直接注册了 35 个），查完后用 godot_call 调用。",
    inputSchema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description:
            "关键词，可用空格分隔多个词。例如 \"tilemap tileset\"、\"audio bus effect\"、\"animation track\"、\"3d mesh\"。",
        },
        limit: {
          type: "number",
          description: "最多返回多少个匹配，默认 8，最大 25。",
        },
      },
      required: ["query"],
    },
  },
  {
    name: "godot_call",
    description:
      "按名称调用任意一个 Godot MCP 工具（共 386 个，包括未被直接注册的那些）。调用前请先用 godot_search 查到准确的工具名和参数 schema。",
    inputSchema: {
      type: "object",
      properties: {
        tool: {
          type: "string",
          description: "工具名，例如 \"create_tileset\"、\"list_translations\"、\"runtime_freeze\"。",
        },
        arguments: {
          type: "object",
          description: "传给该工具的参数对象，键名需与该工具的 schema 一致。",
        },
      },
      required: ["tool"],
    },
  },
];

// ---------------------------------------------------------------- 子进程

function spawnChild() {
  const opts = {
    stdio: ["pipe", "pipe", "pipe"],
    env: process.env,
  };
  if (process.platform === "win32") {
    // npx 是 .cmd 脚本，必须经由 cmd.exe 启动
    return spawn(process.env.ComSpec || "cmd.exe", ["/d", "/s", "/c", CHILD_CMD], {
      ...opts,
      windowsVerbatimArguments: true,
    });
  }
  return spawn(CHILD_CMD, { ...opts, shell: true });
}

const child = spawnChild();

let childAlive = true;

child.on("error", (err) => {
  process.stderr.write(`[godot-mcp-proxy] 子进程启动失败: ${err.message}\n`);
  process.exit(1);
});

child.on("exit", (code, signal) => {
  childAlive = false;
  process.stderr.write(
    `[godot-mcp-proxy] 子进程退出 code=${code} signal=${signal}\n`
  );
  for (const p of internalPending.values()) {
    clearTimeout(p.timer);
    p.reject(new Error("godot mcp 子进程已退出"));
  }
  internalPending.clear();
  process.exit(code === null ? 1 : code || 0);
});

child.stderr.on("data", (d) => process.stderr.write(d));
child.stdout.setEncoding("utf8");

function sendToChild(msg) {
  if (!childAlive || !child.stdin.writable) return;
  try {
    child.stdin.write(JSON.stringify(msg) + "\n");
  } catch (e) {
    process.stderr.write(`[godot-mcp-proxy] 写入子进程失败: ${e.message}\n`);
  }
}

function sendToClient(msg) {
  try {
    process.stdout.write(JSON.stringify(msg) + "\n");
  } catch (e) {
    /* stdout 已关闭，忽略 */
  }
}

// ---------------------------------------------------------------- 状态

let childIdSeq = 0;
const internalPending = new Map(); // childId -> { resolve, reject, timer, method }
const forwardPending = new Map(); // childId -> { clientId, method }

let childTools = null; // 全部 386 个工具
let childToolsPromise = null;
let initializedNotified = false;

function callChild(method, params, timeoutMs) {
  return new Promise((resolve, reject) => {
    const id = ++childIdSeq;
    const timer = setTimeout(() => {
      internalPending.delete(id);
      reject(new Error(`内部调用超时: ${method}`));
    }, timeoutMs || 60000);
    internalPending.set(id, { resolve, reject, timer, method });
    sendToChild({ jsonrpc: "2.0", id, method, params });
  });
}

async function loadChildTools() {
  const all = [];
  let cursor;
  for (let i = 0; i < 50; i++) {
    const res = await callChild("tools/list", cursor ? { cursor } : {}, 60000);
    const tools = (res && res.tools) || [];
    all.push(...tools);
    cursor = res && res.nextCursor;
    if (!cursor) break;
  }
  return all;
}

async function ensureToolsCache() {
  if (childTools) return childTools;
  if (!childToolsPromise) {
    childToolsPromise = loadChildTools()
      .then((tools) => {
        if (!tools.length) throw new Error("子进程返回了 0 个工具");
        childTools = tools;
        process.stderr.write(
          `[godot-mcp-proxy] 已缓存子进程工具数: ${tools.length}\n`
        );
        return tools;
      })
      .catch((e) => {
        childToolsPromise = null; // 允许下次重试
        throw e;
      });
  }
  return childToolsPromise;
}

// ---------------------------------------------------------------- 工具检索

function scoreTool(tool, tokens) {
  const name = (tool.name || "").toLowerCase();
  const desc = (tool.description || "").toLowerCase();
  let score = 0;
  for (const t of tokens) {
    if (name === t) score += 100;
    else if (name.includes(t)) score += 25;
    if (desc.includes(t)) score += 5;
  }
  return score;
}

function searchTools(all, query, limit) {
  const tokens = String(query || "")
    .toLowerCase()
    .split(/\s+/)
    .filter(Boolean);
  if (!tokens.length) return all.slice(0, limit);
  return all
    .map((t) => ({ tool: t, score: scoreTool(t, tokens) }))
    .filter((x) => x.score > 0)
    .sort((a, b) => b.score - a.score || a.tool.name.localeCompare(b.tool.name))
    .slice(0, limit)
    .map((x) => x.tool);
}

function formatSearchResult(all, matches, query) {
  if (!matches.length) {
    return `在 ${all.length} 个工具中没有匹配 "${query}" 的结果。换个关键词，或直接试 godot_search 的英文词（如 "tilemap"、"audio"、"animation"、"material"）。`;
  }
  const parts = [`共 ${all.length} 个工具，匹配 "${query}" 的前 ${matches.length} 个：\n`];
  matches.forEach((t, i) => {
    let schema = "";
    try {
      schema = JSON.stringify(t.inputSchema || {});
    } catch (e) {
      schema = "(schema 序列化失败)";
    }
    if (schema.length > 1400) schema = schema.slice(0, 1400) + "…(已截断)";
    parts.push(
      `${i + 1}. ${t.name}\n   说明：${t.description || "(无)"}\n   参数：${schema}\n`
    );
  });
  parts.push(
    `调用方式：godot_call({ tool: "<工具名>", arguments: { ... } })\n` +
      `（本次结果较多时，用更大的 limit 重查，或缩小关键词范围。）`
  );
  return parts.join("\n");
}

// ---------------------------------------------------------------- 客户端消息

function forwardToChild(msg) {
  if (msg.id === undefined) {
    sendToChild(msg);
    return;
  }
  const childId = ++childIdSeq;
  forwardPending.set(childId, { clientId: msg.id, method: msg.method });
  sendToChild({ ...msg, id: childId });
}

async function handleToolsList(msg) {
  let exposed = [];
  try {
    const all = await ensureToolsCache();
    const byName = new Map(all.map((t) => [t.name, t]));
    for (const name of CORE_TOOLS) {
      const t = byName.get(name);
      if (t) exposed.push(t);
      else process.stderr.write(`[godot-mcp-proxy] 子进程缺少工具: ${name}\n`);
    }
  } catch (e) {
    process.stderr.write(`[godot-mcp-proxy] 拉取工具列表失败: ${e.message}\n`);
  }
  exposed.push(...META_TOOLS);
  sendToClient({ jsonrpc: "2.0", id: msg.id, result: { tools: exposed } });
}

async function handleGodotSearch(msg) {
  const args = (msg.params && msg.params.arguments) || {};
  try {
    const all = await ensureToolsCache();
    const limit = Math.min(Math.max(Number(args.limit) || 8, 1), 25);
    const matches = searchTools(all, args.query, limit);
    sendToClient({
      jsonrpc: "2.0",
      id: msg.id,
      result: {
        content: [{ type: "text", text: formatSearchResult(all, matches, args.query) }],
      },
    });
  } catch (e) {
    sendToClient({
      jsonrpc: "2.0",
      id: msg.id,
      result: {
        content: [{ type: "text", text: `godot_search 失败: ${e.message}` }],
        isError: true,
      },
    });
  }
}

async function handleGodotCall(msg) {
  const args = (msg.params && msg.params.arguments) || {};
  const target = args.tool || args.name;
  if (!target) {
    sendToClient({
      jsonrpc: "2.0",
      id: msg.id,
      result: {
        content: [{ type: "text", text: "godot_call 缺少 tool 参数。" }],
        isError: true,
      },
    });
    return;
  }
  const targetArgs = args.arguments || args.args || {};
  try {
    const result = await callChild(
      "tools/call",
      { name: target, arguments: targetArgs },
      180000
    );
    sendToClient({ jsonrpc: "2.0", id: msg.id, result });
  } catch (e) {
    sendToClient({
      jsonrpc: "2.0",
      id: msg.id,
      result: {
        content: [
          {
            type: "text",
            text: `godot_call("${target}") 失败: ${e.message}\n可用 godot_search 确认工具名是否正确。`,
          },
        ],
        isError: true,
      },
    });
  }
}

function handleClientMessage(msg) {
  const method = msg.method;

  if (method === "ping") {
    sendToClient({ jsonrpc: "2.0", id: msg.id, result: {} });
    return;
  }
  if (method === "tools/list") {
    handleToolsList(msg);
    return;
  }
  if (method === "tools/call") {
    const name = msg.params && msg.params.name;
    if (name === "godot_search") return void handleGodotSearch(msg);
    if (name === "godot_call") return void handleGodotCall(msg);
    forwardToChild(msg);
    return;
  }
  if (method === "notifications/initialized") {
    forwardToChild(msg);
    if (!initializedNotified) {
      initializedNotified = true;
      ensureToolsCache().catch((e) =>
        process.stderr.write(`[godot-mcp-proxy] 预取工具列表失败: ${e.message}\n`)
      );
    }
    return;
  }
  forwardToChild(msg);
}

// ---------------------------------------------------------------- 子进程消息

const PROXY_HINT =
  "\n\n【本服务器经由代理转发】底层 Godot MCP 实际提供 386 个工具，" +
  "但客户端对本服务器的注册上限是 40 个，因此这里只直接注册了 35 个常用工具。" +
  "如需其他能力（tilemap、动画、音频总线、材质、翻译、运行时冻结/步进等），" +
  "请先用 godot_search 按关键词检索工具名与参数 schema，" +
  "再用 godot_call({ tool: \"<工具名>\", arguments: { ... } }) 调用。" +
  "不要假设工具不存在——先搜一次。";

function handleChildMessage(msg) {
  if (msg.id !== undefined && msg.id !== null) {
    const internal = internalPending.get(msg.id);
    if (internal) {
      internalPending.delete(msg.id);
      clearTimeout(internal.timer);
      if (msg.error) internal.reject(new Error(msg.error.message || "子进程返回错误"));
      else internal.resolve(msg.result);
      return;
    }
    const fwd = forwardPending.get(msg.id);
    if (fwd) {
      forwardPending.delete(msg.id);
      let out = { ...msg, id: fwd.clientId };
      if (fwd.method === "initialize" && out.result) {
        out = {
          ...out,
          result: {
            ...out.result,
            instructions: (out.result.instructions || "") + PROXY_HINT,
          },
        };
      }
      sendToClient(out);
      return;
    }
    return; // 未知 id，丢弃
  }

  // 通知类消息：tools/list_changed 会触发客户端重新拉取，但本代理的工具集是静态的
  if (msg.method === "notifications/tools/list_changed") {
    return;
  }
  sendToClient(msg);
}

// ---------------------------------------------------------------- 主循环

function makeLineReader(stream, onMessage) {
  const rl = readline.createInterface({ input: stream, crlfDelay: Infinity });
  rl.on("line", (line) => {
    const t = line.trim();
    if (!t) return;
    let msg;
    try {
      msg = JSON.parse(t);
    } catch (e) {
      process.stderr.write(`[godot-mcp-proxy] 无法解析的消息行\n`);
      return;
    }
    onMessage(msg);
  });
  return rl;
}

makeLineReader(process.stdin, handleClientMessage);
makeLineReader(child.stdout, handleChildMessage);

process.stdin.on("end", () => {
  childAlive = false;
  try {
    child.kill();
  } catch (e) {
    /* ignore */
  }
  process.exit(0);
});

process.on("uncaughtException", (e) => {
  process.stderr.write(`[godot-mcp-proxy] 未捕获异常: ${e.stack || e.message}\n`);
});