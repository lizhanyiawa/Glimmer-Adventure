# ★ THE ADVENTURE ★（异世界文字冒险）

一个基于 Godot 4.7 的异世界穿越黑暗幻想文字冒险游戏，逻辑与界面分离，剧情与数据全部由 JSON 驱动。

## 当前状态

渲染层已从 Python + Textual 整体迁移到 Godot，现在仓库以 Godot 单栈维护。旧版 Python/Textual 实现（`engine/`、`view/`、`launcher.py`、`engine_config.json`、`saves/`）已从 `main` 分支清退，完整历史归档在 `python-legacy` 分支，不再维护，仅作参考。

## 环境要求

- Godot 4.7
- 渲染后端：`gl_compatibility`（已在 `godot/project.godot` 中设定）

## 怎么跑起来

1. 用 Godot 4.7 打开 `godot/` 工程。
2. 主场景为 `res://scenes/Intro.tscn`（已在工程设置中指定）。
3. 直接按 F5 运行。

## 目录结构

| 路径 | 说明 |
|------|------|
| `godot/scenes/` | 场景文件（`.tscn`）：Intro、MainMenu、Naming、Transition、Brighten、GamePlay、Battle、GameOver、Modal |
| `godot/scripts/core/` | 核心逻辑层，纯逻辑、不依赖界面，可单独自测 |
| `godot/scripts/ui/` | 界面层脚本，负责渲染与接线 |
| `godot/data/` | JSON 数据目录（运行时即 `res://data/`），逻辑与文本分离 |
| `godot/assets/` | 像素字体（`fonts/`）与全局主题（`theme/game_theme.tres`） |
| `tools/` | 开发辅助脚本（`godot-mcp-proxy.js`） |

## 数据在哪里改

数据全部位于 `godot/data/`，共 6 组，逻辑与文本分文件存放，引擎启动时按 ID 合并：

| 逻辑文件 | 文本文件 | 内容 |
|----------|----------|------|
| `items.json` | `items_text.json` | 物品逻辑 + 物品描述 |
| `dialogues.json` | `dialogues_text.json` | 对话逻辑 + 对话文本 |
| `enemies.json` | `enemies_text.json` | 敌人数值 + 叙事文本 |
| `rooms/`（按区域分片） | `rooms_text/`（按区域分片） | 房间逻辑 + 房间标题与描述 |
| `shops.json` | 无独立文本文件 | 商店逻辑，含 `name` / `greeting` 文案 |

- 剧情标签（如 `<fire>`、`<shadow>`）直接写在文本文件里，由 `Palette.render()` 统一转成 RichTextLabel 能识别的 BBCode，无需在数据里写 BBCode。
- 合并规则：`description_alt` 的条件写在逻辑文件、`text` 按同索引取自文本文件，两边数量必须一致。

## 开发期自检

- 启动时 `GameEngine.validate_data()` 会自动做数据引用校验（仅在调试构建生效）：检查选项跳转目标、商店商品、敌人掉落物是否存在，以及叙事占位符是否合法。发现问题时在控制台/调试器输出 `[数据自检]` 开头的 warning；无问题则打印通过提示。
- 若 `godot/tests/` 目录存在，说明可以用下面的命令跑核心逻辑自测（失败时退出码非 0）：

  ```bash
  godot --headless --path godot res://tests/TestRunner.tscn
  ```

## 打包注意

- 数据已收进工程（`res://data/`），正常导出即可随包带上，无需额外拷贝。
- 换场景一律走 `Fx.goto(path)`（黑场淡出 → 换场景 → 淡入），不要直接调用 `change_scene_to_file`。

更详细的结构说明（分层架构、数据模型、核心流程、flag 规范、已有内容清单）见 `structure.txt`。