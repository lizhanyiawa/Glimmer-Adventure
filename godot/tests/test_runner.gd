extends Node
## 核心逻辑自测（零依赖、可 headless 运行）。
##
## 运行方式（手动，不在游戏里跑）：
##   godot --headless --path godot res://tests/TestRunner.tscn
## 退出码 = 失败用例数（0 表示全通过），方便以后接 CI。
##
## 说明：
## - GameEngine / FontManager / Fx 是 autoload，测试场景里直接当单例用。
## - 每个测试组开始前会 reset_game()，避免上一组污染全局状态。
## - 只测纯逻辑（数据、条件、效果、背包、存档、战斗、装备），不碰界面。
## - 存档只写 9 号临时槽位，测完删除，绝不动 1~4 号真实存档。

var _passed: int = 0
var _failed: int = 0
var _current_group: String = ""


func _ready() -> void:
	# 等一帧，确保 autoload 的 _ready（数据加载）已经跑完
	await get_tree().process_frame

	print("===== 核心逻辑自测开始 =====")
	_run_all()
	print("\n===== 核心逻辑自测结束 =====")
	print("通过 %d / 失败 %d" % [_passed, _failed])
	get_tree().quit(_failed)


## ────────────────────────── 测试器 ──────────────────────────

## 开启一个测试组：切换组名并重置全局状态
func _group(group_name: String) -> void:
	_current_group = group_name
	GameEngine.reset_game()
	print("\n[测试组] " + group_name)


## 基础断言：条件为真记一次通过，否则记一次失败并打印所在分组
func _check(cond: bool, desc: String) -> void:
	if cond:
		_passed += 1
		print("  [通过] " + desc)
	else:
		_failed += 1
		print("  [失败] %s / %s" % [_current_group, desc])


## 相等断言：失败信息里带上期望值与实际值
func _check_eq(actual, expected, desc: String) -> void:
	_check(actual == expected, "%s（期望 %s，实际 %s）" % [desc, str(expected), str(actual)])


func _run_all() -> void:
	_test_data_loading()
	_test_option_visible()
	_test_apply_effects()
	_test_inventory()
	_test_save_load()
	_test_battle()
	_test_equip()
	_test_use_and_ground()
	_test_to_max_and_time()


## ────────────────────────── 数据加载 ──────────────────────────

func _test_data_loading() -> void:
	_group("数据加载")

	var room := GameEngine.get_room("thatched_hut")
	_check(not room.is_empty(), "get_room(thatched_hut) 非空")

	var enemy := GameEngine.get_enemy("spined_rat")
	_check_eq(enemy.get("hp", -1), 18, "spined_rat.hp 与 JSON 一致")
	_check_eq(enemy.get("attack", -1), 4, "spined_rat.attack 与 JSON 一致")
	_check(enemy.get("drops", []) is Array and "cellar_chest_key" in enemy.get("drops", []),
		"spined_rat.drops 含 cellar_chest_key")

	# validate_data() 只统计"引用了不存在的东西"这类真错误；
	# 旧版无前缀 flag 只作提示、不计入返回值，所以干净数据下这里应当为 0。
	var problems := GameEngine.validate_data()
	_check(problems == 0, "validate_data() 返回 0（实际 %d）" % problems)


## ────────────────────────── 条件判定 ──────────────────────────

func _test_option_visible() -> void:
	_group("条件判定 check_option_visible")

	# 1) 无 require / exclude → visible
	_check_eq(GameEngine.check_option_visible({"effects": {}}), "visible",
		"无 require 的选项 → visible")

	# 2) exclude 命中 → excluded；未命中 → visible
	GameEngine.set_flag("q_test_exclude", true)
	_check_eq(
		GameEngine.check_option_visible({"exclude": {"flags": {"q_test_exclude": true}}}),
		"excluded", "exclude 命中 → excluded")
	_check_eq(
		GameEngine.check_option_visible({"exclude": {"flags": {"q_test_exclude": false}}}),
		"visible", "exclude 未命中 → visible")

	# 3) require 缺 flag → hidden
	_check_eq(
		GameEngine.check_option_visible({"require": {"flags": {"q_test_missing_flag": true}}}),
		"hidden", "缺 flag 的 require → hidden")

	# 4) require 缺 stat → hidden
	_check_eq(
		GameEngine.check_option_visible({"require": {"stats": {"attack": 999}}}),
		"hidden", "stat 不足的 require → hidden")

	# 5) require 缺 item → hidden
	_check_eq(
		GameEngine.check_option_visible({"require": {"items": {"has": "village_key"}}}),
		"hidden", "缺物品的 require → hidden")

	# 6) require 满足 → visible
	GameEngine.set_flag("q_test_ok", true)
	_check_eq(
		GameEngine.check_option_visible({"require": {"flags": {"q_test_ok": true}}}),
		"visible", "require 满足 → visible")


