class_name SaveManager
extends RefCounted
## 存档管理（对应 Python 的 engine/save_manager.py）。
## Godot 版把存档放在 user:// 下（Windows 是 %APPDATA% 对应目录），
## 与项目源码分离，打包后也能正常读写。

const REQUIRED_KEYS: Array = ["room_id", "stats", "inventory", "flags"]
const MAX_SLOTS: int = 9
const SLOT_COUNT: int = 5  ## 界面上显示的槽位数

const SAVE_DIR: String = "user://saves"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


func _valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= MAX_SLOTS


## 保存到指定槽位。成功返回 true。
func save(state: GameState, slot: int) -> bool:
	if not _valid_slot(slot):
		return false
	state.last_saved = Time.get_datetime_string_from_system(false, true)
	var file := FileAccess.open(_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("存档写入失败: %s" % _path(slot))
		return false
	file.store_string(JSON.stringify(state.to_dict(), "    "))
	file.close()
	return true


## 从指定槽位读取。成功返回 true，失败（不存在/校验不过）返回 false。
func load_slot(state: GameState, slot: int) -> bool:
	if not _valid_slot(slot):
		return false
	if not validate(slot):
		return false
	var data := _read_json(_path(slot))
	if data.is_empty():
		return false
	state.from_dict(data)
	# 读档后重置未读状态，避免旧存档的 sys_diary_unread 残留
	state.flags["sys_diary_unread"] = false
	return true


## 校验存档文件是否合法可用
func validate(slot: int) -> bool:
	if not _valid_slot(slot):
		return false
	var path := _path(slot)
	if not FileAccess.file_exists(path):
		return false
	var data := _read_json(path)
	if data.is_empty():
		return false
	for key in REQUIRED_KEYS:
		if not data.has(key):
			return false
	if not (data.get("stats") is Dictionary):
		return false
	if not (data.get("inventory") is Array):
		return false
	if not (data.get("flags") is Dictionary):
		return false
	# 数值范围校验（字符串型 stats 如 player_name 跳过）
	for stat_key in data["stats"]:
		var val = data["stats"][stat_key]
		if not (val is int or val is float):
			continue
		if stat_key == "hp" and not (val >= 0 and val <= 9999):
			return false
		if stat_key == "san" and not (val >= 0 and val <= 200):
			return false
		if stat_key == "corruption" and not (val >= 0 and val <= 100):
			return false
		if not (val >= 0 and val <= 999):
			return false
	return true


func delete(slot: int) -> bool:
	if not _valid_slot(slot):
		return false
	var path := _path(slot)
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


## 返回所有槽位的摘要信息，供存/读档界面显示
func get_slots() -> Array:
	var slots: Array = []
	for i in range(1, SLOT_COUNT + 1):
		var path := _path(i)
		if not FileAccess.file_exists(path):
			slots.append({"slot": i, "exists": false})
			continue
		if not validate(i):
			slots.append({"slot": i, "exists": false, "corrupted": true})
			continue
		var data := _read_json(path)
		var stats: Dictionary = data.get("stats", {})
		slots.append({
			"slot": i,
			"exists": true,
			"room_id": data.get("room_id", "?"),
			"last_saved": data.get("last_saved", "?"),
			"player_name": stats.get("player_name", "无名"),
			"level": stats.get("attack", 1),
		})
	return slots


## 读 JSON 文件，失败返回空字典
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}