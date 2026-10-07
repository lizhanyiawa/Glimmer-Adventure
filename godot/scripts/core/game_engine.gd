extends Node
## 游戏引擎（对应 Python 的 engine/engine.py: GameEngine）。
##
## 作为 autoload 单例挂在 /root/GameEngine 上，全局通过 `GameEngine` 访问。
## 职责：加载 data/*.json、管理 GameState、flag、效果、装备、商店、存读档。
## 本文件不包含任何界面代码——界面靠下面的信号被动刷新。
##
## 【数据目录】data/ 已收进工程，位于 res://data/（即 godot/data/）。
## 为兼容旧布局，仍保留回退：项目上一层的 ../data/。
## 数据搬进工程后，导出打包才能带上数据（res:// 之外的文件不会被打包）。

signal stats_changed          ## 属性/血蓝变化
signal inventory_changed      ## 背包变化
signal room_changed(room_id: String)  ## 房间变化
signal game_loaded            ## 读档完成
signal time_changed(day: int, hour: int)  ## 游戏内时间变化

## flag 命名空间前缀。新增 flag 必须遵循 [前缀]_[子域]_[含义]，避免命名冲突。
const FLAG_PREFIXES: Array = [
	"loc_", "battle_", "npc_", "item_", "story_", "q_", "sys_", "char_", "san_",
	"codex_",
]

const DIRECT_STATS: Array = [
	"hp", "max_hp", "san", "corruption", "attack", "defense", "intelligence", "agility",
]

const EQUIP_SLOTS: Array = ["weapon", "armor", "accessory"]

const MAX_STAT: int = 99
## 只受 0 下限约束、不受 99 上限约束的属性
const NATURAL_UNCAPPED: Array = ["hp", "san"]

## "直接回满"的写法：数据里写 hp_to_max / san_to_max，就不用写死 +999，
## 将来数值膨胀到多少都能顶满（睡觉、大回复点等用它）。
const TO_MAX_KEYS: Dictionary = {
	"hp_to_max": "hp",
	"san_to_max": "san",
}

## 时间显示：把一天切成几段，没有钟表时只能大致判断
const TIME_OF_DAY: Array = [
	[0, 4, "深夜"], [5, 7, "清晨"], [8, 11, "上午"],
	[12, 13, "正午"], [14, 17, "下午"], [18, 19, "黄昏"], [20, 23, "夜晚"],
]

const DEFAULT_SETTINGS: Dictionary = {
	"debug_mode": false,
	"text_speed": "medium",
	"sound_enabled": false,
	"skip_intro": false,
	"confirm_return": true,
	"confirm_exit": true,
	"confirm_save": true,
	"history_lines": 200,
	"font_style": "system",
	"ui_font_level": 1,
}

const CONFIG_PATH: String = "user://engine_config.json"

var state: GameState
var inv_mgr: InventoryManager
var save_mgr: SaveManager
var settings: Dictionary = {}

var _items_db: Dictionary = {}
var _rooms_db: Dictionary = {}
var _dialogues_db: Dictionary = {}
var _shops_db: Dictionary = {}
var _enemies_db: Dictionary = {}
## 百科（游戏内 wiki）：分类与词条都在 codex.json，词条正文是一整段 BBCode 文本
var _codex_db: Dictionary = {}
var _legacy_flag_whitelist: Dictionary = {}

var _data_root: String = ""
## 数据加载阶段收集到的结构性问题（文本层有孤儿条目、描述数量对不上等），
## 交给 validate_data() 一并汇报
var _load_problems: Array = []
## 战斗叙事里合法占位符的匹配式（只允许 {name} / {dmg}）
var _placeholder_re: RegEx = RegEx.create_from_string("\\{([A-Za-z_]+)\\}")


func _ready() -> void:
	_data_root = _resolve_data_root()
	_load_all_data()
	state = GameState.new()
	inv_mgr = InventoryManager.new(state, _items_db)
	_init_default_inventory()
	save_mgr = SaveManager.new()
	settings = DEFAULT_SETTINGS.duplicate()
	load_settings()
	validate_data()


## ────────────────────────── 数据加载 ──────────────────────────

## 解析数据目录：优先 res://data（数据已收进工程），
## 找不到才回退到 Godot 项目上一层的 ../data/（兼容旧布局）
func _resolve_data_root() -> String:
	if FileAccess.file_exists("res://data/items.json"):
		return "res://data"
	var project_dir := ProjectSettings.globalize_path("res://")
	var parent := project_dir.path_join("..").simplify_path()
	return parent.path_join("data")


func _load_all_data() -> void:
	_load_problems = []
	_load_items_db()
	_load_rooms_db()
	_load_dialogues_db()
	_load_shops_db()
	_load_enemies_db()
	_load_codex_db()
	_init_flag_whitelist()


func _load_items_db() -> void:
	_items_db = _read_json(_data_root.path_join("items.json"))
	# 合并文本层：desc 放在 items_text.json，实现逻辑与文本分离
	var texts := _read_json(_data_root.path_join("items_text.json"))
	for item_id in texts:
		if _items_db.has(item_id):
			_items_db[item_id]["desc"] = texts[item_id].get("desc", "")
		else:
			_load_problems.append("items_text.json 里的 '%s' 在 items.json 中没有对应物品" % item_id)