## ────────────────────────── 效果应用 ──────────────────────────

func _test_apply_effects() -> void:
	_group("效果应用 apply_effects")

	# 加物品
	GameEngine.apply_effects({"items": {"add": ["healing_potion_minor"]}})
	_check(GameEngine.inv_mgr.has("healing_potion_minor"), "effects.items.add 后背包里有该物品")

	# 加 flag
	GameEngine.apply_effects({"flags": {"q_test_effect": true}})
	_check_eq(GameEngine.get_flag("q_test_effect"), true, "effects.flags 后 get_flag 为真")

	# 扣 hp 且不越界
	GameEngine.state.stats["hp"] = 50
	GameEngine.apply_effects({"hp": -10})
	_check_eq(GameEngine.state.stats["hp"], 40, "effects.hp 扣 10 后为 40")
	GameEngine.apply_effects({"hp": -9999})
	_check_eq(GameEngine.state.stats["hp"], 0, "过量扣血被夹到 0（不为负）")


## ────────────────────────── 背包 ──────────────────────────

func _test_inventory() -> void:
	_group("背包 InventoryManager")

	# 用独立实例，避免污染全局
	var st := GameState.new()
	var im := InventoryManager.new(st, {})
	var received: Array = []
	im.item_added.connect(func(item_id): received.append(item_id))

	im.add("test_thing", "测试物", "仅用于测试", "misc", 2)
	im.add("test_thing", "测试物", "仅用于测试", "misc", 3)
	_check_eq(im.get_item("test_thing").get("qty", -1), 5, "add 同 id 累加数量")

	_check_eq(received.size(), 2, "item_added 信号触发次数")
	_check(received.size() > 0 and received[0] == "test_thing", "item_added 携带正确 id")

	im.remove("test_thing", 5)
	_check(not im.has("test_thing"), "remove 归零后 has() 为假")
	_check_eq(im.all().size(), 0, "remove 归零后整条消失")


## ────────────────────────── 存档 ──────────────────────────

func _test_save_load() -> void:
	_group("存档 save / load（临时槽位 9）")

	GameEngine.state.stats["hp"] = 77
	GameEngine.state.room_id = "thatched_hut"
	GameEngine.set_flag("q_save_test", true)
	_check_eq(GameEngine.save_game(9), true, "save_game(9) 返回 true")

	# 改动状态
	GameEngine.state.stats["hp"] = 1
	GameEngine.state.room_id = "village_entrance"
	GameEngine.state.flags.erase("q_save_test")

	_check_eq(GameEngine.load_game(9), true, "load_game(9) 返回 true")
	_check_eq(GameEngine.state.stats["hp"], 77, "读档恢复 hp")
	_check_eq(GameEngine.get_flag("q_save_test"), true, "读档恢复 flag")
	_check_eq(GameEngine.state.room_id, "thatched_hut", "读档恢复 room_id")

	# 清理临时槽位，别覆盖 1~4 号真实存档
	_check_eq(GameEngine.delete_save(9), true, "delete_save(9) 清理临时存档")


## ────────────────────────── 战斗 ──────────────────────────

func _test_battle() -> void:
	_group("战斗 BattleManager")

	var battle := BattleManager.new(GameEngine, "spined_rat")
	_check(battle != null and battle.enemy != null, "BattleManager 能创建")
	_check_eq(battle.enemy.hp, 18, "战斗敌人 hp 与 JSON 一致")

	# 连打若干次，断言每次伤害 >= 1（公式下限）
	for i in 3:
		var result := battle.player_attack()
		_check(result.get("dmg", 0) >= 1, "player_attack 第 %d 次伤害 >= 1（实际 %d）" % [i + 1, result.get("dmg", 0)])

	# 防御后防御冷却生效
	battle.player_defend()
	_check(not battle.can_defend(), "player_defend 后 can_defend() 为 false")


## ────────────────────────── 装备 ──────────────────────────

