class_name BattleManager
extends RefCounted
## 回合制战斗的数据层（对应 Python 的 engine/battle.py）。
##
## 只负责数值与机制，不碰任何界面；界面由 scripts/ui/battle.gd 驱动。
## 所有叙事文本都来自 data/enemies_text.json，这里不写死剧情。

## 战斗单位（玩家或敌人）
class Combatant extends RefCounted:
	var name: String
	var hp: int
	var max_hp: int
	var attack: int
	var defense: int
	var agility: int
	var is_player: bool
	var alive: bool = true
	var stunned: bool = false
	var base_agility: int

	func _init(p_name: String, p_hp: int, p_max_hp: int, p_attack: int,
			p_defense: int, p_agility: int, p_is_player: bool = false) -> void:
		name = p_name
		hp = p_hp
		max_hp = p_max_hp
		attack = p_attack
		defense = p_defense
		agility = p_agility
		is_player = p_is_player
		base_agility = p_agility

	func hp_ratio() -> float:
		return float(hp) / float(maxi(max_hp, 1))

	func take_damage(dmg: int) -> int:
		hp = maxi(0, hp - dmg)
		if hp <= 0:
			alive = false
		return dmg


var engine: Node          ## GameEngine 单例
var state                 ## GameState
var enemy_id: String
var enemy_data: Dictionary = {}
var enemy_narrative: Dictionary = {}

var first_monster: bool = false
var player: Combatant = null
var enemy: Combatant = null

var combatants: Array = []
var turn_order: Array = []
var battle_over: bool = false
var player_won: bool = false
var fled: bool = false

var _current_turn_index: int = 0
var _pre_battle: Dictionary = {}
var _player_guarding: bool = false
var _guard_cooldown: bool = false


func _init(p_engine: Node, p_enemy_id: String) -> void:
	engine = p_engine
	state = p_engine.state
	enemy_id = p_enemy_id
	enemy_data = engine.get_enemy(p_enemy_id)
	enemy_narrative = enemy_data.get("narrative", {})

	# 第一次见怪扣理智（只发生一次，用 flag 记录）
	if not state.flags.get("first_monster_seen", false):
		var san_drop := int(enemy_data.get("san_drop", 0))
		if san_drop != 0:
			first_monster = true
			state.stats["san"] = clampi(int(state.stats.get("san", 100)) + san_drop, 0, 100)
			engine.set_flag("first_monster_seen", true)

	var ps: Dictionary = state.stats
	player = Combatant.new(
		str(ps.get("player_name", "你")),
		int(ps.get("hp", 100)), int(ps.get("max_hp", 100)),
		int(ps.get("attack", 10)), int(ps.get("defense", 5)), int(ps.get("agility", 10)),
		true
	)
	var ehp := int(enemy_data.get("hp", 30))
	enemy = Combatant.new(
		str(enemy_data.get("name", "???")),
		ehp, ehp,
		int(enemy_data.get("attack", 8)), int(enemy_data.get("defense", 4)),
		int(enemy_data.get("agility", 8)),
		false
	)

	combatants = [player, enemy]
	_pre_battle = enemy_data.get("pre_battle", {})


## 伤害公式（与 Python 版逐字一致）：
##   伤害 = max(1, round(atk * rand(0.9,1.1) * (100 / (100 + def*0.8))))
##   会心一击（10%）：倍率再 ×1.5
static func calc_damage(atk: float, defense: float) -> Dictionary:
	var rand_mul := randf_range(0.9, 1.1)
	var is_crit := randf() < 0.1
	if is_crit:
		rand_mul *= 1.5
	var raw := atk * rand_mul * (100.0 / (100.0 + defense * 0.8))
	return {"dmg": maxi(1, int(roundf(raw))), "crit": is_crit, "mul": rand_mul}


## ────────────────────────── 叙事文本 ──────────────────────────

## 从叙事文本里随机取一个变体（兼容字符串和数组两种写法）
func _pick_narrative(key: String, fallback: String = "???") -> String:
	var val = enemy_narrative.get(key, fallback)
	if val is Array:
		if val.is_empty():
			return fallback
		return str(val[randi() % val.size()])
	return str(val)


