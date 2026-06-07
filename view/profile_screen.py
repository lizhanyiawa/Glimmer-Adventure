from textual.screen import Screen
from textual.widgets import Static, Button
from textual.containers import Vertical, Horizontal


class ProfileScreen(Screen):
    BINDINGS = [
        ("escape", "close", "关闭"),
    ]

    CSS = """
    ProfileScreen {
        align: center middle;
        background: rgba(0,0,0,0.7);
    }
    #profile_box {
        width: 60;
        height: auto;
        border: thick #ff007f;
        background: #161923;
        padding: 1 4;
    }
    .prof_title {
        text-align: center;
        text-style: bold;
        color: #ff007f;
        margin-bottom: 1;
    }
    .stat_line {
        color: #b2b2b2;
        text-align: left;
    }
    #equip_btn {
        width: 100%;
        background: #23283b;
        color: #ddaa00;
        border: none;
        margin-top: 1;
    }
    #equip_btn:hover {
        background: #ddaa00;
        text-style: bold;
        color: #0b0c10;
    }
    #close_prof_btn {
        width: 100%;
        background: #23283b;
        color: white;
        border: none;
        margin-top: 2;
    }
    #close_prof_btn:hover {
        background: #ffaa00;
        text-style: bold;
    }
    """

    def compose(self):
        engine = self.app.engine
        stats = engine.state.stats

        with Vertical(id="profile_box"):
            yield Static("人物详情", classes="prof_title")
            yield Static(f"名字: {stats.get('player_name', '无名')}", classes="stat_line")
            yield Static(f"生命: {stats.get('hp', 0)}/{stats.get('max_hp', 100)}", classes="stat_line")
            yield Static(f"理智: {stats.get('san', 0)}", classes="stat_line")
            yield Static(f"污染: {stats.get('corruption', 0)}", classes="stat_line")

            yield Static("--- 属性 ---", classes="prof_title")
            yield Static(f"攻击: {stats.get('attack', 0)}", classes="stat_line")
            yield Static(f"防御: {stats.get('defense', 0)}", classes="stat_line")
            yield Static(f"智力: {stats.get('intelligence', 0)}", classes="stat_line")
            yield Static(f"敏捷: {stats.get('agility', 0)}", classes="stat_line")

            yield Button("[E] 装备", id="equip_btn")
            yield Button("[ESC] 关闭", id="close_prof_btn")

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "close_prof_btn":
            self.action_close()
        elif event.button.id == "equip_btn":
            from view.equipment_screen import EquipmentScreen
            self.app.push_screen(EquipmentScreen())

    def action_close(self):
        self.app.pop_screen()