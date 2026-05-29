from textual.screen import Screen
from textual.widgets import Static, Button, Input
from textual.containers import Vertical

from view.game_menu import GamePlayScreen

class NamingScreen(Screen):
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
            yield Static("世界线观测登记系统", classes="label")
            yield Static("请输入你在该崩溃世界中的真名:", classes="label")
            yield Input(placeholder="在此处刻录你的名字...", id="name_input")
            yield Button("确认并绑定因果协议", id="confirm_name_btn")

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "confirm_name_btn":
            player_name = self.query_one("#name_input", Input).value
            
            self.app.engine.set_player_name(player_name)
            
            real_name = self.app.engine.state.stats["player_name"]
            self.notify(f"因果契约已达成：{real_name}", title="系统")
            
            self.app.pop_screen()  
            self.app.pop_screen()  
            
            game_screen = self.app.game_play_screen
            game_screen.engine = self.app.engine
            self.app.push_screen(game_screen)