func _load_rooms_db() -> void:
	_rooms_db = {}
	for entry in _list_json_files(_data_root.path_join("rooms")):
		var chunk := _read_json(entry)
		for room_id in chunk:
			_rooms_db[room_id] = chunk[room_id]

	# 合并文本层：title / description / description_alt
	for entry in _list_json_files(_data_root.path_join("rooms_text")):
		var texts := _read_json(entry)
		for room_id in texts:
			if not _rooms_db.has(room_id):
				_load_problems.append("rooms_text 里的 '%s' 在 rooms/ 中没有对应房间" % room_id)
				continue
			var room: Dictionary = _rooms_db[room_id]
			var text_data: Dictionary = texts[room_id]
			room["title"] = text_data.get("title", room.get("title", ""))
			room["description"] = text_data.get("description", room.get("description", ""))
			var alt_texts: Array = text_data.get("description_alt", [])
			var alts: Array = room.get("description_alt", [])
			if alt_texts.size() != alts.size():
				_load_problems.append("房间 '%s' 的 description_alt 文本数(%d)与条件数(%d)对不上" % [room_id, alt_texts.size(), alts.size()])
			for i in range(min(alt_texts.size(), alts.size())):
				alts[i]["text"] = alt_texts[i]
	if _rooms_db.is_empty():
		push_error("未能加载任何房间数据，数据目录: %s" % _data_root)


func _load_dialogues_db() -> void:
	_dialogues_db = _read_json(_data_root.path_join("dialogues.json"))
	var texts := _read_json(_data_root.path_join("dialogues_text.json"))
	for dlg_id in texts:
		if _dialogues_db.has(dlg_id):
			_dialogues_db[dlg_id]["text"] = texts[dlg_id].get("text", "")
		else:
			_load_problems.append("dialogues_text.json 里的 '%s' 在 dialogues.json 中没有对应对话" % dlg_id)


func _load_shops_db() -> void:
	_shops_db = _read_json(_data_root.path_join("shops.json"))


## 敌人数据 + 战斗叙事文本合并（对应 Python 的 engine/battle.py:_load_enemies）。
## 数值在 enemies.json，叙事在 enemies_text.json，保持逻辑与文本分离。
func _load_enemies_db() -> void:
	_enemies_db = _read_json(_data_root.path_join("enemies.json"))
	var texts := _read_json(_data_root.path_join("enemies_text.json"))
	for enemy_id in texts:
		if not _enemies_db.has(enemy_id):
			_load_problems.append("enemies_text.json 里的 '%s' 在 enemies.json 中没有对应敌人" % enemy_id)
			continue
		var enemy: Dictionary = _enemies_db[enemy_id]
		var text_data: Dictionary = texts[enemy_id]
		enemy["description"] = text_data.get("description", "")
		enemy["narrative"] = text_data.get("narrative", {})
		enemy["san_text"] = text_data.get("san_text", "")


## 百科数据：{categories: [...], entries: [...]}。纯文本内容，不再拆逻辑/文本两层。
func _load_codex_db() -> void:
	_codex_db = _read_json(_data_root.path_join("codex.json"))


func _init_default_inventory() -> void:
	inv_mgr.add_by_id("ballpoint_pen")


## 扫描所有数据里出现过的 flag，登记为「旧版白名单」。
## 这些 flag 未带命名空间前缀，但已在数据中使用，运行时不再告警。
func _init_flag_whitelist() -> void:
	_legacy_flag_whitelist = {}
	_collect_flags(_rooms_db)
	_collect_flags(_dialogues_db)


func _collect_flags(node) -> void:
	if node is Dictionary:
		if node.has("flags") and node["flags"] is Dictionary:
			for key in node["flags"]:
				if key is String and not key.is_empty():
					_legacy_flag_whitelist[key] = true
		for key in node:
			_collect_flags(node[key])
	elif node is Array:
		for item in node:
			_collect_flags(item)


## ────────────────────────── 启动期数据自检 ──────────────────────────

## 所有数据加载完之后跑一遍：把"引用了不存在的东西"这类错误在开场就报出来，
## 免得玩到那一步才发现是数据写错了。只在调试构建里执行，正式包不浪费时间。
## 返回发现的问题数量（0 = 干净）。
func validate_data() -> int:
	if not OS.is_debug_build():
		return 0

	var problems: Array = _load_problems.duplicate()
	_check_option_refs(_rooms_db, "room", problems)
	_check_option_refs(_dialogues_db, "dialogue", problems)
	_check_shops(problems)
	_check_enemies(problems)
	# 无前缀 flag 只是"历史遗留、建议补前缀"，不算引用错误，
	# 不能计入返回值——否则干净数据也会被判定为有问题，自测会误报失败。
	_report_unprefixed_flags()

	if problems.is_empty():
		print("[数据自检] 通过：引用完整，没发现明显问题。")
		return 0
	for problem in problems:
		push_warning("[数据自检] " + problem)
	push_warning("[数据自检] 共发现 %d 处问题，详见上方 warning。" % problems.size())
	return problems.size()


