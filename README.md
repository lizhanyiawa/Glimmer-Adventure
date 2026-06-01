# ★ THE ADVENTURE ★ (冒险)

这是一个基于 [Python](https://www.python.org/) 和 [Textual](https://textual.textualize.io/) 框架开发的现代 TUI (终端用户界面) 文字冒险游戏 (MUD)。

### 运行环境

- Python 3.8+
- 安装依赖：`pip install textual rich`

### 启动游戏

```bash
python launcher.py
```

## 🎮 操作说明

| 按键      | 功能                      |
| :-------- | :------------------------ |
| **1 - 4** | 选择对应的选项 / 菜单项   |
| **P**     | 查看人物状态 (Profile)    |
| **I**     | 打开背包 (Inventory)      |
| **D**     | 查看日记 (Diary)          |
| **S**     | 快速保存 (Save)           |
| **O**     | 系统设置 (Settings)       |
| **ESC**   | 返回上一级 / 退出当前界面 |

> **提示**：本游戏完全支持鼠标操作，你可以直接点击任何按钮。

## 📂 项目结构

```text
├── launcher.py           # 游戏入口
├── engine/               # 核心引擎层
│   ├── engine.py         # 游戏逻辑与状态管理
│   ├── inventory.py      # 背包管理系统
│   └── effects.py        # 视觉特效组件 (打字机等)
├── view/                 # UI 表现层
│   ├── main_menu.py      # 主菜单
│   ├── game_menu.py      # 游戏主界面 (GamePlayScreen)
│   └── ...               # 其他专项功能界面
└── data/                 # 数据配置层
    ├── rooms.json        # 场景与剧本数据
    └── dialogues.json    # NPC 对话与独白数据
```

---

_本项目目前处于早期开发阶段，旨在探索 TUI 环境下的沉浸式叙事可能性。_
