from typing import Dict, Any, List, Optional


class InventoryManager:
    ITEM_TYPES = {
        "key": "钥匙",
        "weapon": "武器",
        "armor": "防具",
        "consumable": "消耗品",
        "material": "材料",
        "quest": "任务物品",
        "misc": "杂物",
    }

    def __init__(self, state, items_db=None):
        self.state = state
        self._items_db = items_db or {}

    def add_by_id(self, item_id: str, qty: int = 1):
        item_def = self._items_db.get(item_id, {})
        if not item_def:
            return
        self.add(
            item_id,
            item_def.get("name", item_id),
            item_def.get("desc", ""),
            item_def.get("type", "misc"),
            qty
        )

    def add(self, item_id: str, name: str, desc: str = "", item_type: str = "misc", qty: int = 1):
        for item in self.state.inventory:
            if item["id"] == item_id:
                item["qty"] = item.get("qty", 1) + qty
                return
        self.state.inventory.append({
            "id": item_id,
            "name": name,
            "desc": desc,
            "type": item_type,
            "qty": qty,
        })

    def remove(self, item_id: str, qty: int = 1) -> bool:
        for item in self.state.inventory:
            if item["id"] == item_id:
                item["qty"] = item.get("qty", 1) - qty
                if item["qty"] <= 0:
                    self.state.inventory.remove(item)
                return True
        return False

    def has(self, item_id: str, qty: int = 1) -> bool:
        for item in self.state.inventory:
            if item["id"] == item_id:
                return item.get("qty", 0) >= qty
        return False

    def get(self, item_id: str) -> Optional[Dict[str, Any]]:
        for item in self.state.inventory:
            if item["id"] == item_id:
                return item
        return None

    def all(self) -> List[Dict[str, Any]]:
        return list(self.state.inventory)

    def count(self) -> int:
        return sum(item.get("qty", 1) for item in self.state.inventory)

    def type_name(self, item_type: str) -> str:
        return self.ITEM_TYPES.get(item_type, item_type)