from textual.screen import Screen
from textual.widgets import Static, Button, RichLog, ProgressBar
from textual.containers import Horizontal, Vertical, Container
from textual.events import Key
from textual import on, work
from rich.text import Text

from engine.effects import TypewriterLog, convert_custom_tags

STATS_NAMES = {
    "hp": "生命",
    "max_hp": "最大生命",
    "san": "理智",
    "corruption": "腐化",
    "attack": "攻击",
    "defense": "防御",
    "intelligence": "智力",
    "agility": "敏捷",
    "coins": "铜币",
}

class LocationWidget(Static):
    DEFAULT_CLASSES = "location_widget"
    def update_location(self, location: str):
        self.update(f"位置: {location}")

class StatBar(Vertical):
    """状态栏显示 HP 和 SAN"""
    DEFAULT_CLASSES = "stat_bar"
    
    def __init__(self, label: str, value: int, max_value: int, color: str, **kwargs):
        super().__init__(**kwargs)
        self._label_text = label
        self._color = color
        self._value = value
        self._max_value = max_value

    def compose(self):
        yield Static(f"{self._label_text}: {self._value}/{self._max_value}", id=f"{self.id}_label")
        yield ProgressBar(total=self._max_value, show_eta=False, show_percentage=False, id=f"{self.id}_bar")

    def on_mount(self):
        self.query_one(ProgressBar).update(progress=self._value)
        self.query_one(ProgressBar).styles.accent = self._color

    def update_stat(self, value: int, max_value: int):
        self._value = value
        self._max_value = max_value
        self.query_one(Static).update(f"{self._label_text}: {self._value}/{self._max_value}")
        self.query_one(ProgressBar).update(total=max_value, progress=value)

