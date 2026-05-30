from textual.screen import Screen
from textual.widgets import Static, Button
from textual.containers import Vertical

# 全局设置界面
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
            yield Static("设置", classes="title")
            yield Static("按 ESC 关闭", classes="title")
            yield Button("读取存档", id="load_save", classes="item_btn")
            yield Button("调试模式: 关", id="toggle_debug", classes="item_btn")
            yield Button("侵蚀倍率: 1.0x", id="reset_corruption", classes="item_btn")
            yield Button("[ESC] 返回", id="close_settings_btn")

    def on_mount(self):
        self.update_labels()

    # 更新按钮文字
    def update_labels(self):
        engine = self.app.engine
        debug_status = "开" if engine.settings["debug_mode"] else "关"
        self.query_one("#toggle_debug", Button).label = f"调试模式: {debug_status}"
        self.query_one("#reset_corruption", Button).label = f"侵蚀倍率: {engine.settings['corruption_rate']}x"

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "close_settings_btn":
            self.action_close()
            return

        btn_id = event.button.id
        engine = self.app.engine

        if btn_id == "load_save":
            from view.save_selection_screen import SaveSelectionScreen
            self.app.push_screen(SaveSelectionScreen())
            return

        if btn_id == "toggle_debug":
            engine.settings["debug_mode"] = not engine.settings["debug_mode"]
            self.update_labels()
            self.notify(f"调试模式: {'开' if engine.settings['debug_mode'] else '关'}")

        elif btn_id == "reset_corruption":
            engine.settings["corruption_rate"] = 1.0
            self.update_labels()
            self.notify("侵蚀倍率已重置为 1.0x")

    def action_close(self):
        self.app.pop_screen()

        if len(self.app.screen_stack) <= 1:
            if hasattr(self.app.engine, "state") and self.app.engine.state is not None:
                from view.game_menu import GamePlayScreen
                self.app.push_screen(GamePlayScreen())
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
