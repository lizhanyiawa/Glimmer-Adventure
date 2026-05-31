from textual.screen import Screen
from textual.widgets import Static, Button, Input
from textual.containers import Vertical

from view.transition_screen import TransitionScreen

# 命名界面
class NamingScreen(Screen):
    BINDINGS = [
        ("enter", "confirm", "确认"),
        ("escape", "cancel", "取消"),
    ]

    CSS = """
    NamingScreen { 
        align: center middle; 
        background: rgba(0, 0, 0, 0.85); 
    }
    #naming_box { 
        width: 50; 
        border: thick #00ffff; 
        background: #161923; 
        padding: 1 4; 
    }
    .label { 
        text-align: center; 
        color: #66fcf1; 
        margin-bottom: 1; 
    }
    Input { 
        background: #1f2833; 
        color: #ffffff; 
        border: tall #45f3ff; 
        margin-bottom: 2; 
    }
    #confirm_name_btn { 
        width: 100%; 
        background: #23283b; 
        color: white; 
        border: none; 
    }
    #confirm_name_btn:hover { 
        background: #00ffff; 
        color: #0b0c10; 
        text-style: bold; 
    }
    """

    def compose(self):
        with Vertical(id="naming_box"):
            yield Static("命名", classes="label")
            yield Static("输入你的名字:", classes="label")
            yield Input(placeholder="", id="name_input")
            yield Static("Enter 确认，ESC 取消", classes="label")
            yield Button("[Enter] 确认", id="confirm_name_btn")

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "confirm_name_btn":
            self.action_confirm()

    def action_confirm(self):
        player_name = self.query_one("#name_input", Input).value
        self.app.engine.set_player_name(player_name)
        real_name = self.app.engine.state.stats["player_name"]
        self.notify(f"命名成功: {real_name}", title="系统")

        self.app.pop_screen()
        self.app.pop_screen()

        self.app.push_screen(TransitionScreen())

    def action_cancel(self):
        self.app.pop_screen()
