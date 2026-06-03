"""战斗界面"""

import asyncio
from typing import Optional

from textual import work
from textual.screen import Screen
from textual.widgets import Static, Button
from textual.containers import Vertical, Horizontal, Container
from rich.text import Text

from engine.effects import TypewriterLog, convert_custom_tags
from engine.battle import BattleManager


# ==========================================
# 文本血条 widget（带渐变动画）
# ==========================================
class HealthBar(Static):
    """文本血条：

    玩家:   [████████░░░░]  80/100 -20
    敌人:   [████████░░░░]  80%    -20

    受击时展示数值并播放从旧值到新值的渐进缩短动画。
    """
    BAR_CHARS = 18
    ANIM_STEPS = 6
    ANIM_INTERVAL = 0.06

    def __init__(self, name: str, hp: int, max_hp: int, is_enemy: bool = False, **kwargs):
        super().__init__(**kwargs)
        self._name = name
        self._display_hp = hp
        self._target_hp = hp
        self._max_hp = max_hp
        self._is_enemy = is_enemy
        self._dmg = 0
        self._anim_from = hp
        self._anim_to = hp
        self._anim_step = 0

    def on_mount(self):
        self._render_bar()

    def set_hp(self, hp: int, max_hp: int, dmg: int = -1):
        """设置目标血量并触发动画。dmg <= 0 不显示伤害数字"""
        self._max_hp = max_hp
        if dmg > 0:
            self._dmg = dmg

        old = self._display_hp
        self._target_hp = hp

        if old != hp:
            self._anim_from = old
            self._anim_to = hp
            self._anim_step = 0
            self._start_anim()
        else:
            self._render_bar()

    @work(exclusive=True)
    async def _start_anim(self):
        for step in range(1, self.ANIM_STEPS + 1):
            self._anim_step = step
            self._render_bar()
            await asyncio.sleep(self.ANIM_INTERVAL)
        self._display_hp = self._target_hp
        self._render_bar()

    def _render_bar(self):
        """渲染血条文本"""
        if self._anim_step > 0 and self._anim_step < self.ANIM_STEPS:
            t = self._anim_step / self.ANIM_STEPS
            current = int(self._anim_from + (self._anim_to - self._anim_from) * t)
        else:
            current = self._display_hp if self._anim_step == 0 else self._target_hp

        self._display_hp = current
        ratio = max(0.0, min(1.0, current / max(self._max_hp, 1)))
        filled = max(0, min(self.BAR_CHARS, int(ratio * self.BAR_CHARS)))
        empty = self.BAR_CHARS - filled

        # 低血量变色
        if ratio < 0.3:
            bar_color = "#ff4444"
        elif ratio < 0.6:
            bar_color = "#ffaa00"
        else:
            bar_color = "#66fcf1"

        bar = Text.assemble(
            ("█" * filled, bar_color),
            ("░" * empty, "#555555"),
            "  ",
        )

        if self._is_enemy:
            pct = int(ratio * 100)
            label = Text(f"{pct}% ", style="#c5c6c7")
        else:
            label = Text(f"{current}/{self._max_hp} ", style="#c5c6c7")

        bar.append_text(label)

        if self._dmg > 0:
            bar.append_text(Text(f" -{self._dmg}", style="#ff4444"))

        self.update(bar)