## 逐个检查房间 / 对话里所有选项的跳转目标与服务引用
func _check_option_refs(db: Dictionary, kind: String, problems: Array) -> void:
	for owner_id in db:
		var node: Dictionary = db[owner_id]
		var where := "%s/%s" % [kind, owner_id]
		_check_ref(node.get("enter_dialogue", ""), _dialogues_db, where + ".enter_dialogue", problems)
		_check_ref(node.get("shop", ""), _shops_db, where + ".shop", problems)
		for option in node.get("options", []):
			if not (option is Dictionary):
				continue
			var tag := "%s 的选项「%s」" % [where, option.get("text", "")]
			_check_ref(option.get("target_room", ""), _rooms_db, tag + ".target_room", problems)
			_check_ref(option.get("target_dialogue", ""), _dialogues_db, tag + ".target_dialogue", problems)
			_check_ref(option.get("battle", ""), _enemies_db, tag + ".battle", problems)
			_check_ref(option.get("shop", ""), _shops_db, tag + ".shop", problems)
			_check_effect_items(option.get("effects", {}), tag, problems)


## 通用引用检查：目标非空、但目标表里没有，就记一条
func _check_ref(target, db: Dictionary, where: String, problems: Array) -> void:
	if target is String and not target.is_empty() and not db.has(target):
		problems.append("%s 指向了不存在的条目 '%s'" % [where, target])


## 检查 effects 里增删的物品是否存在
func _check_effect_items(effects: Dictionary, where: String, problems: Array) -> void:
	if not (effects is Dictionary):
		return
	var items: Dictionary = effects.get("items", {})
	for item in items.get("add", []):
		var item_id: String = item if item is String else item.get("id", "")
		if not _items_db.has(item_id):
			problems.append("%s 的 effects.items.add 引用了不存在的物品 '%s'" % [where, item_id])
	for item_id in items.get("remove", []):
		if item_id is String and not _items_db.has(item_id):
			problems.append("%s 的 effects.items.remove 引用了不存在的物品 '%s'" % [where, item_id])


## 商店里出售的物品必须在 items.json 里存在
func _check_shops(problems: Array) -> void:
	for shop_id in _shops_db:
		for entry in _shops_db[shop_id].get("items", []):
			var item_id: String = entry.get("item_id", "")
			if not _items_db.has(item_id):
				problems.append("shop/%s 出售的物品 '%s' 在 items.json 里不存在" % [shop_id, item_id])


## 敌人掉落物必须存在；战斗叙事里的占位符只允许 {name} / {dmg}
func _check_enemies(problems: Array) -> void:
	for enemy_id in _enemies_db:
		var enemy: Dictionary = _enemies_db[enemy_id]
		for drop in enemy.get("drops", []):
			var drop_id: String = drop if drop is String else drop.get("id", "")
			if not _items_db.has(drop_id):
				problems.append("enemy/%s 的掉落物 '%s' 在 items.json 里不存在" % [enemy_id, drop_id])
		var narrative = enemy.get("narrative", {})
		if not (narrative is Dictionary):
			continue
		for key in narrative:
			var variants: Array = narrative[key] if narrative[key] is Array else [narrative[key]]
			for text in variants:
				if not (text is String):
					continue
				for m in _placeholder_re.search_all(text):
					var placeholder := m.get_string(1)
					if placeholder != "name" and placeholder != "dmg":
						problems.append("enemy/%s 的叙事 '%s' 用了未知占位符 {%s}（只支持 {name}/{dmg}）" % [enemy_id, key, placeholder])


## 旧版遗留的无前缀 flag 汇总成一条提示（不参与错误计数）
func _report_unprefixed_flags() -> void:
	var unprefixed: Array = []
	for flag_key in _legacy_flag_whitelist:
		if not _has_namespace(flag_key):
			unprefixed.append(flag_key)
	if unprefixed.is_empty():
		return
	unprefixed.sort()
	push_warning("[数据自检] 有 %d 个旧版 flag 没有命名空间前缀，建议逐步补上：%s" % [unprefixed.size(), ", ".join(PackedStringArray(unprefixed))])


## flag 是否带了合法命名空间前缀
func _has_namespace(flag_name: String) -> bool:
	for prefix in FLAG_PREFIXES:
		if flag_name.begins_with(prefix) and flag_name.length() > prefix.length():
			return true
	return false


## ────────────────────────── 查询接口 ──────────────────────────

func get_item_def(item_id: String) -> Dictionary:
	return _items_db.get(item_id, {})


func get_room(room_id: String) -> Dictionary:
	var room_data = _rooms_db.get(room_id)
	if room_data is Dictionary:
		var result: Dictionary = room_data.duplicate(true)
		result["id"] = room_id
		return result
	return {}


