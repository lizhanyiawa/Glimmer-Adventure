"""游戏结束画面"""

from textual.screen import Screen
from textual.widgets import Static, Button
from textual.containers import Vertical
from textual import work
import asyncio


class GameOverScreen(Screen):
    BINDINGS = [
        ("escape", "return_menu", "返回主菜单"),
    ]

    CSS = """
    GameOverScreen {
        align: center middle;
        background: #0a0000;
    }
    #gameover_box {
        width: 50;
        height: auto;
        border: solid #cc0000;
        background: #1a0a0a;
        padding: 2 3;
        align: center middle;
    }
    #gameover_title {
        color: #ff2222;
        text-style: bold;
        text-align: center;
        content-align: center middle;
        margin-bottom: 2;
    }
    #gameover_text {
        color: #cc6666;
        text-align: center;
        content-align: center middle;
        margin-bottom: 2;
    }
    #btn_return_menu {
        width: 100%;
        background: #331111;
        color: #cc6666;
        border: solid #661111;
    }
    #btn_return_menu:hover {
        background: #cc0000;
        color: #ffffff;
        text-style: bold;
    }
    """

    def compose(self):
        with Vertical(id="gameover_box"):
            yield Static("你 已 阵 亡", id="gameover_title")
            yield Static(
                "你的冒险到此为止。\n\n"
                "黑暗吞噬了你的意识，\n"
                "星光从你的指尖悄然流逝……",
                id="gameover_text"
            )
            yield Button("[ 返回主菜单 ]", id="btn_return_menu")

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "btn_return_menu":
            self._return_to_menu()

    def action_return_menu(self):
        self._return_to_menu()

    def _return_to_menu(self):
        while len(self.app.screen_stack) > 1:
            self.app.pop_screen()
        self.app.push_screen(self.app.main_menu_screen)
        self.app.engine.reset_game()