# ==========================================
# 战斗界面
# ==========================================
class BattleScreen(Screen):
    BINDINGS = [
        ("1", "action1", "攻击"),
        ("2", "action2", "行动"),
        ("3", "action3", "逃跑"),
        ("4", "action4", "道具"),
        ("enter", "continue", "继续"),
        ("space", "continue", "继续"),
        ("escape", "close", "关闭"),
    ]

    CSS = """
    BattleScreen {
        background: #0b0c10;
        padding: 1;
    }

    #battle_top {
        height: 6;
        background: #161923;
        border: solid #ffffff;
        margin-bottom: 1;
        padding: 0 1;
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
        color: #ffffff;
        text-style: bold;
        height: 1;
    }

    #battle_middle {
        height: 16;
        margin-bottom: 1;
    }
    #battle_story {
        width: 65%;
        height: 100%;
        border: solid #ffffff;
        background: #161923;
        padding: 1 2;
        color: #c5c6c7;
    }
    #battle_history {
        width: 35%;
        height: 100%;
        border: dashed #666666;
        background: #0f1016;
        margin-left: 1;
        color: #888888;
    }

    #battle_bottom {
        height: auto;
    }
    #battle_options {
        width: 100%;
        height: 5;
        layout: grid;
        grid-size: 4 1;
        grid-columns: 1fr 1fr 1fr 1fr;
        grid-gutter: 1 2;
    }
    #action_submenu {
        width: 100%;
        height: 5;
        layout: grid;
        grid-size: 2 1;
        grid-columns: 1fr 1fr;
        grid-gutter: 1 2;
        margin-top: 1;
    }
    #continue_prompt {
        width: 100%;
        height: 1;
        margin-top: 1;
        text-align: center;
        color: #666666;
    }
    .battle_btn {
        background: #1a1e2a;
        border: solid #ffffff;
        color: #c5c6c7;
        width: 100%;
        height: 100%;
        content-align: center middle;
        text-style: bold;
    }
    .battle_btn:hover {
        background: #ffffff;
        color: #0b0c10;
        text-style: bold;
    }
    .battle_btn:disabled {
        background: #1a1a24;
        color: #444444;
        border: solid #444444;
    }
    """

    def __init__(self, enemy_id: str, post_battle_effects: Optional[dict] = None):
        super().__init__()
        self._enemy_id = enemy_id
        self._bm: Optional[BattleManager] = None
        self._post_battle_effects = post_battle_effects or {}
        self._history_text = Text("")
        self._cont_waiting = False
        self._cont_callback = None
        self._action_menu_open = False

    def compose(self):
        with Container(id="battle_top"):
            with Horizontal():
                with Vertical(id="player_panel"):
                    yield Static("", id="player_name", classes="battle_name")
                    yield HealthBar("", 100, 100, is_enemy=False, id="player_hp_bar")
                with Vertical(id="enemy_panel"):
                    yield Static("", id="enemy_name", classes="battle_name")
                    yield HealthBar("", 100, 100, is_enemy=True, id="enemy_hp_bar")

        with Horizontal(id="battle_middle"):
            yield TypewriterLog("", id="battle_story")
            yield Static("", id="battle_history")

        with Vertical(id="battle_bottom"):
            with Horizontal(id="battle_options"):
                yield Button("[1] 攻击", id="btn_attack", classes="battle_btn")
                yield Button("[2] 行动", id="btn_action", classes="battle_btn")
                yield Button("[3] 逃跑", id="btn_flee", classes="battle_btn")
                yield Button("[4] 道具", id="btn_item", classes="battle_btn", disabled=True)
            with Horizontal(id="action_submenu"):
                yield Button("防御", id="btn_defend", classes="battle_btn")
                yield Button("调查", id="btn_investigate", classes="battle_btn")
            yield Static("", id="continue_prompt")

    def on_mount(self):
        self.query_one("#action_submenu").display = False

        self._bm = BattleManager(self.app.engine, self._enemy_id)
        self._refresh_bars()

        encounter_text = self._bm.enemy_narrative.get("encounter", f"{self._bm.enemy.name}出现了！")
        self._write_history(encounter_text)

        pre_text = self._bm.resolve_pre_battle()
        if pre_text:
            self._write_history(pre_text)
            encounter_text += "\n" + pre_text
            self._refresh_bars()

        self._bm.rebuild_turn_order()

        self.query_one("#battle_story", TypewriterLog).type_text(
            encounter_text,
            speed="medium",
            on_complete=self._wait_for_continue,
        )
        self._cont_callback = self._start_turn

    # ── 点击继续 ──

    def _wait_for_continue(self):
        self.query_one("#continue_prompt", Static).update("[#666666]▼ [Click / Enter] 继续[/#666666]")
        self._cont_waiting = True

    def _do_continue(self):
        if not self._cont_waiting:
            return
        self._cont_waiting = False
        self.query_one("#continue_prompt", Static).update("")
        cb = self._cont_callback
        self._cont_callback = None
        if cb:
            cb()

    def on_click(self, event):
        if self._cont_waiting:
            event.stop()
            self._do_continue()

    def action_continue(self):
        self._do_continue()

    # ── 血条更新 ──

    def _refresh_bars(self, player_dmg: int = -1, enemy_dmg: int = -1):
        bm = self._bm
        if bm is None:
            return

        self.query_one("#player_hp_bar", HealthBar).set_hp(
            bm.player.hp, bm.player.max_hp, dmg=player_dmg
        )
        self.query_one("#enemy_hp_bar", HealthBar).set_hp(
            bm.enemy.hp, bm.enemy.max_hp, dmg=enemy_dmg
        )

        self.query_one("#player_name", Static).update(bm.player.name)
        self.query_one("#enemy_name", Static).update(bm.enemy.name)

    def _write_history(self, text: str):
        converted = convert_custom_tags(text)
        new_text = Text.assemble(self._history_text, "\n", Text.from_markup(converted))
        self._history_text = new_text
        self.query_one("#battle_history", Static).update(new_text)

    # ── 回合流 ──

    def _start_turn(self):
        self._close_action_menu()
        if self._bm.battle_over:
            self._end_battle()
            return
        self._refresh_bars()

        if self._bm.is_player_turn():
            self._enable_buttons()
        else:
            self._disable_buttons()
            self._enemy_turn()

    def _disable_buttons(self):
        for bid in ["btn_attack", "btn_action", "btn_flee", "btn_item"]:
            self.query_one(f"#{bid}", Button).disabled = True
        self._close_action_menu()

    def _enable_buttons(self):
        self.query_one("#btn_attack", Button).disabled = False
        self.query_one("#btn_action", Button).disabled = False
        self.query_one("#btn_flee", Button).disabled = False
        self.query_one("#btn_item", Button).disabled = True

    # ── 行动子菜单 ──

    def _open_action_menu(self):
        self._action_menu_open = True
        self.query_one("#battle_options").display = False
        self.query_one("#action_submenu").display = True
        self.query_one("#btn_defend", Button).disabled = not self._bm.can_defend

    def _close_action_menu(self):
        self._action_menu_open = False
        self.query_one("#battle_options").display = True
        self.query_one("#action_submenu").display = False

    # ── 玩家行动 ──

    def _player_attack(self):
        self._disable_buttons()
        self._close_action_menu()
        text, dmg = self._bm.player_attack()
        self._write_history(text)
        self._refresh_bars(enemy_dmg=dmg)
        self._cont_callback = self._start_turn
        self.query_one("#battle_story", TypewriterLog).type_text(
            text, speed="medium", on_complete=self._wait_for_continue
        )

    def _player_defend(self):
        self._disable_buttons()
        self._close_action_menu()
        result = self._bm.player_defend()
        self._write_history(result)
        self._refresh_bars()
        self._cont_callback = self._start_turn
        self.query_one("#battle_story", TypewriterLog).type_text(
            result, speed="medium", on_complete=self._wait_for_continue
        )

    def _player_investigate(self):
        self._disable_buttons()
        self._close_action_menu()
        result = self._bm.player_investigate()
        self._write_history(result)
        self._refresh_bars()
        self._cont_callback = self._start_turn
        self.query_one("#battle_story", TypewriterLog).type_text(
            result, speed="medium", on_complete=self._wait_for_continue
        )

    def _player_flee(self):
        self._disable_buttons()
        self._close_action_menu()
        success, msg = self._bm.player_flee()
        self._write_history(msg)
        self._cont_callback = self._close_battle if success else self._start_turn
        self.query_one("#battle_story", TypewriterLog).type_text(
            msg, speed="medium", on_complete=self._wait_for_continue
        )

    # ── 敌人行动 ──

    def _enemy_turn(self):
        result, dmg = self._bm.enemy_act()
        self._write_history(result)
        self._refresh_bars(player_dmg=dmg)
        self._cont_callback = self._start_turn
        self.query_one("#battle_story", TypewriterLog).type_text(
            result, speed="medium", on_complete=self._wait_for_continue
        )

    # ── 战斗结束 ──

    def _end_battle(self):
        if self._bm.player_won:
            self._bm.finalize()
            self._apply_post_battle()
            rewards = self._bm.apply_rewards()
            self._show_victory_screen(rewards)
        else:
            self._bm.finalize()
            self._write_history("<fire>你被击败了……</fire>")
            self._cont_callback = self._game_over
            self.query_one("#battle_story", TypewriterLog).type_text(
                "<fire>你失去了意识……</fire>",
                speed="slow",
                on_complete=self._wait_for_continue,
            )

    def _show_victory_screen(self, rewards):
        self._disable_buttons()
        victory_msg = self._bm.enemy_narrative.get("victory", "战斗胜利！")
        self._write_history(victory_msg)

        stanzas = [victory_msg]
        xp, drops = rewards if rewards else (0, [])

        reward_lines = ["\n[#ffdd00]━━ 战利品 ━━[/#ffdd00]"]
        if xp > 0:
            reward_lines.append(f"[#c5c6c7]经验值 +{xp}[/#c5c6c7]")
        if drops:
            for drop_id in drops:
                item_def = self.app.engine.get_item_def(drop_id)
                name = item_def.get("name", drop_id) if item_def else drop_id
                reward_lines.append(f"[#66fcf1]获得物品: {name}[/#66fcf1]")

        if len(reward_lines) > 1:
            stanzas.append("\n".join(reward_lines))

        self._cont_callback = self._close_battle
        self.query_one("#battle_story", TypewriterLog).type_text(
            "\n".join(stanzas), speed="medium", on_complete=self._wait_for_continue
        )

    def _apply_post_battle(self):
        if self._post_battle_effects:
            self.app.engine.apply_effects(self._post_battle_effects)

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
        if self._cont_waiting:
            return
        bid = event.button.id

        if self._action_menu_open:
            if bid == "btn_defend":
                self._player_defend()
            elif bid == "btn_investigate":
                self._player_investigate()
            return

        if bid == "btn_attack":
            self._player_attack()
        elif bid == "btn_action":
            self._open_action_menu()
        elif bid == "btn_flee":
            self._player_flee()

    def action_action1(self):
        if self._bm and self._bm.is_player_turn() and not self._cont_waiting and not self._action_menu_open:
            self._player_attack()

    def action_action2(self):
        if self._bm and self._bm.is_player_turn() and not self._cont_waiting and not self._action_menu_open:
            self._open_action_menu()

    def action_action3(self):
        if self._bm and self._bm.is_player_turn() and not self._cont_waiting and not self._action_menu_open:
            self._player_flee()

    def action_close(self):
        pass
