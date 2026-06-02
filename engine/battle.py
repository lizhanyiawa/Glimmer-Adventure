"""回合制战斗系统"""

import random
import json
from typing import Dict, Any, List, Optional, Tuple
from engine.paths import data_path


def _load_enemies() -> Dict[str, Any]:
    with open(data_path("enemies.json"), "r", encoding="utf-8") as f:
        return json.load(f)


def calc_damage(atk: float, defense: float) -> Tuple[int, bool, float]:
    """计算伤害，返回 (伤害值, 是否会心一击, 倍率)。

    公式: 伤害 = max(1, round(atk * rand(0.9, 1.1) * (100 / (100 + def * 0.8))))

    会心一击 (random < 0.1): 倍率 × 1.5
    """
    rand_mul = random.uniform(0.9, 1.1)
    is_critical = random.random() < 0.1
    if is_critical:
        rand_mul *= 1.5
    raw = atk * rand_mul * (100.0 / (100.0 + defense * 0.8))
    return max(1, round(raw)), is_critical, rand_mul


class Combatant:
    def __init__(self, name: str, hp: int, max_hp: int, attack: int,
                 defense: int, agility: int, is_player: bool = False):
        self.name = name
        self.hp = hp
        self.max_hp = max_hp
        self.attack = attack
        self.defense = defense
        self.agility = agility
        self.is_player = is_player
        self.alive = True
        self.stunned = False
        self._base_agility = agility

    @property
    def hp_ratio(self) -> float:
        return self.hp / max(self.max_hp, 1)

    def take_damage(self, dmg: int) -> int:
        self.hp = max(0, self.hp - dmg)
        if self.hp <= 0:
            self.alive = False
        return dmg

    def modify_agility(self, delta: int):
        self.agility = max(0, self.agility + delta)


