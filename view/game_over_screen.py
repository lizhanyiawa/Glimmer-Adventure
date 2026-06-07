"""游戏结束画面 — 红色渐暗动画"""

from textual.screen import Screen
from textual.widgets import Static, Button
from textual.containers import Vertical
from textual import work
import asyncio
from engine.effects import FXManager


class GameOverScreen(Screen):
    BINDINGS = [
        ("escape", "return_menu", "返回主菜单"),
    ]

    CSS = """
    GameOverScreen {
        align: center middle;
        background: #0b0c10;
    }
    #gameover_box {
        width: 50;
        height: auto;
        border: solid #330000;
        background: #1a0a0a;
        padding: 2 3;
        align: center middle;
        content-align: center middle;
    }
    #gameover_title {
        color: #663333;
        text-style: bold;
        text-align: center;
        margin-bottom: 2;
    }
    #gameover_text {
        color: #664444;
        text-align: center;
        margin-bottom: 2;
    }
    #btn_return_menu {
        width: 100%;
        background: #221111;
        color: #663333;
        border: solid #441111;
        margin-top: 2;
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

    def on_mount(self):
        self._countdown_to_return()

    @work(exclusive=True)
    async def _countdown_to_return(self):
        box = self.query_one("#gameover_box")
        # 红色边框渐亮动画
        await FXManager.play_border_brighten(box, duration=1.2, color="#ff0000")
        await asyncio.sleep(0.5)

        # 文字渐红
        title = self.query_one("#gameover_title")
        text_w = self.query_one("#gameover_text")
        btn = self.query_one("#btn_return_menu")

        for i in range(10):
            t = (i + 1) / 10
            r = int(102 + 153 * t)
            g = int(51 * (1 - t))
            b = int(51 * (1 - t))
            hex_color = f"#{r:02x}{g:02x}{b:02x}"
            title.styles.color = hex_color

            tr = int(102 * (1 - t))
            tg = int(68 * (1 - t))
            tb = int(68 * (1 - t))
            text_hex = f"#{r:02x}{tg:02x}{tb:02x}"
            text_w.styles.color = text_hex

            btn_bg_r = int(34 + 170 * t)
            btn_bg = f"#{btn_bg_r:02x}1111"
            btn.styles.background = btn_bg
            btn.styles.color = hex_color

            await asyncio.sleep(0.15)

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
