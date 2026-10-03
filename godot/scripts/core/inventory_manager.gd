class_name InventoryManager
extends RefCounted
## 背包管理（对应 Python 的 engine/inventory.py）。
## 只操作 GameState.inventory，不涉及任何界面逻辑。

const ITEM_TYPES: Dictionary = {
	"key": "钥匙",
	"weapon": "武器",
	"armor": "防具",
	"consumable": "消耗品",
	"material": "材料",
	"quest": "任务物品",
	"misc": "杂物",
}

var state: GameState
var _items_db: Dictionary


func _init(p_state: GameState, p_items_db: Dictionary = {}) -> void:
	state = p_state
	_items_db = p_items_db


## 按物品 id 从物品库取定义后加入背包（物品库里没有则忽略）
func add_by_id(item_id: String, qty: int = 1) -> void:
	var item_def: Dictionary = _items_db.get(item_id, {})
	if item_def.is_empty():
		return
	add(
		item_id,
		item_def.get("name", item_id),
		item_def.get("desc", ""),
		item_def.get("type", "misc"),
		qty
	)


## 直接加入背包；已有同名 id 则累加数量
func add(item_id: String, item_name: String, desc: String = "", item_type: String = "misc", qty: int = 1) -> void:
	for item in state.inventory:
		if item["id"] == item_id:
			item["qty"] = item.get("qty", 1) + qty
			return
	state.inventory.append({
		"id": item_id,
		"name": item_name,
		"desc": desc,
		"type": item_type,
		"qty": qty,
	})


## 移除指定数量；数量归零则整条删除。返回是否成功找到该物品。
func remove(item_id: String, qty: int = 1) -> bool:
	for item in state.inventory:
		if item["id"] == item_id:
			item["qty"] = item.get("qty", 1) - qty
			if item["qty"] <= 0:
				state.inventory.erase(item)
			return true
	return false


func has(item_id: String, qty: int = 1) -> bool:
	for item in state.inventory:
		if item["id"] == item_id:
			return item.get("qty", 0) >= qty
	return false


func get_item(item_id: String) -> Dictionary:
	for item in state.inventory:
		if item["id"] == item_id:
			return item
	return {}


## 返回背包列表（副本，改动不会影响原数据）
func all() -> Array:
	return state.inventory.duplicate(true)


func count() -> int:
	var total := 0
	for item in state.inventory:
		total += item.get("qty", 1)
	return total


func type_name(item_type: String) -> String:
	return ITEM_TYPES.get(item_type, item_type)