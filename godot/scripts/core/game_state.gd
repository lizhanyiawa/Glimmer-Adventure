class_name GameState
extends RefCounted
## 玩家状态容器（对应 Python 的 engine/engine.py: GameState）。
##
## flags 存储所有标记。新 flag 务必遵循命名空间规范：
##   loc_ / battle_ / npc_ / item_ / story_ / q_ / sys_ / char_ / san_

var room_id: String = "thatched_hut_bed"
var dialogue_id: String = ""
var play_time: float = 0.0
var last_saved: String = ""

var stats: Dictionary = {
	"attack": 5,
	"defense": 5,
	"intelligence": 5,
	"agility": 5,
	"hp": 100,
	"max_hp": 100,
	"san": 100,
	"corruption": 0,
	"coins": 0,
}

var inventory: Array = []
var equipment: Dictionary = {}
var diary: Dictionary = {
	"tasks": [],
	"notes": [],
}
var flags: Dictionary = {}


## 序列化，供存档使用
func to_dict() -> Dictionary:
	return {
		"room_id": room_id,
		"dialogue_id": dialogue_id,
		"play_time": play_time,
		"last_saved": last_saved,
		"stats": stats,
		"inventory": inventory,
		"equipment": equipment,
		"diary": diary,
		"flags": flags,
	}


## 从存档数据恢复（就地修改，保持引用不变）
func from_dict(data: Dictionary) -> void:
	room_id = data.get("room_id", room_id)
	dialogue_id = data.get("dialogue_id", "")
	play_time = data.get("play_time", 0.0)
	last_saved = data.get("last_saved", "")

	# JSON 读回来的数字一律是 float，这里按默认值的类型还原成 int，
	# 否则 "HP: 78.0/100.0" 这种显示会很难看。
	var saved_stats: Dictionary = data.get("stats", {})
	for key in saved_stats:
		var val = saved_stats[key]
		if val is float and stats.get(key) is int:
			saved_stats[key] = int(val)
	stats = saved_stats if not saved_stats.is_empty() else stats

	inventory = data.get("inventory", [])
	equipment = data.get("equipment", {})
	diary = data.get("diary", diary)
	flags = data.get("flags", {})