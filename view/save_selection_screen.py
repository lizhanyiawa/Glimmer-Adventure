import os
import json
from textual.screen import Screen
from textual.widgets import Static, Button
from textual.containers import Vertical

# 存档选择界面
class SaveSelectionScreen(Screen):
    BINDINGS = [
        ("escape", "close", "关闭"),
    ]

    CSS = """
    SaveSelectionScreen { align: center middle; background: rgba(0,0,0,0.8); }
    #save_box { width: 54; border: solid #00ff66; background: #161923; padding: 1 4; }
    .title { text-align: center; color: #00ff66; text-style: bold; margin-bottom: 2; }
    .save_slot_btn { width: 100%; margin: 1 0; background: #23283b; color: white; border: none; }
    .save_slot_btn:hover { background: #00ff66; color: #0b0c10; text-style: bold; }
    .save_slot_btn:disabled { background: #1a1a24; color: #444444; border: none; }
    #close_save_btn { width: 100%; background: #ff007f; color: white; border: none; margin-top: 2; }
    """

    def compose(self):
        with Vertical(id="save_box"):
            yield Static("读取存档", classes="title")
            for i in range(1, 6):
                yield Button(f"存档 {i}", id=f"slot_{i}", classes="save_slot_btn")
            yield Button("[ESC] 返回", id="close_save_btn")

    def on_mount(self):
        self.update_slots()

    def update_slots(self):
        for i in range(1, 6):
            btn = self.query_one(f"#slot_{i}", Button)
            save_path = f"saves/slot_{i}.json"
            if os.path.exists(save_path):
                try:
                    with open(save_path, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    name = data.get("stats", {}).get("player_name", "无名")
                    room = data.get("room_id", "未知")
                    time = data.get("last_saved", "")
                    btn.label = f"存档 {i}: {name} | {room} | {time}"
                    btn.disabled = False
                except Exception:
                    btn.label = f"存档 {i}: (损坏)"
                    btn.disabled = True
            else:
                btn.label = f"存档 {i}: 空"
                btn.disabled = True

    def on_button_pressed(self, event: Button.Pressed):
        btn_id = event.button.id
        if btn_id == "close_save_btn":
            self.action_close()
        elif btn_id.startswith("slot_"):
            slot = int(btn_id.split("_")[1])
            if self.app.engine.load_game(slot):
                self.notify(f"已加载存档 {slot}")
                self.app.pop_screen()
                from view.brighten_screen import BrightenScreen
                self.app.push_screen(BrightenScreen())
            else:
                self.notify("加载失败", title="错误")

    def action_close(self):
        self.app.pop_screen()
