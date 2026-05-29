from textual.screen import Screen
from textual.widgets import Static, Button
from textual.containers import Vertical

class MenuButton(Button):
    pass

class MainMenuScreen(Screen):
    """把主菜单封装成一个独立的‘屏幕（Screen）’"""
    CSS = """
    MainMenuScreen { align: center middle; background: #0f1016; }
    #menu_box { width: 60; height: auto; border: double $accent; background: #161923; padding: 1 3; }
    .title { text-align: center; text-style: bold; color: #ff007f; }
    .subtitle { text-align: center; text-style: italic; color: #00ffff; margin-bottom: 2; }
    MenuButton { width: 100%; margin: 1 0; background: #23283b; color: #ffffff; border: none; }
    MenuButton:hover { background: #ff007f; text-style: bold; }
    """

    def compose(self):
        with Vertical(id="menu_box"):
            yield Static("★ ISEKAI GLITCHER ★", classes="title")
            yield Static("—— 异世界降维打击与低压电工指南 ——", classes="subtitle")
            yield MenuButton("[1] 进入那个充满 Flag 的世界", id="start")
            yield MenuButton("[2] 读取超古代前端魔法记录", id="load")
            yield MenuButton("[3] 强行掐断魔法电线并跑路", id="exit")

    def on_button_pressed(self, event: Button.Pressed):
        button_id = event.button.id
        if button_id == "start":
            # 优雅地通知主程序：玩家点击了开始游戏
            self.app.action_start_game()
        elif button_id == "load":
            self.notify("未检测到存档文件的魔法残留。", title="错误", severity="error")
        elif button_id == "exit":
            self.app.exit()