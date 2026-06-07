"""装备界面 — 人物属性扩展"""

from textual.screen import Screen
from textual.widgets import Static, Button
from textual.containers import Vertical, Horizontal
from textual import on


class EquipmentScreen(Screen):
    BINDINGS = [
        ("escape", "close", "关闭"),
    ]

    CSS = """
    EquipmentScreen {
        align: center middle;
        background: rgba(0, 0, 0, 0.75);
    }
    #equip_box {
        width: 72;
        height: auto;
        border: thick #ddaa00;
        background: #161923;
        padding: 1 4;
    }
    .equip_title {
        text-align: center;
        text-style: bold;
        color: #ddaa00;
        margin-bottom: 1;
    }
    .slot_line {
        color: #b2b2b2;
        min-height: 1;
    }
    .slot_name {
        color: #ddaa00;
        text-style: bold;
    }
    .slot_empty {
        color: #666666;
    }
    .slot_stats {
        color: #55cc55;
    }
    .equip_summary {
        color: #888888;
        margin-top: 1;
        border-top: solid #333333;
        padding-top: 1;
    }
    .equip_summary_label {
        color: #ddaa00;
    }
    #equip_btn_row {
        margin-top: 2;
        height: auto;
    }
    .equip_action_btn {
        width: 100%;
        border: none;
        background: #11141e;
        color: #ddaa00;
    }
    .equip_action_btn:hover {
        background: #ddaa00;
        color: #0b0c10;
        text-style: bold;
    }
    """

    def compose(self):
        engine = self.app.engine
        equipment = engine.get_equipment()
        stats = engine.state.stats
        inv = engine.inv_mgr.all()

        # 找出所有可装备物品
        self._equippable = [item for item in inv
                            if engine._items_db.get(item["id"], {}).get("equip_slot")]

        with Vertical(id="equip_box"):
            yield Static("── 装备 ──", classes="equip_title")

            for slot in engine.EQUIP_SLOTS:
                entry = equipment.get(slot)
                if entry:
                    stat_str = ", ".join(
                        f"+{v}{k}" for k, v in entry.get("stats", {}).items()
                    )
                    line = f"[slot_name]{slot.upper()}[/slot_name]: {entry['name']}  [slot_stats]{stat_str}[/slot_stats]"
                else:
                    line = f"[slot_name]{slot.upper()}[/slot_name]: [slot_empty]（空）[/slot_empty]"
                yield Static(line, classes="slot_line")

            # 汇总
            summary = engine.get_equipped_stats_summary()
            if summary:
                summary_str = ", ".join(f"+{v}{k}" for k, v in summary.items())
                yield Static(f"[equip_summary_label]装备加成:[/equip_summary_label] {summary_str}", classes="equip_summary")
            else:
                yield Static("[equip_summary_label]装备加成:[/equip_summary_label] 无", classes="equip_summary")

            with Vertical(id="equip_btn_row"):
                if self._equippable:
                    yield Static("── 可装备物品 ──", classes="equip_title")
                    for item in self._equippable:
                        yield Button(f"{item['name']} x{item.get('qty', 1)}", id=f"eq_{item['id']}", classes="equip_action_btn")
                yield Button("[ESC] 关闭", id="btn_close_equip")

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "btn_close_equip":
            self.action_close()
            return
        if event.button.id.startswith("eq_"):
            item_id = event.button.id[3:]
            self._do_equip(item_id)

    def _do_equip(self, item_id: str):
        engine = self.app.engine
        result = engine.equip(item_id)
        if result["success"]:
            self.notify(result["message"], title="装备")
            # 刷新自身
            self.app.pop_screen()
            self.app.push_screen(EquipmentScreen())
        else:
            self.notify(result["message"], title="无法装备", severity="warning")

    def action_close(self):
        self.app.pop_screen()
