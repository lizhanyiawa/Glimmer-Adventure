from textual.screen import Screen
from textual.widgets import Static, Button
from textual.containers import Vertical
from view.global_settings import ConfirmActionScreen


class SaveGameScreen(Screen):
    BINDINGS = [
        ("escape", "close", "关闭"),
    ]

    CSS = """
    SaveGameScreen {
        align: center middle;
        background: rgba(0, 0, 0, 0.8);
    }
    #save_box {
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
    .save_slot_btn {
        width: 100%;
        margin: 1 0;
        background: #23283b;
        color: white;
        border: none;
    }
    .save_slot_btn:hover {
        background: #ffaa00;
        color: #0b0c10;
        text-style: bold;
    }
    #close_save_btn {
        width: 100%;
        background: #ff007f;
        color: white;
        border: none;
        margin-top: 2;
    }
    #close_save_btn:hover {
        background: #ffaa00;
        text-style: bold;
    }
    """

    def compose(self):
        with Vertical(id="save_box"):
            yield Static("保存游戏", classes="title")
            for i in range(1, 6):
                yield Button(f"存档 {i}", id=f"slot_{i}", classes="save_slot_btn")
            yield Button("[ESC] 返回", id="close_save_btn")

    def on_mount(self):
        self.update_slots()

    def update_slots(self):
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

    def on_button_pressed(self, event: Button.Pressed):
        btn_id = event.button.id
        if btn_id == "close_save_btn":
            self.action_close()
        elif btn_id.startswith("slot_"):
            slot = int(btn_id.split("_")[1])
            slots = self.app.engine.get_save_slots()
            has_data = any(s["slot"] == slot and s["exists"] for s in slots)

            confirm = self.app.engine.settings.get("confirm_save", True)
            if has_data and confirm:
                self.app.push_screen(ConfirmActionScreen(
                    f"覆盖存档 {slot}",
                    f"该槽位已有存档，确定要覆盖吗？",
                    lambda s=slot: self._do_save(s)
                ))
            else:
                self._do_save(slot)

    def _do_save(self, slot: int):
        if self.app.engine.save_game(slot):
            self.notify(f"已保存到存档 {slot}")
            self.update_slots()
            self.app.pop_screen()
        else:
            self.notify("保存失败", title="错误")

    def on_click(self, event):
        if event.control is self:
            self.action_close()

    def action_close(self):
        self.app.pop_screen()