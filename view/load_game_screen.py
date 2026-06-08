from textual.screen import Screen
from textual.widgets import Static, Button
from textual.containers import Vertical, Horizontal
from textual import on

from view.brighten_screen import BrightenScreen


class LoadGameScreen(Screen):
    BINDINGS = [
        ("escape", "close", "关闭"),
    ]

    CSS = """
    LoadGameScreen {
        align: center middle;
        background: rgba(0, 0, 0, 0.7);
    }
    #load_box {
        width: 54;
        border: solid #00ff66;
        background: #161923;
        padding: 1 4;
    }
    .title {
        text-align: center;
        color: #00ff66;
        text-style: bold;
        margin-bottom: 1;
    }
    .save_slot_btn {
        width: 100%;
        margin: 1 0;
        background: #23283b;
        color: white;
        border: none;
    }
    .save_slot_btn:hover {
        background: #00ff66;
        color: #0b0c10;
        text-style: bold;
    }
    #close_load_btn {
        width: 100%;
        background: #ff007f;
        color: white;
        border: none;
        margin-top: 2;
    }
    #close_load_btn:hover {
        background: #ffaa00;
        text-style: bold;
    }
    """

    def compose(self):
        with Vertical(id="load_box"):
            yield Static("读取存档", classes="title")
            for i in range(1, 6):
                yield Button(f"存档 {i}", id=f"slot_{i}", classes="save_slot_btn")
            yield Button("[ESC] 关闭", id="close_load_btn")

    def on_mount(self):
        self.refresh_slots()

    def refresh_slots(self):
        slots = self.app.engine.get_save_slots()
        for s in slots:
            i = s["slot"]
            btn = self.query_one(f"#slot_{i}", Button)
            if s.get("corrupted"):
                btn.label = f"存档 {i}: (损坏)"
            elif s["exists"]:
                name = s.get("player_name", "无名")
                room = s.get("room_id", "未知")
                time = s.get("last_saved", "")
                btn.label = f"存档 {i}: {name} | {room} | {time}"
            else:
                btn.label = f"存档 {i}: 空"
                btn.disabled = True

    def _load_slot(self, slot: int):
        if self.app.engine.load_game(slot):
            self.notify(f"已加载存档 {slot}")
            self.app.pop_screen()
            self.app.push_screen(BrightenScreen())
        else:
            self.notify("加载失败", title="错误")

    def on_button_pressed(self, event: Button.Pressed):
        btn_id = event.button.id
        if btn_id == "close_load_btn":
            self.action_close()
        elif btn_id.startswith("slot_"):
            slot = int(btn_id.split("_")[1])
            slots = self.app.engine.get_save_slots()
            has_data = any(s["slot"] == slot and s["exists"] for s in slots)
            if has_data:
                self.app.push_screen(LoadConfirmScreen(slot, self._load_slot))

    def on_click(self, event):
        if event.control is self:
            self.action_close()

    def action_close(self):
        self.app.pop_screen()


class LoadConfirmScreen(Screen):
    BINDINGS = [
        ("y", "confirm", "确认"),
        ("n", "cancel", "取消"),
        ("escape", "cancel", "取消"),
    ]

    CSS = """
    LoadConfirmScreen {
        align: center middle;
        background: rgba(0, 0, 0, 0.0);
    }
    #confirm_box {
        width: 48;
        height: auto;
        border: heavy #00ff66;
        background: #101a10;
        padding: 1 4;
    }
    .confirm_title {
        text-align: center;
        text-style: bold;
        color: #00ff66;
        margin-bottom: 1;
    }
    .confirm_text {
        text-align: center;
        margin-bottom: 2;
        color: #e5e5e5;
    }
    #confirm_btn_box {
        content-align: center middle;
        height: auto;
        width: 100%;
    }
    .confirm_slot_btn {
        width: 100%;
        margin: 1 0;
        background: #23283b;
        color: white;
        border: none;
    }
    .confirm_slot_btn:hover {
        background: #00ff66;
        color: #0b0c10;
        text-style: bold;
    }
    """

    def __init__(self, slot: int, on_confirm):
        super().__init__()
        self._slot = slot
        self._on_confirm = on_confirm

    def compose(self):
        with Vertical(id="confirm_box"):
            yield Static("读取存档确认", classes="confirm_title")
            yield Static(f"确定要读取存档 {self._slot} 吗？\n当前未保存的进度将会丢失。", classes="confirm_text")
            yield Static("按 Y 确认，N 或 ESC 取消", classes="confirm_text")
            with Horizontal(id="confirm_btn_box"):
                yield Button("[Y] 确认", id="btn_yes", classes="confirm_slot_btn")
                yield Button("[N] 取消", id="btn_no", classes="confirm_slot_btn")

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "btn_yes":
            self.app.pop_screen()
            self._on_confirm(self._slot)
        elif event.button.id == "btn_no":
            self.app.pop_screen()

    def on_click(self, event):
        if event.control is self:
            self.app.pop_screen()

    def action_confirm(self):
        self.app.pop_screen()
        self._on_confirm(self._slot)

    def action_cancel(self):
        self.app.pop_screen()
