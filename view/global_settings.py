# view/global_settings.py
from textual.screen import Screen
from textual.widgets import Static, Button
from textual.containers import Vertical

class GlobalSettingsScreen(Screen):
    BINDINGS = [
        ("escape", "close", "关闭"),
    ]

    CSS = """
    GlobalSettingsScreen { 
        align: center middle; 
        background: rgba(0, 0, 0, 0.8); 
    }
    #global_settings_box { 
        width: 54; 
        border: solid #ffaa00; 
        background: #161923; 
        padding: 1 4; 
    }
    .title { 
        text-align: center; 
        color: #ffaa00; 
        text-style: bold; 
        margin-bottom: 2; 
    }
    .item_btn { 
        width: 100%; 
        margin: 1 0; 
        background: #23283b; 
        color: white; 
        border: none; 
    }
    .item_btn:hover { 
        background: #ffaa00; 
        color: #0b0c10; 
        text-style: bold; 
    }
    #close_settings_btn { 
        width: 100%; 
        background: #ff007f; 
        color: white; 
        border: none; 
        margin-top: 2; 
    }
    """

    def compose(self):
        with Vertical(id="global_settings_box"):
            yield Static("全局因果参数微调", classes="title")
            yield Static("按 ESC 关闭", classes="title")
            yield Button("切换真理视界", id="toggle_debug", classes="item_btn")
            yield Button("归置世界常数倍率", id="reset_corruption", classes="item_btn")
            yield Button("[ESC] 返回游戏世界", id="close_settings_btn")

    def on_mount(self):
        self.update_labels()

    def update_labels(self):
        engine = self.app.engine
        debug_status = "开启" if engine.settings["debug_mode"] else "关闭"
        self.query_one("#toggle_debug", Button).label = f"真理视界 (Debug) -> 状态: 【{debug_status}】"
        self.query_one("#reset_corruption", Button).label = f"常识异化倍率 -> 当前: 【{engine.settings['corruption_rate']}x】"

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "close_settings_btn":
            self.action_close()
            return
            
        btn_id = event.button.id
        engine = self.app.engine

        if btn_id == "toggle_debug":
            engine.settings["debug_mode"] = not engine.settings["debug_mode"]
            self.update_labels()
            self.notify(f"真理视界状态已变更为: {engine.settings['debug_mode']}")
            
        elif btn_id == "reset_corruption":
            engine.settings["corruption_rate"] = 1.0
            self.update_labels()
            self.notify("世界常识常数已重置为基础权值 (1.0x)")

    def action_close(self):
        self.app.pop_screen()
        
        if len(self.app.screen_stack) <= 1:
            if hasattr(self.app.engine, "state") and self.app.engine.state is not None:
                self.app.push_screen(self.app.game_play_screen)
                self.app.game_play_screen.refresh_ui()
            else:
                self.app.push_screen(self.app.main_menu_screen)
        else:
            if hasattr(self.app, "game_play_screen"):
                try:
                    self.app.game_play_screen.refresh_ui()
                except Exception:
                    pass
            if hasattr(self.app, "main_menu_screen"):
                try:
                    self.app.main_menu_screen.check_save_file()
                except Exception:
                    pass