class BattleManager:
    """战斗管理器 — 回合制，敏捷排序，纯数据层"""

    def __init__(self, engine, enemy_id: str):
        self.engine = engine
        self.state = engine.state
        enemies_data = _load_enemies()

        e_data = enemies_data.get(enemy_id, {})
        self.enemy_data = e_data
        self.enemy_narrative = e_data.get("narrative", {})

        player_stats = self.state.stats
        self.player = Combatant(
            name=self.state.stats.get("player_name", "你"),
            hp=player_stats.get("hp", 100),
            max_hp=player_stats.get("max_hp", 100),
            attack=player_stats.get("attack", 10),
            defense=player_stats.get("defense", 5),
            agility=player_stats.get("agility", 10),
            is_player=True,
        )

        self.enemy = Combatant(
            name=e_data.get("name", "???",),
            hp=e_data.get("hp", 30),
            max_hp=e_data.get("hp", 30),
            attack=e_data.get("attack", 8),
            defense=e_data.get("defense", 4),
            agility=e_data.get("agility", 8),
            is_player=False,
        )

        self.combatants = [self.player, self.enemy]
        self.turn_order: List[Combatant] = []
        self.battle_log: List[str] = []
        self.battle_over = False
        self.player_won = False
        self.fled = False
        self._current_turn_index = 0

        self._pre_battle = e_data.get("pre_battle", {})
        self._player_guarding = False
        self._guard_cooldown = False

    # ── 预战斗事件 ──
    def resolve_pre_battle(self) -> str:
        """在 encounter 文本播放完之后、首回合开始之前调用。

        返回预战斗事件的叙事文本（为空字符串表示没有预事件）。
        """
        pre = self._pre_battle
        if not pre:
            return ""

        ptype = pre.get("type", "")
        if ptype == "rock_throw":
            hit = random.random() < pre.get("hit_rate", 0.5)
            if hit:
                pct = pre.get("damage_pct", 0.1)
                dmg = max(1, round(self.enemy.max_hp * pct))
                self.enemy.take_damage(dmg)
                lines = [pre.get("hit_text", "石头命中了！")]
                if random.random() < pre.get("stun_chance", 0):
                    self.enemy.stunned = True
                    lines.append(pre.get("stun_text", "敌人陷入了眩晕！"))
                self._check_battle_end()
                return "\n".join(lines)
            else:
                return pre.get("miss_text", "石头没有命中……")

        return ""

    # ── 排序 ──
    def rebuild_turn_order(self):
        self.combatants.sort(key=lambda c: c.agility, reverse=True)
        self.turn_order = [c for c in self.combatants if c.alive]
        self._current_turn_index = 0

    def current_actor(self) -> Optional[Combatant]:
        if self._current_turn_index < len(self.turn_order):
            return self.turn_order[self._current_turn_index]
        return None

    def advance_turn(self):
        self._current_turn_index += 1
        if self._current_turn_index >= len(self.turn_order):
            self._current_turn_index = 0

    def is_player_turn(self) -> bool:
        actor = self.current_actor()
        return actor is not None and actor.is_player

    # ── 玩家行动 ──
    def player_attack(self) -> str:
        dmg, crit, mul = calc_damage(self.player.attack, self.enemy.defense)
        self.enemy.take_damage(dmg)

        prefix = self.enemy_narrative.get("player_attack", "你发起攻击！")
        if crit:
            hit_msg = self.enemy_narrative.get("player_heavy", f"会心一击！造成 {dmg} 点伤害！")
        else:
            hit_msg = self.enemy_narrative.get("player_hit", f"命中了！造成 {dmg} 点伤害。")

        lines = [prefix, hit_msg]
        if not self.enemy.alive:
            lines.append(self.enemy_narrative.get("death", f"{self.enemy.name}倒下了！"))

        self._check_battle_end()
        self.advance_turn()
        return "\n".join(lines)

    def player_defend(self) -> str:
        self._player_guarding = True
        self._guard_cooldown = True
        self.advance_turn()
        return "你稳住身形架起防御，<heal>做好了承受冲击的准备</heal>。"

    @property
    def can_defend(self) -> bool:
        return not self._guard_cooldown

    def player_flee(self) -> Tuple[bool, str]:
        success = random.random() < 0.5
        if success:
            self.fled = True
            self.battle_over = True
            return True, self.enemy_narrative.get("flee_success", "你成功逃跑了！")
        else:
            self.advance_turn()
            return False, self.enemy_narrative.get("flee_fail", "逃跑失败！")

    # ── 敌人行动 ──
    def enemy_act(self) -> str:
        if self.enemy.stunned:
            self.enemy.stunned = False
            self.advance_turn()
            return f"{self.enemy.name}<dim>还在眩晕中，无法行动</dim>……"

        dmg, crit, mul = calc_damage(self.enemy.attack, self.player.defense)

        if self._player_guarding:
            dmg = max(1, dmg // 2)
            self._player_guarding = False
            self._guard_cooldown = False
            msg = f"{self.enemy.name}的猛攻被你的防御姿态<heal>化解了大半</heal>，造成了 {dmg} 点伤害。"
            self.player.take_damage(dmg)

            lines = [self.enemy_narrative.get("attack", f"{self.enemy.name}发起攻击！"), msg]
        else:
            self.player.take_damage(dmg)
            attack_msg = self.enemy_narrative.get("attack", f"{self.enemy.name}发起攻击！")
            hit_msg = self.enemy_narrative.get("hit", f"造成了 {dmg} 点伤害。")
            lines = [attack_msg, hit_msg]

        if not self.player.alive:
            lines.append("<fire>你倒下了……</fire>")

        self._check_battle_end()
        self.advance_turn()
        return "\n".join(lines)

    # ── 结算 ──
    def _check_battle_end(self):
        if not self.enemy.alive:
            self.battle_over = True
            self.player_won = True
        elif not self.player.alive:
            self.battle_over = True
            self.player_won = False

    def finalize(self):
        """战斗结束后同步血量回 GameState"""
        self.state.stats["hp"] = self.player.hp

    def apply_rewards(self):
        if not self.player_won:
            return
        xp = self.enemy_data.get("xp", 0)
        drops = self.enemy_data.get("drops", [])
        for drop_id in drops:
            self.engine.inv_mgr.add_by_id(drop_id)
        return xp, drops
