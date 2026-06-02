from textual.screen import Screen
from textual.widgets import Static, Button
from textual.containers import Vertical, Horizontal


class ConfirmActionScreen(Screen):
    BINDINGS = [
        ("y", "confirm", "确认"),
        ("n", "cancel", "取消"),
        ("escape", "cancel", "取消"),
    ]

    CSS = """
    ConfirmActionScreen {
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

    def __init__(self, title: str, message: str, on_confirm):
        super().__init__()
        self._title = title
        self._message = message
        self._on_confirm = on_confirm

    def compose(self):
        with Vertical(id="confirm_box"):
            yield Static(self._title, classes="confirm_title")
            yield Static(self._message, classes="confirm_text")
            yield Static("按 Y 确认，N 或 ESC 取消", classes="confirm_text")
            with Horizontal(id="btn_box"):
                yield Button("[Y] 确认", id="btn_yes", classes="choice_btn")
                yield Button("[N] 取消", id="btn_no", classes="choice_btn")

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "btn_yes":
            self.app.pop_screen()
            self._on_confirm()
        elif event.button.id == "btn_no":
            self.app.pop_screen()

    def action_confirm(self):
        self.app.pop_screen()
        self._on_confirm()

    def action_cancel(self):
        self.app.pop_screen()


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
        width: 58;
        border: solid #ffaa00;
        background: #161923;
        padding: 1 4;
    }
    .title {
        text-align: center;
        color: #ffaa00;
        text-style: bold;
        margin-bottom: 1;
    }
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
    .action_btn {
        width: 100%;
        margin: 1 0;
        background: #23283b;
        color: white;
        border: none;
    }
    .action_btn:hover {
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
    #close_settings_btn:hover {
        background: #ffaa00;
        text-style: bold;
    }
    """

    SPEED_ORDER = ["instant", "fast", "medium", "slow"]
    SPEED_LABELS = {"instant": "即时", "fast": "快", "medium": "中", "slow": "慢"}

    def compose(self):
        engine = self.app.engine
        s = engine.settings

        with Vertical(id="global_settings_box"):
            yield Static("设置", classes="title")

            with Horizontal(classes="setting_row"):
                yield Static("文字速度", classes="setting_desc")
                yield Button(
                    self.SPEED_LABELS.get(s.get("text_speed", "medium"), "中"),
                    id="toggle_text_speed",
                    classes="toggle_btn"
                )

            with Horizontal(classes="setting_row"):
                yield Static("调试模式", classes="setting_desc")
                yield Button(
                    "开" if s.get("debug_mode", False) else "关",
                    id="toggle_debug",
                    classes="toggle_btn"
                )

            with Horizontal(classes="setting_row"):
                yield Static("侵蚀倍率", classes="setting_desc")
                yield Button(
                    f"{s.get('corruption_rate', 1.0)}x",
                    id="toggle_corruption",
                    classes="toggle_btn"
                )

            with Horizontal(classes="setting_row"):
                yield Static("跳过开场动画", classes="setting_desc")
                yield Button(
                    "开" if s.get("skip_intro", False) else "关",
                    id="toggle_skip_intro",
                    classes="toggle_btn"
                )

            with Horizontal(classes="setting_row"):
                yield Static("返回主菜单确认", classes="setting_desc")
                yield Button(
                    "开" if s.get("confirm_return", True) else "关",
                    id="toggle_confirm_return",
                    classes="toggle_btn"
                )

            with Horizontal(classes="setting_row"):
                yield Static("退出游戏确认", classes="setting_desc")
                yield Button(
                    "开" if s.get("confirm_exit", True) else "关",
                    id="toggle_confirm_exit",
                    classes="toggle_btn"
                )

            with Horizontal(classes="setting_row"):
                yield Static("覆盖存档提醒", classes="setting_desc")
                yield Button(
                    "开" if s.get("confirm_save", True) else "关",
                    id="toggle_confirm_save",
                    classes="toggle_btn"
                )

            with Horizontal(classes="setting_row"):
                yield Static("历史记录上限(行)", classes="setting_desc")
                yield Button(
                    str(s.get("history_lines", 200)),
                    id="toggle_history_lines",
                    classes="toggle_btn"
                )

            yield Button("读取存档", id="load_save", classes="action_btn")
            yield Button("回到主菜单", id="return_to_menu", classes="action_btn")
            yield Button("退出游戏", id="exit_game", classes="action_btn")
            yield Button("保存并关闭", id="close_settings_btn")

    def on_button_pressed(self, event: Button.Pressed):
        btn_id = event.button.id
        engine = self.app.engine

        if btn_id == "toggle_text_speed":
            cur = engine.settings.get("text_speed", "medium")
            idx = self.SPEED_ORDER.index(cur) if cur in self.SPEED_ORDER else 2
            next_idx = (idx + 1) % len(self.SPEED_ORDER)
            engine.settings["text_speed"] = self.SPEED_ORDER[next_idx]
            event.button.label = self.SPEED_LABELS[self.SPEED_ORDER[next_idx]]
            self.notify(f"文字速度: {self.SPEED_LABELS[self.SPEED_ORDER[next_idx]]}")

        elif btn_id == "toggle_debug":
            engine.settings["debug_mode"] = not engine.settings.get("debug_mode", False)
            event.button.label = "开" if engine.settings["debug_mode"] else "关"
            self.notify(f"调试模式: {'开' if engine.settings['debug_mode'] else '关'}")

        elif btn_id == "toggle_corruption":
            rates = [0.0, 0.5, 1.0, 1.5, 2.0]
            cur = engine.settings.get("corruption_rate", 1.0)
            idx = rates.index(cur) if cur in rates else 2
            next_idx = (idx + 1) % len(rates)
            engine.settings["corruption_rate"] = rates[next_idx]
            event.button.label = f"{rates[next_idx]}x"
            self.notify(f"侵蚀倍率: {rates[next_idx]}x")

        elif btn_id == "toggle_skip_intro":
            engine.settings["skip_intro"] = not engine.settings.get("skip_intro", False)
            event.button.label = "开" if engine.settings["skip_intro"] else "关"
            self.notify(f"跳过开场动画: {'开' if engine.settings['skip_intro'] else '关'}")

        elif btn_id == "toggle_confirm_return":
            engine.settings["confirm_return"] = not engine.settings.get("confirm_return", True)
            event.button.label = "开" if engine.settings["confirm_return"] else "关"
            self.notify(f"返回主菜单确认: {'开' if engine.settings['confirm_return'] else '关'}")

        elif btn_id == "toggle_confirm_exit":
            engine.settings["confirm_exit"] = not engine.settings.get("confirm_exit", True)
            event.button.label = "开" if engine.settings["confirm_exit"] else "关"
            self.notify(f"退出游戏确认: {'开' if engine.settings['confirm_exit'] else '关'}")

        elif btn_id == "toggle_confirm_save":
            engine.settings["confirm_save"] = not engine.settings.get("confirm_save", True)
            event.button.label = "开" if engine.settings["confirm_save"] else "关"
            self.notify(f"覆盖存档提醒: {'开' if engine.settings['confirm_save'] else '关'}")

        elif btn_id == "toggle_history_lines":
            options = [50, 100, 200, 500]
            cur = engine.settings.get("history_lines", 200)
            idx = options.index(cur) if cur in options else 2
            next_val = options[(idx + 1) % len(options)]
            engine.settings["history_lines"] = next_val
            event.button.label = str(next_val)
            self.notify(f"历史记录上限: {next_val} 行")

        elif btn_id == "load_save":
            from view.load_game_screen import LoadGameScreen
            self.app.push_screen(LoadGameScreen())

        elif btn_id == "return_to_menu":
            engine.save_settings()
            if engine.settings.get("confirm_return", True):
                self.app.push_screen(ConfirmActionScreen(
                    "返回主菜单",
                    "确定要返回主菜单吗？\n未保存的进度将会丢失。",
                    self._do_return_to_menu
                ))
            else:
                self._do_return_to_menu()

        elif btn_id == "exit_game":
            engine.save_settings()
            if engine.settings.get("confirm_exit", True):
                self.app.push_screen(ConfirmActionScreen(
                    "退出游戏",
                    "确定要退出游戏吗？\n未保存的进度将会丢失。",
                    self._do_exit
                ))
            else:
                self._do_exit()

        elif btn_id == "close_settings_btn":
            engine.save_settings()
            self.action_close()

    def _do_return_to_menu(self):
        while len(self.app.screen_stack) > 1:
            self.app.pop_screen()
        self.app.push_screen(self.app.main_menu_screen)
        self.app.main_menu_screen.check_save_file()

    def _do_exit(self):
        self.app.exit()

    def on_click(self, event):
        if event.control is self:
            self.action_close()

    def action_close(self):
        self.app.engine.save_settings()
        self.app.pop_screen()

        if len(self.app.screen_stack) <= 1:
            if hasattr(self.app.engine, "state") and self.app.engine.state is not None:
                from view.game_menu import GamePlayScreen
                self.app.push_screen(GamePlayScreen())
            else:
                self.app.push_screen(self.app.main_menu_screen)
        else:
            if hasattr(self.app, "main_menu_screen"):
                try:
                    self.app.main_menu_screen.check_save_file()
                except Exception:
                    pass