func _test_equip() -> void:
	_group("装备 equip")

	GameEngine.inv_mgr.add_by_id("iron_dagger")
	var attack_before: int = GameEngine.state.stats["attack"]

	var result := GameEngine.equip("iron_dagger")
	_check_eq(result.get("success", false), true, "equip(iron_dagger) 成功")
	_check(GameEngine.get_equipment().has("weapon"), "get_equipment() 含 weapon 槽位")
	_check_eq(GameEngine.state.stats["attack"], attack_before + 3, "装备后攻击力 +3")

	# 还原全局状态
	GameEngine.reset_game()


## ────────────────────────── 使用物品 / 地面丢弃 ──────────────────────────

func _test_use_and_ground() -> void:
	_group("使用物品 / 地面丢弃")

	# 满血时用治疗药水应该被拒绝，否则等于白白浪费一瓶
	GameEngine.inv_mgr.add_by_id("healing_potion_minor")
	GameEngine.state.stats["hp"] = GameEngine.state.stats["max_hp"]
	var wasted := GameEngine.use_item("healing_potion_minor")
	_check_eq(wasted.get("success", false), false, "满血时使用药水被拒绝")
	_check_eq(GameEngine.inv_mgr.get_item("healing_potion_minor").get("qty", 0), 1,
		"被拒绝时数量不变")

	# 掉血后使用，按 effect 回 20 点
	GameEngine.state.stats["hp"] = 50
	var used := GameEngine.use_item("healing_potion_minor")
	_check_eq(used.get("success", false), true, "use_item 成功")
	_check_eq(GameEngine.state.stats["hp"], 70, "次级治疗药水回 20 点生命")
	_check_eq(GameEngine.inv_mgr.has("healing_potion_minor"), false, "用完后从背包扣除")

	# 丢弃 → 掉在当前房间地上 → 再捡回来
	GameEngine.state.room_id = "thatched_hut"
	GameEngine.inv_mgr.add_by_id("bread")
	var dropped := GameEngine.drop_to_ground(GameEngine.inv_mgr.get_item("bread"))
	_check_eq(dropped.get("success", false), true, "drop_to_ground 成功")
	_check_eq(GameEngine.inv_mgr.has("bread"), false, "丢弃后背包里没有该物品")
	_check_eq(GameEngine.get_ground_items("thatched_hut").size(), 1, "当前房间地上出现 1 件物品")

	var picked := GameEngine.pick_up_ground_item(0)
	_check_eq(picked.get("success", false), true, "pick_up_ground_item 成功")
	_check_eq(GameEngine.inv_mgr.has("bread"), true, "捡回后回到背包")
	_check_eq(GameEngine.get_ground_items("thatched_hut").size(), 0, "捡走后地上清空")

	GameEngine.reset_game()


## ────────────────────────── 回满 / 游戏内时间 ──────────────────────────

func _test_to_max_and_time() -> void:
	_group("回满与游戏内时间")

	# 睡觉 = 直接回满，不依赖 +999，以后数值膨胀也不怕
	GameEngine.state.stats["hp"] = 12
	GameEngine.state.stats["san"] = 20
	GameEngine.apply_effects({"hp_to_max": true, "san_to_max": true})
	_check_eq(GameEngine.state.stats["hp"], GameEngine.state.stats["max_hp"],
		"hp_to_max 顶到最大生命")
	_check_eq(GameEngine.state.stats["san"], 100, "san_to_max 顶到 100")

	# 跨过 24 点进第二天
	GameEngine.state.game_day = 1
	GameEngine.state.game_time = 23
	GameEngine.advance_time(1)
	_check_eq(GameEngine.state.game_day, 2, "跨过 24 点进第二天")
	_check_eq(GameEngine.state.game_time, 0, "小时回零")

	# 睡到早上 6 点
	GameEngine.state.game_day = 3
	GameEngine.state.game_time = 22
	GameEngine.sleep_until_morning()
	_check_eq(GameEngine.state.game_day, 4, "晚上睡觉进第二天")
	_check_eq(GameEngine.state.game_time, 6, "睡到早上 6 点")

	# 没有钟表时只给模糊时间
	_check_eq(GameEngine.has_timepiece(), false, "开局身上没有能看时间的物品")
	_check(GameEngine.get_time_display().find("6:00") == -1, "没钟表时不显示精确时间")

	# 数据里写 advance_hours 也要真的推进时间
	GameEngine.state.game_time = 10
	GameEngine.apply_effects({"advance_hours": 5})
	_check_eq(GameEngine.state.game_time, 15, "advance_hours 推进时间")

	GameEngine.reset_game()