## 取文本并把 {name} / {dmg} 占位符替换掉。
## dmg 给个默认值：文本里没写 {dmg} 时这个键会被忽略，不会影响别的分支。
func _fmt_narrative(key: String, fallback: String = "???", dmg: int = -1) -> String:
	return _pick_narrative(key, fallback).format({"name": enemy.name, "dmg": dmg})


## 供界面层取叙事文本的公开入口（界面只管显示，不关心内部是字符串还是数组）
func get_narrative(key: String, fallback: String = "???") -> String:
	return _fmt_narrative(key, fallback)


## ────────────────────────── 预战斗事件 ──────────────────────────

## 对应 Python 的 resolve_pre_battle：目前只有"扔石头"一种。
func resolve_pre_battle() -> String:
	if _pre_battle.is_empty():
		return ""
	var ptype := str(_pre_battle.get("type", ""))
	if ptype != "rock_throw":
		return ""

	if randf() < float(_pre_battle.get("hit_rate", 0.5)):
		var pct := float(_pre_battle.get("damage_pct", 0.1))
		var dmg := maxi(1, int(roundf(enemy.max_hp * pct)))
		enemy.take_damage(dmg)
		var lines: Array = [str(_pre_battle.get("hit_text", "石头命中了！"))]
		if randf() < float(_pre_battle.get("stun_chance", 0)):
			enemy.stunned = true
			lines.append(str(_pre_battle.get("stun_text", "敌人陷入了眩晕！")))
		_check_battle_end()
		return "\n".join(lines)
	return str(_pre_battle.get("miss_text", "石头没有命中……"))


## ────────────────────────── 回合顺序 ──────────────────────────

## 按敏捷从高到低排序，活着的人参与本回合
func rebuild_turn_order() -> void:
	combatants.sort_custom(func(a, b): return a.agility > b.agility)
	turn_order = []
	for c in combatants:
		if c.alive:
			turn_order.append(c)
	_current_turn_index = 0


func current_actor() -> Combatant:
	if _current_turn_index < turn_order.size():
		return turn_order[_current_turn_index]
	return null


func advance_turn() -> void:
	_current_turn_index += 1
	if _current_turn_index >= turn_order.size():
		_current_turn_index = 0


func is_player_turn() -> bool:
	var actor := current_actor()
	return actor != null and actor.is_player


func can_defend() -> bool:
	return not _guard_cooldown


## ────────────────────────── 玩家行动 ──────────────────────────

func player_attack() -> Dictionary:
	var res := calc_damage(player.attack, enemy.defense)
	var dmg: int = res["dmg"]
	var crit: bool = res["crit"]
	enemy.take_damage(dmg)

	var lines: Array = [_fmt_narrative("player_attack", "你发起攻击！")]
	if crit:
		lines.append(_fmt_narrative("player_heavy", "会心一击！造成 %d 点伤害！" % dmg, dmg))
	else:
		lines.append(_fmt_narrative("player_hit", "命中了！造成 %d 点伤害。" % dmg, dmg))
	if not enemy.alive:
		lines.append(_fmt_narrative("death", "%s倒下了！" % enemy.name))

	_check_battle_end()
	advance_turn()
	_sync_to_state()
	return {"text": "\n".join(lines), "dmg": dmg}


func player_defend() -> String:
	_player_guarding = true
	_guard_cooldown = true
	advance_turn()
	_sync_to_state()
	return _pick_narrative("defend", "你稳住身形架起防御，<heal>做好了承受冲击的准备</heal>。")