func get_dialogue(dialogue_id: String) -> Dictionary:
	var dlg_data = _dialogues_db.get(dialogue_id)
	if dlg_data is Dictionary:
		var result: Dictionary = dlg_data.duplicate(true)
		result["id"] = dialogue_id
		return result
	return {}


## 取一份敌人数据（含合并进来的叙事文本）。找不到返回空字典。
func get_enemy(enemy_id: String) -> Dictionary:
	var enemy_data = _enemies_db.get(enemy_id)
	if enemy_data is Dictionary:
		return enemy_data.duplicate(true)
	return {}


func get_shop(shop_id: String) -> Dictionary:
	var shop_data = _shops_db.get(shop_id)
	if not (shop_data is Dictionary):
		return {}
	var shop: Dictionary = shop_data.duplicate(true)
	shop["id"] = shop_id
	# 把每个商品条目展开成完整物品定义，界面直接可用
	var rich_items: Array = []
	for entry in shop.get("items", []):
		var item_def := get_item_def(entry.get("item_id", ""))
		rich_items.append({
			"item_id": entry.get("item_id", ""),
			"name": item_def.get("name", entry.get("item_id", "")),
			"desc": item_def.get("desc", ""),
			"type": item_def.get("type", "misc"),
			"price": entry.get("price", 0),
			"stock": entry.get("stock", -1),
		})
	shop["items"] = rich_items
	return shop


## ────────────────────────── 百科 ──────────────────────────

## 百科分类列表，形如 [{id, name}, ...]
func get_codex_categories() -> Array:
	var cats = _codex_db.get("categories", [])
	return cats if cats is Array else []


## 百科全部词条（不筛选、不判定解锁）
func get_codex_entries() -> Array:
	var entries = _codex_db.get("entries", [])
	return entries if entries is Array else []


## 词条是否已解锁：没有 unlock 字段视为开局就知道，否则看对应 flag
func is_codex_unlocked(entry: Dictionary) -> bool:
	var key := str(entry.get("unlock", ""))
	if key.is_empty():
		return true
	return bool(get_flag(key, false))


## 已解锁 / 总数，给界面显示进度用
func get_codex_progress() -> Array:
	var total := 0
	var unlocked := 0
	for entry in get_codex_entries():
		total += 1
		if is_codex_unlocked(entry):
			unlocked += 1
	return [unlocked, total]


## ────────────────────────── Flag ──────────────────────────

## 校验 flag 名称是否符合命名空间规范
func validate_flag_name(flag_name: String) -> bool:
	return _legacy_flag_whitelist.has(flag_name) or _has_namespace(flag_name)


func get_flag(key: String, default_value = false):
	return state.flags.get(key, default_value)


func set_flag(key: String, value) -> void:
	if not validate_flag_name(key):
		push_warning("Flag '%s' 未使用前缀命名空间，建议使用 %s 之一" % [key, FLAG_PREFIXES])
	state.flags[key] = value


func delete_flag(key: String) -> void:
	state.flags.erase(key)


## ────────────────────────── 条件判定 ──────────────────────────

## 检测选项可见性。返回 "visible" / "hidden"（灰显）/ "excluded"（完全不显示）。
## exclude.flags 是 OR 逻辑：任一条件命中即排除。
## require.flags 是 AND 逻辑：全部满足才显示。
func check_option_visible(option: Dictionary) -> String:
	var excludes: Dictionary = option.get("exclude", {})
	for flag_key in excludes.get("flags", {}):
		if state.flags.get(flag_key, false) == excludes["flags"][flag_key]:
			return "excluded"

	var reqs: Dictionary = option.get("require", {})
	if reqs.is_empty():
		return "visible"

	for stat_key in reqs.get("stats", {}):
		if state.stats.get(stat_key, 0) < reqs["stats"][stat_key]:
			return "hidden"

	for flag_key in reqs.get("flags", {}):
		if state.flags.get(flag_key, false) != reqs["flags"][flag_key]:
			return "hidden"

	var item_reqs: Dictionary = reqs.get("items", {})
	if not item_reqs.is_empty():
		var has_id = item_reqs.get("has", "")
		if not has_id.is_empty() and not inv_mgr.has(has_id):
			return "hidden"

	return "visible"


## 选项的「焕新条件」是否成立。语法与 require / exclude 完全一致
## （flags / stats / items），写在选项自己的 relight 字段里：
##
##   "relight": {
##     "require": { "items": { "has": "cellar_chest_key" } },
##     "exclude": { "flags": { "chest_opened": true } }
##   }
##
## 用途：查看类选项去过一次就会变暗，但"再看一眼"有时候会有新东西——
## 拿到钥匙之后那只铁皮木箱就值得再翻一次。条件成立时按钮重新亮起，
## 条件解除（箱子开过了）又暗回去，所以是双向的，不是一次性解锁。
func is_option_relit(option: Dictionary) -> bool:
	var relight: Dictionary = option.get("relight", {})
	if relight.is_empty():
		return false
	var probe := {
		"require": relight.get("require", {}),
		"exclude": relight.get("exclude", {}),
	}
	return check_option_visible(probe) == "visible"


