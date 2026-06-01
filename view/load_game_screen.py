from textual.screen import Screen
from textual.widgets import Static, Button, ListView, ListItem
from textual.containers import Vertical
from textual import on

from view.brighten_screen import BrightenScreen


class LoadGameScreen(Screen):
    BINDINGS = [
        ("escape", "close", "关闭"),
        ("enter", "select", "选择"),
        ("up", "focus_previous", "上一个"),
        ("down", "focus_next", "下一个"),
    ]

    CSS = """
    LoadGameScreen {
        align: center middle;
        background: rgba(0, 0, 0, 0.8);
    }
    #load_box {
        width: 60;
        height: 22;
        border: solid #00ff66;
        background: #161923;
        padding: 1 2;
    }
    .title {
        text-align: center;
        color: #00ff66;
        text-style: bold;
        margin-bottom: 1;
    }
    #save_list {
        background: #11141e;
        border: solid #333333;
        margin-bottom: 1;
        height: 14;
    }
    .save_item_label {
        color: #d5d5d5;
        padding: 0 1;
    }
    #close_btn {
        width: 100%;
        background: #ff007f;
        color: white;
        border: none;
    }
    #close_btn:hover {
        background: #ffaa00;
        text-style: bold;
    }
    """

    def compose(self):
        with Vertical(id="load_box"):
            yield Static("读取存档", classes="title")
            yield ListView(id="save_list")
            yield Static("↑↓ 选择  Enter 确认  ESC 关闭", classes="title")
            yield Button("[ESC] 关闭", id="close_btn")

    def on_mount(self):
        self.refresh_save_list()

    def refresh_save_list(self):
        list_view = self.query_one("#save_list", ListView)
        list_view.clear()

        slots = self.app.engine.get_save_slots()
        for s in slots:
            slot_id = s["slot"]
            if s.get("corrupted"):
                label = f" 槽位 [{slot_id}] · (损坏)"
                item = ListItem(Static(label, classes="save_item_label"), id=f"slot_{slot_id}")
                item.disabled = True
            elif s["exists"]:
                name = s.get("player_name", "无名")
                room = s.get("room_id", "未知")
                time = s.get("last_saved", "")
                label = f" 槽位 [{slot_id}] · {name} | {room} | {time}"
                item = ListItem(Static(label, classes="save_item_label"), id=f"slot_{slot_id}")
            else:
                label = f" 槽位 [{slot_id}] · (空)"
                item = ListItem(Static(label, classes="save_item_label"), id=f"slot_{slot_id}")
                item.disabled = True
            list_view.append(item)

    def _load_slot(self, slot: int):
        if self.app.engine.load_game(slot):
            self.notify(f"已加载存档 {slot}")
            self.app.pop_screen()
            self.app.push_screen(BrightenScreen())
        else:
            self.notify("加载失败", title="错误")

    @on(ListView.Selected)
    def on_save_selected(self, event: ListView.Selected):
        slot_id_str = event.item.id
        if not slot_id_str or not slot_id_str.startswith("slot_"):
            return
        slot = int(slot_id_str.split("_")[1])
        self._load_slot(slot)

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "close_btn":
            self.action_close()

    def action_select(self):
        list_view = self.query_one("#save_list", ListView)
        selected = list_view.highlighted_child
        if selected and not selected.disabled:
            slot_id_str = selected.id
            if slot_id_str and slot_id_str.startswith("slot_"):
                slot = int(slot_id_str.split("_")[1])
                self._load_slot(slot)

    def action_close(self):
        self.app.pop_screen()