# 游戏主界面
class GamePlayScreen(Screen):
    BINDINGS = [
        ("1", "option1", "选项 1"),
        ("2", "option2", "选项 2"),
        ("3", "option3", "选项 3"),
        ("4", "option4", "选项 4"),
        ("5", "option5", "选项 5"),
        ("6", "option6", "选项 6"),
        ("p", "profile", "人物"),
        ("i", "inventory", "物品"),
        ("d", "diary", "日记"),
        ("s", "save", "保存"),
        ("o", "settings", "设置"),
        ("escape", "menu", "菜单"),
    ]

    CSS = """
    GamePlayScreen {
        padding: 1;
        background: #0b0c10;
        color: #c5c6c7;
    }
    #status_bar {
        height: 5;
        background: #1f2833;
        border: solid #45f3ff;
        margin-bottom: 1;
        padding: 0 1;
    }
    #status_layout {
        height: 100%;
    }
    #stats_left {
        width: 30%;
        height: 100%;
        padding: 0 1;
    }
    #location_center {
        width: 40%;
        height: 100%;
        content-align: center middle;
    }
    #stats_right {
        width: 30%;
        height: 100%;
        padding: 0 1;
        content-align: right middle;
    }
    .stat_bar {
        height: 2;
        margin: 0;
    }
    .stat_bar ProgressBar {
        height: 1;
        margin: 0;
    }
    .stat_bar Static {
        text-style: bold;
    }
    .location_widget {
        color: #ffaa00;
        text-align: center;
        content-align: center middle;
        text-style: bold;
        width: 100%;
    }
    .status_tag {
        color: #66fcf1;
        text-align: right;
    }
    #main_viewport {
        height: 16;
        margin-bottom: 1;
    }
    #story_box {
        width: 65%;
        height: 100%;
        border: solid #45f3ff;
        background: #1f2833;
        padding: 1 2;
    }
    #right_panel {
        width: 35%;
        height: 100%;
        margin-left: 1;
    }
    #history_box {
        width: 100%;
        height: 1fr;
        border: dashed #555555;
        background: #0f1016;
    }
    #tracked_task {
        width: 100%;
        height: 3;
        border: solid #e6b800;
        background: #1a1a10;
        color: #e6b800;
        content-align: center middle;
        text-align: center;
        text-style: bold;
    }
    .tracked_empty {
        border: dashed #333333 !important;
        background: #0f1016 !important;
        color: #555555 !important;
        text-style: none !important;
    }
    #bottom_console {
        height: 12;
    }
    #story_options {
        width: 65%;
        layout: grid;
        grid-size: 3 2;
        grid-columns: 1fr 1fr 1fr;
        grid-rows: 1fr 1fr;
        grid-gutter: 1 2;
    }
    #system_options {
        width: 35%;
        margin-left: 1;
    }
    #left_buttons {
        width: 1fr;
        height: 100%;
        margin-right: 1;
    }
    #right_buttons {
        width: 1fr;
        height: 100%;
    }
    .opt_btn {
        background: #11141e;
        border: solid #45f3ff;
        color: #66fcf1;
        width: 100%;
        height: 100%;
        content-align: center middle;
    }
    .opt_btn:hover {
        background: #66fcf1;
        color: #0b0c10;
        text-style: bold;
    }
    .opt_btn:disabled {
        background: #1a1a24;
        color: #444444;
        border: solid #333333;
    }
    .sys_btn {
        background: #1f2833;
        border: none;
        color: #ffffff;
        width: 100%;
        height: 2;
        margin: 0;
    }
    #btn_profile:hover {
        background: #ff007f;
        text-style: bold;
    }
    #btn_inventory:hover {
        background: #66fcf1;
        color: #0b0c10;
        text-style: bold;
    }
    #btn_diary:hover {
        background: #e6b800;
        color: #0b0c10;
        text-style: bold;
    }
    #btn_diary:disabled {
        background: #1f2833;
        color: #555555;
        text-style: none;
    }
    .diary_flash {
        background: #ffe066 !important;
        color: #0b0c10 !important;
        text-style: bold;
    }
    #btn_save:hover {
        background: #00ff66;
        color: #0b0c10;
        text-style: bold;
    }
    #btn_menu_settings:hover {
        background: #ffaa00;
        color: #0b0c10;
        text-style: bold;
    }
    #btn_shop:hover {
        background: #ffaa00;
        color: #0b0c10;
        text-style: bold;
    }
    """

    def compose(self):
        engine = self.app.engine
        stats = engine.state.stats

        with Container(id="status_bar"):
            with Horizontal(id="status_layout"):
                with Vertical(id="stats_left"):
                    yield StatBar("HP", stats.get("hp", 100), stats.get("max_hp", 100), "#ff0000", id="pb_hp")
                    yield StatBar("SAN", stats.get("san", 100), 100, "#00ff00", id="pb_san")
                with Container(id="location_center"):
                    yield LocationWidget("位置: 加载中...", id="lbl_location")
                with Vertical(id="stats_right"):
                    yield Static(f"ATK: {stats.get('attack', 0)}  DEF: {stats.get('defense', 0)}", classes="status_tag", id="txt_combat")
                    yield Static(f"INT: {stats.get('intelligence', 0)}  AGI: {stats.get('agility', 0)}", classes="status_tag", id="txt_mind")
                    yield Static(f"COR: {stats.get('corruption', 0)}%", classes="status_tag", id="txt_wealth")

        with Horizontal(id="main_viewport"):
            yield TypewriterLog("", id="story_box")
            with Vertical(id="right_panel"):
                yield RichLog(id="history_box", markup=True, wrap=True, max_lines=engine.settings.get("history_lines", 200))
                yield Static("", id="tracked_task")

        with Horizontal(id="bottom_console"):
            with Container(id="story_options"):
                yield Button("[1] 选项 1", id="opt1", classes="opt_btn")
                yield Button("[2] 选项 2", id="opt2", classes="opt_btn")
                yield Button("[3] 选项 3", id="opt3", classes="opt_btn")
                yield Button("[4] 选项 4", id="opt4", classes="opt_btn")
                yield Button("[5] 选项 5", id="opt5", classes="opt_btn")
                yield Button("[6] 选项 6", id="opt6", classes="opt_btn")
            with Horizontal(id="system_options"):
                with Vertical(id="left_buttons"):
                    yield Button("[P] 人物", id="btn_profile", classes="sys_btn")
                    yield Button("[I] 物品", id="btn_inventory", classes="sys_btn")
                    yield Button("[S] 保存", id="btn_save", classes="sys_btn")
                    yield Button("[ ] ---", id="btn_empty1", classes="sys_btn", disabled=True)
                    yield Button("[ ] ---", id="btn_empty2", classes="sys_btn", disabled=True)
                with Vertical(id="right_buttons"):
                    self._btn_diary = Button("[ ] ---", id="btn_diary", classes="sys_btn", disabled=True)
                    yield self._btn_diary
                    yield Button("[O] 设置", id="btn_menu_settings", classes="sys_btn")
                    yield Button("[T] 交易", id="btn_shop", classes="sys_btn")
                    yield Button("[ ] ---", id="btn_empty4", classes="sys_btn", disabled=True)
                    yield Button("[ ] ---", id="btn_empty5", classes="sys_btn", disabled=True)

    def on_mount(self):
        self.call_after_refresh(self.load_current_room)
        self._refresh_diary_button()
        self._refresh_tracked_task()
        self._update_ui_colors()

    def on_screen_resumed(self):
        """从子界面（商店/战斗等）返回时刷新状态栏。"""
        self._refresh_status_bar()
        self._refresh_diary_button()
        self._refresh_tracked_task()
        self._update_ui_colors()

    def _refresh_status_bar(self):
        """刷新 HP/SAN/属性/铜币 等状态显示。使用目标更新，避免闪烁。"""
        stats = self.app.engine.state.stats
        self.query_one("#pb_hp", StatBar).update_stat(stats.get("hp", 100), stats.get("max_hp", 100))
        self.query_one("#pb_san", StatBar).update_stat(stats.get("san", 100), 100)
        self.query_one("#txt_combat", Static).update(f"ATK: {stats.get('attack', 0)}  DEF: {stats.get('defense', 0)}")
        self.query_one("#txt_mind", Static).update(f"INT: {stats.get('intelligence', 0)}  AGI: {stats.get('agility', 0)}")
        self.query_one("#txt_wealth", Static).update(f"COR: {stats.get('corruption', 0)}%")

    def _refresh_tracked_task(self):
        engine = self.app.engine
        tracked_id = engine.get_flag("sys_tracked_task_id", "")
        tasks = engine.state.diary.get("tasks", [])
        tracked_widget = self.query_one("#tracked_task", Static)

        if tracked_id:
            for t in tasks:
                if t.get("id") == tracked_id:
                    done = t.get("done", False)
                    prefix = "✓ " if done else ""
                    tracked_widget.update(f"追踪任务: {prefix}{t.get('title', '???')}")
                    tracked_widget.set_class(False, "tracked_empty")
                    return
            engine.delete_flag("sys_tracked_task_id")
            tracked_widget.update("")
            tracked_widget.set_class(True, "tracked_empty")
        else:
            tracked_widget.update("")
            tracked_widget.set_class(True, "tracked_empty")

    def _update_ui_colors(self):
        engine = self.app.engine
        stats = engine.state.stats
        hp = stats.get("hp", 100)
        max_hp = stats.get("max_hp", 100)
        san = stats.get("san", 100)
        is_dialogue = bool(engine.state.dialogue_id)

        hp_ratio = hp / max(max_hp, 1)

        if is_dialogue:
            bg_color, border_color = "#0a1a0a", "#00ff66"
        elif hp_ratio < 0.1:
            bg_color, border_color = "#1a0505", "#ff2222"
        elif san < 30:
            bg_color, border_color = "#0f0a1a", "#cc44ff"
        elif hp_ratio < 0.3:
            bg_color, border_color = "#1a1a05", "#ffaa00"
        else:
            bg_color, border_color = "#0b0c10", "#45f3ff"

        self.styles.background = bg_color
        self.query_one("#status_bar").styles.border = ("solid", border_color)
        self.query_one("#story_box").styles.border = ("solid", border_color)

        for btn_id in ["opt1", "opt2", "opt3", "opt4", "opt5", "opt6"]:
            try:
                btn = self.query_one(f"#{btn_id}", Button)
                if not btn.disabled:
                    btn.styles.border = ("solid", border_color)
                    btn.styles.color = border_color
            except Exception:
                pass

    def _refresh_diary_button(self):
        engine = self.app.engine
        state = engine.state
        inventory = state.inventory
        has_diary_item = any(item.get("id") in ["diary", "old_diary"] for item in inventory)
        has_diary_flag = engine.get_flag("has_diary", False)
        has_unread = engine.get_flag("sys_diary_unread", False)

        has_diary = has_diary_item or has_diary_flag

        if not has_diary:
            self._btn_diary.label = "[ ] ---"
            self._btn_diary.disabled = True
            self._btn_diary.styles.color = "#ffffff"
            self._btn_diary.styles.text_style = "none"
        else:
            self._btn_diary.label = "[D] 日记"
            self._btn_diary.disabled = False
            self._btn_diary.styles.color = "#e6b800"
            self._btn_diary.styles.text_style = "bold"
            if has_unread:
                self._start_diary_flash()

    def _start_diary_flash(self):
        if hasattr(self, "_diary_flash_timer") and self._diary_flash_timer is not None:
            return
        self._flash_on = True
        self._flash_count = 0
        self._diary_flash_timer = self.set_interval(0.4, self._diary_flash_tick)

    def _diary_flash_tick(self):
        self._flash_count += 1
        if self._flash_count > 12:
            self._btn_diary.set_class(False, "diary_flash")
            if hasattr(self, "_diary_flash_timer") and self._diary_flash_timer is not None:
                self._diary_flash_timer.stop()
                self._diary_flash_timer = None
            return
        self._flash_on = not self._flash_on
        self._btn_diary.set_class(self._flash_on, "diary_flash")

    def load_current_room(self):
        engine = self.app.engine
        room_id = engine.state.room_id
        dialogue_id = engine.state.dialogue_id
        stats = engine.state.stats

        self._refresh_status_bar()
        self._update_ui_colors()

        node_data = None
        is_dialogue = False

        if dialogue_id:
            node_data = engine.get_dialogue(dialogue_id)
            is_dialogue = True

        if not node_data:
            node_data = engine.get_room(room_id)
            is_dialogue = False

        if not node_data:
            self.query_one("#story_box", TypewriterLog).update(f"[错误] 数据不存在 (Room: {room_id}, Dialogue: {dialogue_id})")
            return

        if is_dialogue:
            room_data = engine.get_room(room_id)
            location_title = room_data.get("title", room_id) if room_data else "未知地点"
            self.query_one("#lbl_location", LocationWidget).update_location(f"{location_title} (对话中)")
        else:
            self.query_one("#lbl_location", LocationWidget).update_location(node_data.get("title", room_id))

        btn_map = ["opt1", "opt2", "opt3", "opt4", "opt5", "opt6"]
        for btn_id in btn_map:
            btn = self.query_one(f"#{btn_id}", Button)
            btn.label = "[·] 聆听常识流动中..."
            btn.disabled = True

        if is_dialogue:
            speaker = node_data.get("speaker", "???")
            story_text = node_data.get("text", "")

            if speaker:
                full_text = f"【 {speaker} 】\n\n{story_text}"
                history_log = self.query_one("#history_box", RichLog)
                history_log.write(f"[bold cyan]【 {speaker} 】[/bold cyan]")
                history_log.write(convert_custom_tags(story_text))
            else:
                full_text = story_text
        else:
            story_text = engine.resolve_room_description(node_data)
            full_text = f"【 {node_data.get('title', room_id)} 】\n\n{story_text}"

            history_log = self.query_one("#history_box", RichLog)
            history_log.write(f"\n[bold white]【 {node_data.get('title', room_id)} 】[/bold white]")
            history_log.write(convert_custom_tags(story_text))

        def show_options_after_typing():
            self.refresh_options(node_data)

        self.query_one("#story_box", TypewriterLog).type_text(
            full_text,
            speed=engine.settings.get("text_speed", "medium"),
            on_complete=show_options_after_typing
        )

    def refresh_options(self, room_data: dict):
        options = room_data.get("options", [])
        engine = self.app.engine

        compacted = self._get_compacted_options(options)
        self._compacted_mapping = compacted

        btn_map = ["opt1", "opt2", "opt3", "opt4", "opt5", "opt6"]
        for i, btn_id in enumerate(btn_map):
            btn = self.query_one(f"#{btn_id}", Button)
            if i < len(compacted):
                option, disabled, text = compacted[i]
                btn.label = f"[{i+1}] {text}"
                btn.disabled = disabled
            else:
                btn.label = f"[{i+1}] ---"
                btn.disabled = True

        self._update_ui_colors()

    def _get_compacted_options(self, options):
        engine = self.app.engine
        result = []
        for option in options:
            state = engine.check_option_visible(option)
            if state == "excluded":
                continue
            if state == "visible":
                result.append((option, False, option.get("text", "选项")))
            else:
                hidden_text = option.get("hidden_text")
                if hidden_text:
                    result.append((option, True, hidden_text))
        return result

    # 键盘动作：选项1-6
    def action_option1(self): self.select_option(0)
    def action_option2(self): self.select_option(1)
    def action_option3(self): self.select_option(2)
    def action_option4(self): self.select_option(3)
    def action_option5(self): self.select_option(4)
    def action_option6(self): self.select_option(5)

    def select_option(self, index: int):
        compacted = getattr(self, '_compacted_mapping', [])
        if index >= len(compacted):
            return
        option, disabled, _ = compacted[index]
        if disabled:
            return

        engine = self.app.engine

        result = engine.select_option(option)
        
        history_log = self.query_one("#history_box", RichLog)
        history_log.write(f"\n[bold white]【你】[/bold white][cyan]「{option.get('text', '')}」[/cyan]")

        effects = result.get("effects_applied", {})

        changes = engine.resolve_stats_changes(effects)
        if changes:
            change_msgs = []
            for c in changes:
                k, v = c["key"], c["delta"]
                display_name = STATS_NAMES.get(k, k)
                sign = "+" if v > 0 else ""
                if k == "corruption":
                    color = "red" if v > 0 else "green"
                else:
                    color = "green" if v > 0 else "red"

                change_msgs.append(f"[{color}]{display_name} {sign}{v}[/{color}]")

            if change_msgs:
                change_str = ", ".join(change_msgs)
                history_log.write(f"✦ 状态变更: {change_str}")
                plain_str = change_str.replace("[green]", "").replace("[/green]", "").replace("[red]", "").replace("[/red]", "")
                self.notify(f"状态发生变化：{plain_str}", title="提示", timeout=3)

        battle_id = option.get("battle")
        if battle_id:
            from view.battle_screen import BattleScreen
            post_battle = option.get("post_battle", {})
            self.app.push_screen(BattleScreen(battle_id, post_battle))
            return

        shop_id = option.get("shop")
        if shop_id:
            from view.shop_screen import ShopScreen
            self.app.push_screen(ShopScreen(shop_id))
            return

        self.load_current_room()
        self._refresh_diary_button()
        self._refresh_tracked_task()

    def action_profile(self):
        from view.profile_screen import ProfileScreen
        self.app.push_screen(ProfileScreen())

    def action_inventory(self):
        from view.inventory_screen import InventoryScreen
        self.app.push_screen(InventoryScreen())

    def action_diary(self):
        from view.diary_screen import DiaryScreen
        self.app.push_screen(DiaryScreen())

    def action_save(self):
        from view.save_game_screen import SaveGameScreen
        self.app.push_screen(SaveGameScreen())

    def action_settings(self):
        from view.global_settings import GlobalSettingsScreen
        self.app.push_screen(GlobalSettingsScreen())

    def action_shop(self):
        room = self.app.engine.get_room(self.app.engine.state.room_id)
        shop_id = room.get("shop") if room else None
        if shop_id:
            from view.shop_screen import ShopScreen
            self.app.push_screen(ShopScreen(shop_id))
        else:
            self.notify("这里没有可以交易的对象", title="提示", timeout=2)

    def action_menu(self):
        if len(self.app.screen_stack) <= 1:
            return
        self.app.pop_screen()
        if self.app.main_menu_screen not in self.app.screen_stack:
            self.app.push_screen(self.app.main_menu_screen)

    def on_button_pressed(self, event: Button.Pressed):
        btn_id = event.button.id

        if btn_id == "btn_profile":
            self.action_profile()
        elif btn_id == "btn_inventory":
            self.action_inventory()
        elif btn_id == "btn_diary":
            self.action_diary()
        elif btn_id == "btn_save":
            self.action_save()
        elif btn_id == "btn_menu_settings":
            self.action_settings()
        elif btn_id == "btn_shop":
            self.action_shop()
        elif btn_id in ("opt1", "opt2", "opt3", "opt4", "opt5", "opt6"):
            index = int(btn_id[-1]) - 1
            self.select_option(index)