## 按条件选取房间描述（description_alt 里第一条满足条件的优先）。
##
## if 支持的条件键（多个键之间是 AND）：
##   flags  —— {flag名: 期望值}
##   stats  —— {属性名: 最低值}
##   period —— 时段名，或时段名数组（数组内是 OR）。时段名取自 TIME_OF_DAY，
##             如 "清晨" / ["黄昏", "夜晚"]。没有钟表也能按"大致时段"换文案。
func resolve_room_description(room_data: Dictionary) -> String:
	for alt in room_data.get("description_alt", []):
		var cond: Dictionary = alt.get("if", {})
		if _room_alt_matches(cond):
			return alt.get("text", room_data.get("description", ""))
	return room_data.get("description", "")


## 一段 description_alt 的条件是否成立
func _room_alt_matches(cond: Dictionary) -> bool:
	for flag_key in cond.get("flags", {}):
		if state.flags.get(flag_key, false) != cond["flags"][flag_key]:
			return false
	for stat_key in cond.get("stats", {}):
		if state.stats.get(stat_key, 0) < cond["stats"][stat_key]:
			return false
	if cond.has("period") and not _period_matches(cond["period"]):
		return false
	return true


## 当前时段是否命中 period 条件（字符串或字符串数组，数组内 OR）
func _period_matches(period) -> bool:
	var now := _time_of_day_name()
	if period is Array:
		return (period as Array).has(now)
	return str(period) == now


## ────────────────────────── 效果应用 ──────────────────────────

## 把 effects 里涉及的属性变化抽成 [{key, delta}] 列表，供界面提示用
func resolve_stats_changes(effects: Dictionary) -> Array:
	var changes: Array = []
	var to_max_keys: Array = []
	for marker in TO_MAX_KEYS:
		if effects.has(marker) and effects[marker]:
			var target: String = TO_MAX_KEYS[marker]
			changes.append({"key": target, "to_max": true})
			to_max_keys.append(target)
	for stat_key in DIRECT_STATS:
		if effects.has(stat_key) and not to_max_keys.has(stat_key):
			changes.append({"key": stat_key, "delta": effects[stat_key]})
	for stat_key in effects.get("stats", {}):
		if not to_max_keys.has(stat_key):
			changes.append({"key": stat_key, "delta": effects["stats"][stat_key]})
	return changes


## 应用 effects（属性 / flag / 物品 / 任务 / 笔记），不处理房间跳转
func apply_effects(effects: Dictionary) -> void:
	if effects.is_empty():
		return

	var changed_stats := false

	# 顶层直接写的属性（如 "hp": -10）
	for stat_key in DIRECT_STATS:
		if effects.has(stat_key):
			_apply_stat_delta(stat_key, effects[stat_key])
			changed_stats = true

	# 统一放在 stats 里的属性
	for stat_key in effects.get("stats", {}):
		_apply_stat_delta(stat_key, effects["stats"][stat_key])
		changed_stats = true

	# 直接回满（睡觉等）：不写具体数字，顶到上限就行
	for marker in TO_MAX_KEYS:
		if effects.has(marker) and effects[marker]:
			_apply_stat_to_max(TO_MAX_KEYS[marker])
			changed_stats = true

	# 时间推进：睡觉 / 长时间动作由数据控制
	if effects.has("advance_hours"):
		advance_time(int(effects["advance_hours"]))
	if effects.get("sleep_until_morning", false):
		sleep_until_morning()

	# 夹紧上限
	if state.stats.has("hp") and state.stats.has("max_hp"):
		state.stats["hp"] = min(state.stats["hp"], state.stats["max_hp"])
	if state.stats.has("san"):
		state.stats["san"] = min(state.stats["san"], 100)

	for flag_key in effects.get("flags", {}):
		set_flag(flag_key, effects["flags"][flag_key])

	var items: Dictionary = effects.get("items", {})
	for item in items.get("add", []):
		if item is String:
			inv_mgr.add_by_id(item)
		elif item is Dictionary:
			inv_mgr.add(
				item.get("id", ""),
				item.get("name", ""),
				item.get("desc", ""),
				item.get("type", "misc"),
				item.get("qty", 1)
			)
	for item_id in items.get("remove", []):
		inv_mgr.remove(item_id)
	if not items.is_empty():
		inventory_changed.emit()

	var tasks: Dictionary = effects.get("tasks", {})
	for task in tasks.get("add", []):
		var task_id: String = task.get("id", "task_%d" % state.diary["tasks"].size())
		if not _has_task(task_id):
			state.diary["tasks"].append({
				"id": task_id,
				"title": task.get("title", "未命名任务"),
				"content": task.get("content", ""),
				"done": false,
			})
			set_flag("sys_diary_unread", true)
	for task_id in tasks.get("complete", []):
		for task in state.diary["tasks"]:
			if task.get("id") == task_id:
				task["done"] = true
				set_flag("sys_diary_unread", true)
				break

	for note in effects.get("notes", {}).get("add", []):
		var note_id: String = note.get("id", "note_%d" % state.diary["notes"].size())
		if not _has_note(note_id):
			state.diary["notes"].append({
				"id": note_id,
				"title": note.get("title", "未命名笔记"),
				"content": note.get("content", ""),
				"created": note.get("created", Time.get_datetime_string_from_system(false, true)),
			})
			set_flag("sys_diary_unread", true)

	if changed_stats:
		stats_changed.emit()


