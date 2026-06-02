"""战斗界面"""

from textual.screen import Screen
from textual.widgets import Static, Button, ProgressBar
from textual.containers import Vertical, Horizontal, Container
from rich.text import Text

from engine.effects import TypewriterLog, convert_custom_tags
from engine.battle import BattleManager


class BattleScreen(Screen):
    BINDINGS = [
        ("1", "action1", "攻击"),
        ("2", "action2", "防御"),
        ("3", "action3", "逃跑"),
        ("4", "action4", "道具"),
        ("escape", "close", "关闭"),
    ]

    CSS = """
    BattleScreen {
        background: #f5f0e8;
        padding: 1;
    }

    #battle_top {
        height: 5;
        background: #e8e0d0;
        border: solid #8b7355;
        margin-bottom: 1;
        padding: 0 1;
    }
    #battle_top Horizontal {
        height: 100%;
    }
    #player_panel {
        width: 50%;
        height: 100%;
        padding: 0 1;
        content-align: left middle;
    }
    #enemy_panel {
        width: 50%;
        height: 100%;
        padding: 0 1;
        content-align: right middle;
    }
    .battle_name {
        color: #333333;
        text-style: bold;
    }
    .battle_hp_label {
        color: #555555;
    }
    .battle_stat_bar {
        height: 2;
    }

    #battle_middle {
        height: 16;
        margin-bottom: 1;
    }
    #battle_story {
        width: 65%;
        height: 100%;
        border: solid #8b7355;
        background: #faf8f2;
        padding: 1 2;
        color: #333333;
    }
    #battle_history {
        width: 35%;
        height: 100%;
        border: dashed #8b7355;
        background: #f0ece0;
        margin-left: 1;
        color: #555555;
    }

    #battle_bottom {
        height: 5;
    }
    #battle_options {
        width: 100%;
        height: 100%;
        layout: grid;
        grid-size: 4 1;
        grid-columns: 1fr 1fr 1fr 1fr;
        grid-gutter: 1 2;
    }
    .battle_btn {
        background: #e8e0d0;
        border: solid #8b7355;
        color: #333333;
        width: 100%;
        height: 100%;
        content-align: center middle;
        text-style: bold;
    }
    .battle_btn:hover {
        background: #d4c4a8;
        color: #1a1a1a;
    }
    .battle_btn:disabled {
        background: #e0dcd0;
        color: #aaaaaa;
        border: solid #cccccc;
    }

    #battle_hp_bar {
        width: 100%;
        height: 1;
    }
    #battle_hp_bar > .bar--bar {
        background: #cc3333;
    }
    #enemy_hp_bar {
        width: 100%;
        height: 1;
    }
    #enemy_hp_bar > .bar--bar {
        background: #cc3333;
    }
    """

    def __init__(self, enemy_id: str):
        super().__init__()
        self._enemy_id = enemy_id
        self._bm: BattleManager | None = None
        self._waiting_input = False

    def compose(self):
        with Container(id="battle_top"):
            with Horizontal():
                with Vertical(id="player_panel"):
                    yield Static("", id="player_name", classes="battle_name")
                    yield Static("", id="player_hp_label", classes="battle_hp_label")
                    yield ProgressBar(total=100, show_eta=False, show_percentage=False, id="battle_hp_bar")
                with Vertical(id="enemy_panel"):
                    yield Static("", id="enemy_name", classes="battle_name")
                    yield Static("", id="enemy_hp_label", classes="battle_hp_label")
                    yield ProgressBar(total=100, show_eta=False, show_percentage=False, id="enemy_hp_bar")

        with Horizontal(id="battle_middle"):
            yield TypewriterLog("", id="battle_story")
            yield Static("", id="battle_history")

        with Horizontal(id="battle_bottom"):
            with Horizontal(id="battle_options"):
                yield Button("[1] 攻击", id="btn_attack", classes="battle_btn")
                yield Button("[2] 防御", id="btn_defend", classes="battle_btn")
                yield Button("[3] 逃跑", id="btn_flee", classes="battle_btn")
                yield Button("[4] 道具", id="btn_item", classes="battle_btn", disabled=True)

    def on_mount(self):
        self._bm = BattleManager(self.app.engine, self._enemy_id)
        self._refresh_hp_bars()
        self._update_enemy_display()

        encounter_text = self._bm.enemy_narrative.get("encounter", f"{self._bm.enemy.name}出现了！")
        self._write_history(encounter_text)
        self._bm.rebuild_turn_order()

        story_box = self.query_one("#battle_story", TypewriterLog)
        story_box.type_text(
            encounter_text,
            speed="medium",
            on_complete=self._start_turn,
        )

    # ── HP bar ──
    def _refresh_hp_bars(self):
        bm = self._bm
        max_hp = bm.player.max_hp

        self.query_one("#battle_hp_bar", ProgressBar).update(
            total=max_hp, progress=bm.player.hp
        )

        e_max = bm.enemy.max_hp
        self.query_one("#enemy_hp_bar", ProgressBar).update(
            total=e_max, progress=bm.enemy.hp
        )

        self.query_one("#player_hp_label", Static).update(
            f"HP: {bm.player.hp}/{bm.player.max_hp}"
        )
        self.query_one("#enemy_hp_label", Static).update(
            f"HP: {bm.enemy.hp}/{bm.enemy.max_hp}"
        )
        self.query_one("#player_name", Static).update(bm.player.name)
        self.query_one("#enemy_name", Static).update(bm.enemy.name)

    def _update_enemy_display(self):
        bm = self._bm
        self.query_one("#enemy_name", Static).update(bm.enemy.name)

    def _write_history(self, text: str):
        converted = convert_custom_tags(text)
        history = self.query_one("#battle_history", Static)
        current = history.renderable if history.renderable else Text("")
        if isinstance(current, str):
            current = Text(current)
        new_text = Text.assemble(current, "\n", Text.from_markup(converted))
        history.update(new_text)

    # ── 回合流 ──
    def _start_turn(self):
        if self._bm.battle_over:
            self._end_battle()
            return
        self._bm.rebuild_turn_order()
        self._refresh_hp_bars()

        if self._bm.is_player_turn():
            self._enable_buttons()
        else:
            self._disable_buttons()
            self._enemy_turn()

    def _disable_buttons(self):
        for bid in ["btn_attack", "btn_defend", "btn_flee", "btn_item"]:
            self.query_one(f"#{bid}", Button).disabled = True

    def _enable_buttons(self):
        self.query_one("#btn_attack", Button).disabled = False
        self.query_one("#btn_defend", Button).disabled = False
        self.query_one("#btn_flee", Button).disabled = False
        self.query_one("#btn_item", Button).disabled = True

    # ── 玩家行动 ──
    def _player_attack(self):
        self._disable_buttons()
        result = self._bm.player_attack()
        self._write_history(result)
        self._refresh_hp_bars()
        self.query_one("#battle_story", TypewriterLog).type_text(
            result, speed="medium", on_complete=self._start_turn
        )

    def _player_defend(self):
        self._disable_buttons()
        result = self._bm.player_defend()
        self._write_history(result)
        self.query_one("#battle_story", TypewriterLog).type_text(
            result, speed="medium", on_complete=self._start_turn
        )

    def _player_flee(self):
        self._disable_buttons()
        success, msg = self._bm.player_flee()
        self._write_history(msg)
        if success:
            self.query_one("#battle_story", TypewriterLog).type_text(
                msg, speed="medium", on_complete=self._close_battle
            )
        else:
            self.query_one("#battle_story", TypewriterLog).type_text(
                msg, speed="medium", on_complete=self._start_turn
            )

    # ── 敌人行动 ──
    def _enemy_turn(self):
        result = self._bm.enemy_act()
        self._write_history(result)
        self._refresh_hp_bars()
        self.query_one("#battle_story", TypewriterLog).type_text(
            result, speed="medium", on_complete=self._start_turn
        )

    # ── 战斗结束 ──
    def _end_battle(self):
        if self._bm.player_won:
            self._bm.finalize()
            victory_msg = self._bm.enemy_narrative.get("victory", "战斗胜利！")
            self._write_history(victory_msg)
            self.query_one("#battle_story", TypewriterLog).type_text(
                victory_msg, speed="medium", on_complete=self._close_battle
            )
        else:
            self._bm.finalize()
            self._write_history("<fire>你被击败了……</fire>")
            self.query_one("#battle_story", TypewriterLog).type_text(
                "<fire>你失去了意识……</fire>",
                speed="slow",
                on_complete=self._game_over,
            )

    def _close_battle(self):
        self.app.pop_screen()
        if hasattr(self.app, "gameplay_screen") and self.app.gameplay_screen:
            self.app.gameplay_screen.load_current_room()
            self.app.gameplay_screen._refresh_diary_button()

    def _game_over(self):
        self.app.pop_screen()
        from view.game_over_screen import GameOverScreen
        self.app.push_screen(GameOverScreen())

    # ── 按钮事件 ──
    def on_button_pressed(self, event: Button.Pressed):
        bid = event.button.id
        if bid == "btn_attack":
            self._player_attack()
        elif bid == "btn_defend":
            self._player_defend()
        elif bid == "btn_flee":
            self._player_flee()

    def action_action1(self):
        if self._bm and self._bm.is_player_turn():
            self._player_attack()

    def action_action2(self):
        if self._bm and self._bm.is_player_turn():
            self._player_defend()

    def action_action3(self):
        if self._bm and self._bm.is_player_turn():
            self._player_flee()

    def action_close(self):
        pass
