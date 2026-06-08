from textual.screen import Screen
from textual.widgets import Static, Button
from textual.containers import Vertical, Horizontal

from view.naming_screen import NamingScreen
from view.global_settings import GlobalSettingsScreen
from view.brighten_screen import BrightenScreen
from view.load_game_screen import LoadGameScreen

class MenuButton(Button):
    pass

# 主菜单
class MainMenuScreen(Screen):
    BINDINGS = [
        ("1", "new_game", "新游戏"),
        ("2", "load_game", "读取游戏"),
        ("3", "settings", "设置"),
        ("4", "exit", "退出"),
    ]

    CSS = """
    MainMenuScreen { 
        align: center middle; 
        background: #0b0c10; 
    }
    #menu_box { 
        width: 65; 
        height: auto; 
        border: double #45f3ff; 
        background: #1f2833; 
        padding: 1 3; 
    }
    .title { 
        text-align: center; 
        text-style: bold; 
        color: #66fcf1; 
        margin-bottom: 0;
    }
    .subtitle { 
        text-align: center; 
        text-style: italic; 
        color: #ffaa00; 
        margin-bottom: 2; 
    }
    MenuButton { 
        width: 100%; 
        margin: 1 0; 
        background: #11141e; 
        color: #66fcf1; 
        border: none; 
    }
    MenuButton:hover { 
        background: #45f3ff; 
        color: #0b0c10; 
        text-style: bold; 
    }
    MenuButton:disabled {
        background: #1a222d;
        color: #555555;
    }
    """

    def compose(self):
        with Vertical(id="menu_box"):
            yield Static("★ THE ADVENTURE ★", classes="title")
            yield Static("—— 冒险 ——", classes="subtitle")
            yield MenuButton("[1] 新游戏", id="btn_new_game")
            yield MenuButton("[2] 读取游戏", id="btn_load_game")
            yield MenuButton("[3] 设置", id="btn_settings")
            yield MenuButton("[4] 退出游戏", id="btn_exit")
            yield Static("使用 1-4 数字键选择，或用鼠标点击", classes="subtitle")

    # 键盘动作
    def _start_new_game(self):
        self.app.engine.reset_game()
        self.app.push_screen(NamingScreen())

    def _open_load_game(self):
        self.app.push_screen(LoadGameScreen())

    def _open_settings(self):
        self.app.push_screen(GlobalSettingsScreen())

    def _open_quit(self):
        self.app.push_screen(QuitConfirmScreen())

    def action_new_game(self):
        self._start_new_game()

    def action_load_game(self):
        self._open_load_game()

    def action_settings(self):
        self._open_settings()

    def action_exit(self):
        self._open_quit()

    def on_mount(self):
        self.check_save_file()

    # 检查存档是否存在，无存档则禁用读取按钮
    def check_save_file(self):
        slots = self.app.engine.get_save_slots()
        has_save = any(s["exists"] and not s.get("corrupted") for s in slots)
        try:
            load_btn = self.query_one("#btn_load_game", MenuButton)
        except Exception:
            return
        if not has_save:
            load_btn.disabled = True
            load_btn.label = "[2] 读取游戏 (无存档)"
        else:
            load_btn.disabled = False
            load_btn.label = "[2] 读取游戏"

    def on_button_pressed(self, event: Button.Pressed):
        button_id = event.button.id

        if button_id == "btn_new_game":
            self._start_new_game()

        elif button_id == "btn_load_game":
            self._open_load_game()

        elif button_id == "btn_settings":
            self._open_settings()

        elif button_id == "btn_exit":
            self._open_quit()


# 退出确认弹窗
class QuitConfirmScreen(Screen):
    BINDINGS = [
        ("y", "confirm", "确认退出"),
        ("n", "cancel", "取消"),
        ("escape", "cancel", "取消"),
    ]

    CSS = """
    QuitConfirmScreen { 
        align: center middle; 
        background: rgba(0,0,0,0.65); 
    }
    #confirm_box { 
        width: 50; 
        height: auto; 
        border: heavy red; 
        background: #1a1010; 
        padding: 1 4; 
    }
    .confirm_title { 
        text-align: center; 
        text-style: bold; 
        color: red; 
        margin-bottom: 1; 
    }
    .confirm_text { 
        text-align: center; 
        margin-bottom: 2; 
        color: #e5e5e5; 
    }
    #btn_box { 
        content-align: center middle; 
        height: auto; 
        width: 100%; 
    }
    .choice_btn { 
        width: 18; 
        margin: 0 1; 
    }
    #btn_yes { 
        background: #880000; 
        color: white; 
        border: none; 
    }
    #btn_yes:hover { 
        background: red; 
        text-style: bold; 
    }
    #btn_no { 
        background: #222222; 
        color: white; 
        border: none; 
    }
    #btn_no:hover { 
        background: #555555; 
        text-style: bold; 
    }
    """

    def compose(self):
        with Vertical(id="confirm_box"):
            yield Static("⚠️ 退出确认", classes="confirm_title")
            yield Static("确定要退出游戏吗？\n未保存的进度将会丢失。", classes="confirm_text")
            yield Static("按 Y 确认，N 或 ESC 取消", classes="confirm_text")
            with Horizontal(id="btn_box"):
                yield Button("[Y] 退出", id="btn_yes", classes="choice_btn")
                yield Button("[N] 取消", id="btn_no", classes="choice_btn")

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "btn_yes":
            self.app.exit()
        elif event.button.id == "btn_no":
            self.app.pop_screen()

    def action_confirm(self):
        self.app.exit()

    def action_cancel(self):
        self.app.pop_screen()