func _apply_stat_delta(stat_key: String, delta) -> void:
	if not state.stats.has(stat_key):
		return
	var new_val = state.stats[stat_key] + delta
	if stat_key in NATURAL_UNCAPPED:
		state.stats[stat_key] = max(0, new_val)
	else:
		state.stats[stat_key] = clampi(int(new_val), 0, MAX_STAT)


## 把某项属性直接顶到上限（回满）
func _apply_stat_to_max(stat_key: String) -> void:
	if not state.stats.has(stat_key):
		return
	if stat_key == "hp":
		state.stats["hp"] = int(state.stats.get("max_hp", 100))
	elif stat_key == "san":
		state.stats["san"] = 100
	else:
		state.stats[stat_key] = MAX_STAT


## ────────────────────────── 游戏内时间 ──────────────────────────

## 推进 hours 小时，跨过 24 点就进到第二天
func advance_time(hours: int) -> void:
	if hours == 0:
		return
	state.game_time += hours
	while state.game_time >= 24:
		state.game_time -= 24
		state.game_day += 1
	time_changed.emit(state.game_day, state.game_time)


## 睡到第二天早上 6 点（凌晨入睡就当当天早上）
func sleep_until_morning() -> void:
	if state.game_time >= 6:
		state.game_day += 1
	state.game_time = 6
	time_changed.emit(state.game_day, state.game_time)


## 现在能不能看到"几点几分"：身上有能看时间的物品，或当前房间里有钟表
func has_timepiece() -> bool:
	for item in inv_mgr.all():
		if get_item_def(item.get("id", "")).get("shows_time", false):
			return true
	for slot in state.equipment:
		var entry: Dictionary = state.equipment[slot]
		if get_item_def(entry.get("item_id", "")).get("shows_time", false):
			return true
	return get_room(state.room_id).get("timepiece", false)


## 顶部时间显示：有钟表就是"第 N 天 14:00"，否则只给"下午"这种大致判断
func get_time_display() -> String:
	if has_timepiece():
		return "第 %d 天 %02d:00" % [state.game_day, state.game_time]
	return "第 %d 天 %s" % [state.game_day, _time_of_day_name()]


func _time_of_day_name() -> String:
	for span in TIME_OF_DAY:
		if state.game_time >= int(span[0]) and state.game_time <= int(span[1]):
			return span[2]
	return "夜里"


func _has_task(task_id: String) -> bool:
	for task in state.diary["tasks"]:
		if task.get("id") == task_id:
			return true
	return false


func _has_note(note_id: String) -> bool:
	for note in state.diary["notes"]:
		if note.get("id") == note_id:
			return true
	return false


## 选中一个选项：应用效果并跳转房间/对话
func select_option(option: Dictionary) -> Dictionary:
	apply_effects(option.get("effects", {}))

	var next_room: String = option.get("target_room", "")
	var next_dialogue: String = option.get("target_dialogue", "")

	if not next_dialogue.is_empty():
		state.dialogue_id = next_dialogue
	elif not next_room.is_empty():
		var moved := next_room != state.room_id
		state.room_id = next_room
		# 真正换了房间才推进 1 小时；原地休息/睡觉交给 effects 里的时间字段
		if moved:
			advance_time(1)
		# enter_dialogue：进入房间后自动触发的对话
		var room_def: Dictionary = _rooms_db.get(next_room, {})
		state.dialogue_id = room_def.get("enter_dialogue", "")
		room_changed.emit(state.room_id)

	return {
		"success": true,
		"next_room": state.room_id,
		"next_dialogue": state.dialogue_id,
		"effects_applied": option.get("effects", {}),
	}


## ────────────────────────── 装备 ──────────────────────────

func equip(item_id: String) -> Dictionary:
	var item_def := get_item_def(item_id)
	if item_def.is_empty():
		return {"success": false, "message": "物品数据不存在"}

	var slot: String = item_def.get("equip_slot", "")
	if slot.is_empty():
		return {"success": false, "message": "这件物品无法装备"}

	var equip_stats: Dictionary = item_def.get("equip_stats", {})
	if equip_stats.is_empty():
		return {"success": false, "message": "这件物品没有属性加成"}

	if state.equipment.has(slot):
		return {"success": false, "message": "该位置已有装备，请先卸下"}

	if not inv_mgr.remove(item_id, 1):
		return {"success": false, "message": "背包中没有这件物品"}

	for stat_key in equip_stats:
		if state.stats.has(stat_key):
			state.stats[stat_key] += equip_stats[stat_key]

	state.equipment[slot] = {
		"item_id": item_id,
		"name": item_def.get("name", item_id),
		"stats": equip_stats.duplicate(),
	}

	stats_changed.emit()
	inventory_changed.emit()
	return {
		"success": true,
		"message": "装备了 %s" % item_def.get("name", item_id),
		"slot": slot,
		"stats": equip_stats,
	}