func player_flee() -> Dictionary:
	# 逃跑率 = 基础 50% + 敏捷差每点 5% + 敌人特性修正；理智 ≤30 再降 10%
	var agi_diff: int = player.agility - enemy.agility
	var base_chance := 0.5 + agi_diff * 0.05
	var flee_mod := float(enemy_data.get("flee_mod", 0))
	var san_penalty := -0.1 if int(state.stats.get("san", 100)) <= 30 else 0.0
	var chance := clampf(base_chance + flee_mod + san_penalty, 0.05, 0.95)

	if randf() < chance:
		fled = true
		battle_over = true
		_sync_to_state()
		return {"success": true, "text": str(enemy_narrative.get("flee_success", "你成功逃跑了！"))}
	advance_turn()
	return {"success": false, "text": str(enemy_narrative.get("flee_fail", "逃跑失败！"))}


func player_investigate() -> String:
	# 调查敌人，消耗一回合
	var desc := str(enemy_data.get("description", "你看不出什么特别的信息。"))
	var hp_pct := int(float(enemy.hp) / float(maxi(enemy.max_hp, 1)) * 100.0)

	var prefix := _fmt_narrative("investigate", "你仔细观察了%s。" % enemy.name)

	var statuses: Dictionary = enemy_narrative.get("hp_status", {})
	var hp_desc := ""
	if hp_pct >= 90:
		hp_desc = str(statuses.get("healthy", "看起来毫发无伤"))
	elif hp_pct >= 60:
		hp_desc = str(statuses.get("scratched", "受了些轻伤"))
	elif hp_pct >= 30:
		hp_desc = str(statuses.get("wounded", "伤势不轻"))
	else:
		hp_desc = str(statuses.get("critical", "已是强弩之末"))

	var lines: Array = [prefix, "", "[color=#888888]%s[/color]" % desc, "", "-- 状态: %s --" % hp_desc]
	advance_turn()
	return "\n".join(lines)


## ────────────────────────── 敌人行动 ──────────────────────────

func enemy_act() -> Dictionary:
	if enemy.stunned:
		enemy.stunned = false
		# 敌人这一回合没出手，防御的"冷却"就不该继续锁着玩家，否则连续眩晕时
		# 防御按钮会被白锁好几回合。注意只清冷却、不清 _player_guarding——
		# 这次防御还没被消耗，等敌人下次真正出手时仍然要减半。
		_guard_cooldown = false
		advance_turn()
		return {"text": _fmt_narrative("stunned", "%s还在眩晕中，无法行动……" % enemy.name), "dmg": 0}

	var res := calc_damage(enemy.attack, player.defense)
	var dmg: int = res["dmg"]
	var lines: Array = []

	if _player_guarding:
		dmg = maxi(1, dmg / 2)
		_player_guarding = false
		_guard_cooldown = false
		player.take_damage(dmg)
		lines.append(_fmt_narrative("attack", "%s发起攻击！" % enemy.name))
		lines.append(_fmt_narrative("guarded", "但你的防御姿态化解了大半力道，只造成了 %d 点伤害。" % dmg, dmg))
	else:
		player.take_damage(dmg)
		lines.append(_fmt_narrative("attack", "%s发起攻击！" % enemy.name))
		lines.append(_fmt_narrative("hit", "造成了 %d 点伤害。" % dmg, dmg))

	if not player.alive:
		lines.append("<fire>你倒下了……</fire>")

	_check_battle_end()
	advance_turn()
	_sync_to_state()
	return {"text": "\n".join(lines), "dmg": dmg}


## ────────────────────────── 结算 ──────────────────────────

func _check_battle_end() -> void:
	if not enemy.alive:
		battle_over = true
		player_won = true
	elif not player.alive:
		battle_over = true
		player_won = false


## 每回合把血量同步回 GameState，避免中途退出丢进度
func _sync_to_state() -> void:
	state.stats["hp"] = player.hp
	if player.agility != player.base_agility:
		state.stats["agility"] = player.agility


func finalize() -> void:
	_sync_to_state()


## 胜利结算：经验值只用于展示，掉落进背包
func apply_rewards() -> Dictionary:
	if not player_won:
		return {"xp": 0, "drops": []}
	var xp := int(enemy_data.get("xp", 0))
	var drops: Array = enemy_data.get("drops", [])
	for drop_id in drops:
		engine.inv_mgr.add_by_id(str(drop_id))
	return {"xp": xp, "drops": drops}
