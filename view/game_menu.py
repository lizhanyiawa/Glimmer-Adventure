import json
from textual.screen import Screen
from textual.widgets import Static, Button
from textual.containers import Vertical, Horizontal

class GamePlayScreen(Screen):
    """真正的游戏内剧情与交互视窗"""
    CSS = """
    GamePlayScreen { padding: 2; background: #0b0c10; }
    #status_bar { height: 3; background: #1f2833; color: #66fcf1; border: sunken #45f3ff; text-align: center; padding: 0 2; }
    #story_box { height: 12; margin: 1 0; padding: 1 2; border: solid #45f3ff; background: #1f2833; }
    #options_box { height: auto; }
    .opt_btn { margin: 0 1; background: #0b0c10; border: tall #45f3ff; color: #66fcf1; }
    .opt_btn:hover { background: #66fcf1; color: #0b0c10; }
    """

    def compose(self):
        # 顶部固定雷打不动的数据状态栏
        yield Static("🧠 精气神: 100/100 | 📍 位置: 大学教室 | 🏷️ 永久账本: []", id="status_bar")
        # 中间的故事叙事区
        yield Static("", id="story_box")
        # 底部的选项交互区
        with Horizontal(id="options_box"):
            yield Button("选项加载中...", id="opt1", classes="opt_btn")
            yield Button("选项加载中...", id="opt2", classes="opt_btn")

    def on_mount(self):
        """当这个游戏视窗被加载时，自动去读 JSON 并显示第一个故事房间"""
        with open("data/rooms.json", "r", encoding="utf-8") as f:
            rooms = json.load(f)
        
        # 拿到刚才 JSON 里的第一个房间
        room = rooms["start_classroom"]
        
        # 渲染故事与选项
        self.query_one("#story_box", Static).update(f"[bold magenta]【{room['title']}】[/bold magenta]\n\n{room['description']}")
        self.query_one("#opt1", Button).label = room["options"][0]["text"]
        self.query_one("#opt2", Button).label = room["options"][1]["text"]