func unequip(slot: String) -> Dictionary:
	if not state.equipment.has(slot):
		return {"success": false, "message": "该位置没有装备"}

	var entry: Dictionary = state.equipment[slot]
	var item_id: String = entry.get("item_id", "")

	for stat_key in entry.get("stats", {}):
		if state.stats.has(stat_key):
			state.stats[stat_key] = max(0, state.stats[stat_key] - entry["stats"][stat_key])

	var item_def := get_item_def(item_id)
	inv_mgr.add(
		item_id,
		item_def.get("name", entry.get("name", item_id)),
		item_def.get("desc", ""),
		item_def.get("type", "misc"),
		1
	)

	state.equipment.erase(slot)
	stats_changed.emit()
	inventory_changed.emit()
	return {"success": true, "message": "卸下了 %s" % entry.get("name", item_id), "slot": slot}


func get_equipment() -> Dictionary:
	return state.equipment.duplicate(true)


func get_equipped_stats_summary() -> Dictionary:
	var total: Dictionary = {}
	for entry in state.equipment.values():
		for key in entry.get("stats", {}):
			total[key] = total.get(key, 0) + entry["stats"][key]
	return total


## ────────────────────────── 商店 ──────────────────────────

func buy_item(shop_id: String, item_id: String, qty: int = 1) -> Dictionary:
	var shop_data = _shops_db.get(shop_id)
	if not (shop_data is Dictionary):
		return {"success": false, "message": "商店不存在。", "cost": 0}

	var shop_entry: Dictionary = {}
	for entry in shop_data.get("items", []):
		if entry.get("item_id") == item_id:
			shop_entry = entry
			break
	if shop_entry.is_empty():
		return {"success": false, "message": "该商品不出售。", "cost": 0}

	var stock: int = shop_entry.get("stock", -1)
	if stock >= 0 and stock < qty:
		return {"success": false, "message": "库存不足。", "cost": 0}

	var cost: int = int(shop_entry.get("price", 0)) * qty
	var coins: int = state.stats.get("coins", 0)
	if coins < cost:
		return {
			"success": false,
			"message": "铜币不足——需要 %d 枚，你只有 %d 枚。" % [cost, coins],
			"cost": 0,
		}

	state.stats["coins"] = coins - cost
	inv_mgr.add_by_id(item_id, qty)
	if stock >= 0:
		shop_entry["stock"] = stock - qty

	stats_changed.emit()
	inventory_changed.emit()
	return {
		"success": true,
		"message": "购买了%s ×%d。" % [get_item_def(item_id).get("name", item_id), qty],
		"cost": cost,
	}


func sell_item(item_id: String, qty: int = 1) -> Dictionary:
	var item_def := get_item_def(item_id)
	if item_def.is_empty():
		return {"success": false, "message": "物品不存在。", "earned": 0}

	var value: int = item_def.get("value", 0)
	if value <= 0:
		return {"success": false, "message": "这东西卖不了钱。", "earned": 0}

	if not inv_mgr.has(item_id, qty):
		return {"success": false, "message": "你没有足够的该物品。", "earned": 0}

	var earned: int = int(value * qty * 0.4)
	inv_mgr.remove(item_id, qty)
	state.stats["coins"] = state.stats.get("coins", 0) + earned

	stats_changed.emit()
	inventory_changed.emit()
	return {
		"success": true,
		"message": "出售了%s ×%d，获得 %d 枚铜币。" % [item_def.get("name", item_id), qty, earned],
		"earned": earned,
	}


## ────────────────────────── 使用物品 ──────────────────────────

## 使用一件消耗品：先查数据里的 effect，再判断"用了到底有没有变化"，
## 最后才扣数量、套效果。血满了就不该白白浪费一瓶药。
func use_item(item_id: String) -> Dictionary:
	var item_def := get_item_def(item_id)
	if item_def.is_empty():
		return {"success": false, "message": "物品不存在。"}
	var effect: Dictionary = item_def.get("effect", {})
	if effect.is_empty():
		return {"success": false, "message": "这东西现在用不了。"}
	if not inv_mgr.has(item_id):
		return {"success": false, "message": "背包里没有这件物品。"}
	if not _effect_would_change(effect):
		return {"success": false, "message": "现在不需要用它。"}

	inv_mgr.remove(item_id, 1)
	apply_effects(effect)
	inventory_changed.emit()
	return {"success": true, "message": "使用了「%s」。" % item_def.get("name", item_id)}


