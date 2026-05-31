import os
from textual.app import App
from textual.screen import Screen
from textual.widgets import Static, Button, ListItem, ListView
from textual.containers import Vertical, Horizontal
from textual import on

from engine import GameEngine, GameState
from view.naming_screen import NamingScreen
from view.global_settings import GlobalSettingsScreen

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
    def action_new_game(self):
        from engine.engine import GameState
        self.app.engine.state = GameState()
        self.app.push_screen(NamingScreen())

    def action_load_game(self):
        if self.app.engine.load_game(1):
            self.notify("存档读取成功")
            self.app.pop_screen()
            from view.game_menu import GamePlayScreen
            self.app.push_screen(GamePlayScreen())
        else:
            self.notify("读取存档失败", title="错误")

    def action_settings(self):
        self.app.push_screen(GlobalSettingsScreen())

    def action_exit(self):
        self.app.push_screen(QuitConfirmScreen())

    def on_mount(self):
        self.check_save_file()

    # 检查存档是否存在，无存档则禁用读取按钮
    def check_save_file(self):
        has_save = os.path.exists("saves/slot_1.json")
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
            from engine.engine import GameState
            self.app.engine.state = GameState()
            self.app.push_screen(NamingScreen())

        elif button_id == "btn_load_game":
            if self.app.engine.load_game(1):
                self.notify("存档读取成功")
                self.app.pop_screen()
                from view.game_menu import GamePlayScreen
                self.app.push_screen(GamePlayScreen())
            else:
                self.notify("读取存档失败", title="错误")

        elif button_id == "btn_settings":
            self.app.push_screen(GlobalSettingsScreen())

        elif button_id == "btn_exit":
            self.app.push_screen(QuitConfirmScreen())


# 存档选择界面
class SaveSelectorScreen(Screen):
    BINDINGS = [
        ("escape", "cancel", "取消"),
        ("enter", "select", "选择"),
    ]

    CSS = """
    SaveSelectorScreen { 
        align: center middle; 
        background: rgba(0, 0, 0, 0.7); 
    }
    #selector_box { 
        width: 60; 
        height: 20; 
        border: solid #ffaa00; 
        background: #161923; 
        padding: 1 2; 
    }
    .sel_title { 
        text-align: center; 
        text-style: bold; 
        color: #ffaa00; 
        margin-bottom: 1; 
    }
    #save_list {
        background: #11141e;
        border: solid #333333;
        margin-bottom: 1;
        height: 12;
    }
    .save_item_label {
        color: #d5d5d5;
        padding: 0 1;
    }
    #btn_cancel { 
        width: 100%; 
        background: #23283b; 
        color: white; 
        border: none; 
    }
    #btn_cancel:hover { 
        background: #ffaa00; 
        color: #0b0c10;
        text-style: bold; 
    }
    """

    def compose(self):
        with Vertical(id="selector_box"):
            yield Static("存档", classes="sel_title")
            yield ListView(id="save_list")
            yield Button("[ESC] 关闭", id="btn_cancel")
            yield Static("使用 ↑↓ 选择，Enter 确认，ESC 关闭", classes="sel_title")

    def on_mount(self):
        self.refresh_save_list()

    # 刷新存档列表
    def refresh_save_list(self):
        list_view = self.query_one("#save_list", ListView)
        list_view.clear()

        slots = self.app.engine.get_save_slots()
        for s in slots:
            slot_id = s["slot"]
            if s["exists"]:
                desc = f" 槽位 [{slot_id}] · {s['room_id']} · {s['last_saved']}"
                item = ListItem(Static(desc, classes="save_item_label"), id=f"slot_{slot_id}")
            else:
                item = ListItem(Static(f" 槽位 [{slot_id}] · (空)", classes="save_item_label"), id=f"slot_{slot_id}")
                item.disabled = True
            list_view.append(item)

    @on(ListView.Selected)
    def on_save_selected(self, event: ListView.Selected):
        slot_id_str = event.item.id
        slot_idx = int(slot_id_str.split("_")[1])
        success = self.app.engine.load_game(slot_idx)
        if success:
            self.notify(f"存档 [{slot_idx}] 读取成功")
            self.app.pop_screen()
            self.app.action_start_gameplay()
        else:
            self.notify("读取存档失败", severity="error", title="错误")

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "btn_cancel":
            self.app.pop_screen()

    def action_cancel(self):
        self.app.pop_screen()

    def action_select(self):
        list_view = self.query_one("#save_list", ListView)
        selected_item = list_view.highlighted_child
        if selected_item and not selected_item.disabled:
            slot_id_str = selected_item.id
            slot_idx = int(slot_id_str.split("_")[1])
            success = self.app.engine.load_game(slot_idx)
            if success:
                self.notify(f"存档 [{slot_idx}] 读取成功")
                self.app.pop_screen()
                self.app.action_start_gameplay()
            else:
                self.notify("读取存档失败", severity="error", title="错误")


