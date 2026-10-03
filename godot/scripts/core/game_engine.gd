extends Node
## 游戏引擎（对应 Python 的 engine/engine.py: GameEngine）。
##
## 作为 autoload 单例挂在 /root/GameEngine 上，全局通过 `GameEngine` 访问。
## 职责：加载 data/*.json、管理 GameState、flag、效果、装备、商店、存读档。
## 本文件不包含任何界面代码——界面靠下面的信号被动刷新。
##
## 【数据目录】Godot 项目在 d:\The adventure\godot\，而 data/ 在上一层。
## 优先读项目内的 res://data/（以后想把数据搬进来就直接生效），
## 没有则回退读上一层的 ../data/。打包后需要把 data/ 复制进 res://。

signal stats_changed          ## 属性/血蓝变化
signal inventory_changed      ## 背包变化
signal room_changed(room_id: String)  ## 房间变化
signal game_loaded            ## 读档完成

## flag 命名空间前缀。新增 flag 必须遵循 [前缀]_[子域]_[含义]，避免命名冲突。
const FLAG_PREFIXES: Array = [
	"loc_", "battle_", "npc_", "item_", "story_", "q_", "sys_", "char_", "san_",
]

const DIRECT_STATS: Array = [
	"hp", "max_hp", "san", "corruption", "attack", "defense", "intelligence", "agility",
]

const EQUIP_SLOTS: Array = ["weapon", "armor", "accessory"]

const MAX_STAT: int = 99
## 只受 0 下限约束、不受 99 上限约束的属性
const NATURAL_UNCAPPED: Array = ["hp", "san"]

const DEFAULT_SETTINGS: Dictionary = {
	"debug_mode": false,
	"text_speed": "medium",
	"corruption_rate": 1.0,
	"sound_enabled": false,
	"skip_intro": false,
	"confirm_return": true,
	"confirm_exit": true,
	"confirm_save": true,
	"history_lines": 200,
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
var _legacy_flag_whitelist: Dictionary = {}

var _data_root: String = ""


func _ready() -> void:
	_data_root = _resolve_data_root()
	_load_all_data()
	state = GameState.new()
	inv_mgr = InventoryManager.new(state, _items_db)
	_init_default_inventory()
	save_mgr = SaveManager.new()
	settings = DEFAULT_SETTINGS.duplicate()
	load_settings()


## ────────────────────────── 数据加载 ──────────────────────────

## 解析数据目录：优先 res://data，否则用 Godot 项目上一层的 data/
func _resolve_data_root() -> String:
	if FileAccess.file_exists("res://data/items.json"):
		return "res://data"
	var project_dir := ProjectSettings.globalize_path("res://")
	var parent := project_dir.path_join("..").simplify_path()
	return parent.path_join("data")


func _load_all_data() -> void:
	_load_items_db()
	_load_rooms_db()
	_load_dialogues_db()
	_load_shops_db()
	_init_flag_whitelist()


func _load_items_db() -> void:
	_items_db = _read_json(_data_root.path_join("items.json"))
	# 合并文本层：desc 放在 items_text.json，实现逻辑与文本分离
	var texts := _read_json(_data_root.path_join("items_text.json"))
	for item_id in texts:
		if _items_db.has(item_id):
			_items_db[item_id]["desc"] = texts[item_id].get("desc", "")


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
				continue
			var room: Dictionary = _rooms_db[room_id]
			var text_data: Dictionary = texts[room_id]
			room["title"] = text_data.get("title", room.get("title", ""))
			room["description"] = text_data.get("description", room.get("description", ""))
			var alt_texts: Array = text_data.get("description_alt", [])
			var alts: Array = room.get("description_alt", [])
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


func _load_shops_db() -> void:
	_shops_db = _read_json(_data_root.path_join("shops.json"))


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


## ────────────────────────── Flag ──────────────────────────

## 校验 flag 名称是否符合命名空间规范
func validate_flag_name(flag_name: String) -> bool:
	if _legacy_flag_whitelist.has(flag_name):
		return true
	for prefix in FLAG_PREFIXES:
		if flag_name.begins_with(prefix) and flag_name.length() > prefix.length():
			return true
	return false


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


## 按条件选取房间描述（description_alt 里第一条满足条件的优先）
func resolve_room_description(room_data: Dictionary) -> String:
	for alt in room_data.get("description_alt", []):
		var cond: Dictionary = alt.get("if", {})
		var matched := true
		for flag_key in cond.get("flags", {}):
			if state.flags.get(flag_key, false) != cond["flags"][flag_key]:
				matched = false
				break
		if not matched:
			continue
		for stat_key in cond.get("stats", {}):
			if state.stats.get(stat_key, 0) < cond["stats"][stat_key]:
				matched = false
				break
		if matched:
			return alt.get("text", room_data.get("description", ""))
	return room_data.get("description", "")


## ────────────────────────── 效果应用 ──────────────────────────

## 把 effects 里涉及的属性变化抽成 [{key, delta}] 列表，供界面提示用
func resolve_stats_changes(effects: Dictionary) -> Array:
	var changes: Array = []
	for stat_key in DIRECT_STATS:
		if effects.has(stat_key):
			changes.append({"key": stat_key, "delta": effects[stat_key]})
	for stat_key in effects.get("stats", {}):
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
		state.room_id = next_room
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