## 这组效果在当前状态下会不会真的产生变化（用于拦住"满血嗑药"这种浪费）
func _effect_would_change(effect: Dictionary) -> bool:
	# 把顶层属性和 stats 里写的属性合并成一张表，再逐个看有没有实际增量
	var merged: Dictionary = {}
	for stat_key in DIRECT_STATS:
		if effect.has(stat_key):
			merged[stat_key] = int(effect[stat_key])
	for stat_key in effect.get("stats", {}):
		merged[stat_key] = merged.get(stat_key, 0) + int(effect["stats"][stat_key])

	for stat_key in merged:
		if not state.stats.has(stat_key):
			continue
		var current := int(state.stats[stat_key])
		var cap := MAX_STAT
		if stat_key == "hp":
			cap = int(state.stats.get("max_hp", 9999))
		elif stat_key == "san":
			cap = 100
		if clampi(current + int(merged[stat_key]), 0, cap) != current:
			return true
	return false


## ────────────────────────── 地面物品 ──────────────────────────

## 取某个房间地上的物品（默认当前房间）。每项都带上 ground=true 与下标，
## 供物品栏的「地上」分区渲染与捡起。
func get_ground_items(room_id: String = "") -> Array:
	var rid: String = room_id if not room_id.is_empty() else state.room_id
	var list: Array = state.ground.get(rid, [])
	var result: Array = []
	for i in range(list.size()):
		var copy: Dictionary = list[i].duplicate()
		copy["ground"] = true
		copy["ground_index"] = i
		result.append(copy)
	return result


## 把背包里的一件物品丢到当前房间的地上（同 id 会自动堆叠）
func drop_to_ground(item: Dictionary) -> Dictionary:
	var item_id: String = item.get("id", "")
	if item_id.is_empty() or not inv_mgr.has(item_id):
		return {"success": false, "message": "背包里没有这件物品。"}
	if not inv_mgr.remove(item_id, 1):
		return {"success": false, "message": "丢弃失败。"}

	var rid := state.room_id
	var list: Array = state.ground.get(rid, [])
	var merged := false
	for entry in list:
		if entry.get("id") == item_id:
			entry["qty"] = int(entry.get("qty", 1)) + 1
			merged = true
			break
	if not merged:
		list.append({
			"id": item_id,
			"name": item.get("name", item_id),
			"desc": item.get("desc", ""),
			"type": item.get("type", "misc"),
			"qty": 1,
		})
	state.ground[rid] = list

	inventory_changed.emit()
	return {"success": true, "message": "丢弃了「%s」" % item.get("name", item_id)}


## 从当前房间地上捡回第 index 条
func pick_up_ground_item(index: int) -> Dictionary:
	var rid := state.room_id
	var list: Array = state.ground.get(rid, [])
	if index < 0 or index >= list.size():
		return {"success": false, "message": "这里没有这件东西。"}

	var entry: Dictionary = list[index]
	var item_id: String = entry.get("id", "")
	inv_mgr.add(
		item_id,
		entry.get("name", item_id),
		entry.get("desc", ""),
		entry.get("type", "misc"),
		int(entry.get("qty", 1))
	)
	list.remove_at(index)
	if list.is_empty():
		state.ground.erase(rid)
	else:
		state.ground[rid] = list

	inventory_changed.emit()
	return {"success": true, "message": "捡起了「%s」" % entry.get("name", item_id)}


## ────────────────────────── 存读档 ──────────────────────────

func save_game(slot: int) -> bool:
	return save_mgr.save(state, slot)


func load_game(slot: int) -> bool:
	var ok := save_mgr.load_slot(state, slot)
	if ok:
		# 读档会整体替换 state 内容，背包管理器需重新指向新的物品表
		inv_mgr = InventoryManager.new(state, _items_db)
		game_loaded.emit()
		stats_changed.emit()
		inventory_changed.emit()
		room_changed.emit(state.room_id)
	return ok


func validate_save(slot: int) -> bool:
	return save_mgr.validate(slot)


func delete_save(slot: int) -> bool:
	return save_mgr.delete(slot)


func get_save_slots() -> Array:
	return save_mgr.get_slots()


## ────────────────────────── 设置 ──────────────────────────

func load_settings() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		settings.merge(parsed, true)
	if settings.get("text_speed") not in ["instant", "fast", "medium", "slow"]:
		settings["text_speed"] = "medium"


func save_settings() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		push_error("设置保存失败: %s" % CONFIG_PATH)
		return
	file.store_string(JSON.stringify(settings, "    "))
	file.close()


## ────────────────────────── 其他 ──────────────────────────

func set_player_name(player_name: String) -> void:
	var final_name := player_name.strip_edges()
	if final_name.is_empty():
		final_name = "无名"
	state.stats["player_name"] = final_name
	set_flag("sys_has_named", true)


func reset_game() -> void:
	state = GameState.new()
	inv_mgr = InventoryManager.new(state, _items_db)
	_init_default_inventory()


## ────────────────────────── 文件工具 ──────────────────────────

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("数据文件不存在: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("JSON 解析失败: %s" % path)
	return {}


## 列出目录下所有 .json 文件路径（目录不存在时返回空数组）
func _list_json_files(dir_path: String) -> Array:
	var files: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return files
	for filename in dir.get_files():
		if filename.ends_with(".json"):
			files.append(dir_path.path_join(filename))
	files.sort()
	return files