# 设置界面（在主菜单调用）
class SettingsScreen(Screen):
    CSS = """
    SettingsScreen { 
        align: center middle; 
        background: rgba(0,0,0,0.8); 
    }
    #settings_box { 
        width: 58; 
        height: auto; 
        border: solid #00ff66; 
        background: #11141e; 
        padding: 1 3; 
    }
    .settings_title { 
        text-align: center; 
        text-style: bold; 
        color: #00ff66; 
        margin-bottom: 2; 
    }
    /* 开关属性行 */
    .setting_row {
        height: 3;
        margin-bottom: 1;
        content-align: left middle;
    }
    .setting_desc {
        width: 32;
        color: #b2b2b2;
        content-align: left middle;
    }
    .toggle_btn {
        width: 18;
        border: none;
    }
    #btn_close_settings { 
        width: 100%; 
        background: #23283b; 
        color: white; 
        border: none; 
        margin-top: 1; 
    }
    #btn_close_settings:hover { 
        background: #00ff66; 
        color: #0b0c10;
        text-style: bold; 
    }
    """

    def compose(self):
        engine = self.app.engine
        with Vertical(id="settings_box"):
            yield Static("设置", classes="settings_title")

            with Horizontal(classes="setting_row"):
                yield Static("调试模式", classes="setting_desc")
                yield Button(
                    "开" if engine.settings["debug_mode"] else "关",
                    id="toggle_debug",
                    classes="toggle_btn"
                )

            with Horizontal(classes="setting_row"):
                yield Static("侵蚀倍率", classes="setting_desc")
                yield Button(
                    f"{engine.settings['corruption_rate']}x",
                    id="toggle_corruption",
                    classes="toggle_btn"
                )

            with Horizontal(classes="setting_row"):
                yield Static("音效", classes="setting_desc")
                yield Button(
                    "开" if engine.settings["sound_enabled"] else "关",
                    id="toggle_sound",
                    classes="toggle_btn"
                )

            yield Button("保存并关闭", id="btn_close_settings")

    def on_button_pressed(self, event: Button.Pressed):
        btn_id = event.button.id
        engine = self.app.engine

        if btn_id == "toggle_debug":
            engine.settings["debug_mode"] = not engine.settings["debug_mode"]
            event.button.label = "开" if engine.settings["debug_mode"] else "关"
            self.notify(f"调试模式: {'开' if engine.settings['debug_mode'] else '关'}")

        elif btn_id == "toggle_corruption":
            rates = [0.0, 0.5, 1.0, 1.5, 2.0]
            curr_rate = engine.settings["corruption_rate"]
            next_idx = (rates.index(curr_rate) + 1) % len(rates) if curr_rate in rates else 2
            engine.settings["corruption_rate"] = rates[next_idx]
            event.button.label = f"{engine.settings['corruption_rate']}x"
            self.notify(f"侵蚀倍率: {engine.settings['corruption_rate']}x")

        elif btn_id == "toggle_sound":
            engine.settings["sound_enabled"] = not engine.settings["sound_enabled"]
            event.button.label = "开" if engine.settings["sound_enabled"] else "关"
            self.notify(f"音效: {'开' if engine.settings['sound_enabled'] else '关'}")

        elif btn_id == "btn_close_settings":
            engine.save_settings()
            self.app.pop_screen()
            if hasattr(self.app.main_menu_screen, "update_load_button_state"):
                self.app.main_menu_screen.update_load_button_state()


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


# 应用入口
class MUDApp(App):
    def on_mount(self):
        self.engine = GameEngine()
        self.main_menu_screen = MainMenuScreen()
        self.push_screen(self.main_menu_screen)

    def action_start_gameplay(self):
        self.notify(f"已加载房间: {self.engine.state.room_id}", title="进入游戏")

if __name__ == "__main__":
    app = MUDApp()
    app.run()
