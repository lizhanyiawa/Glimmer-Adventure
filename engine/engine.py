import os
import json
from typing import Dict, Any, List
from engine.inventory import InventoryManager
from engine.save_manager import SaveManager
from engine.paths import data_path, config_path


DIRECT_STATS = ["hp", "max_hp", "san", "corruption", "attack", "defense", "intelligence", "agility"]


class GameState:
    def __init__(self):
        self.room_id: str = "thatched_hut_bed"
        self.dialogue_id: str = ""
        self.play_time: float = 0.0
        self.last_saved: str = ""

        self.stats: Dict[str, Any] = {
            "attack": 5,
            "defense": 3,
            "intelligence": 5,
            "agility": 5,
            "hp": 100,
            "max_hp": 100,
            "san": 100,
            "corruption": 0,
        }

        self.inventory: List[Dict[str, Any]] = []

        self.diary: Dict[str, Any] = {
            "tasks": [],
            "notes": [],
        }

        self.flags: Dict[str, bool] = {
            "met_alice": False,
            "classroom_power_cut": False,
            "corridor_guarded": True,
        }


class GameEngine:
    def __init__(self):
        self._items_db: Dict[str, Any] = {}
        self._rooms_db: Dict[str, Any] = {}
        self._dialogues_db: Dict[str, Any] = {}

        self._load_items_db()
        self._load_rooms_db()
        self._load_dialogues_db()

        self.state: GameState = GameState()
        self.inv_mgr = InventoryManager(self.state, self._items_db)
        self._init_default_inventory()

        self.save_mgr: SaveManager = SaveManager()
        self.config_file: str = config_path()

        self.settings: Dict[str, Any] = {
            "debug_mode": False,
            "text_speed": "medium",
            "corruption_rate": 1.0,
            "sound_enabled": False,
            "skip_intro": False,
            "confirm_return": True,
            "confirm_exit": True,
            "confirm_save": True,
            "history_lines": 200,
        }

        self.load_settings()

    def _load_items_db(self):
        try:
            with open(data_path("items.json"), "r", encoding="utf-8") as f:
                self._items_db = json.load(f)
        except Exception as e:
            print(f"[ERROR] 加载 items.json 失败: {e}")
            self._items_db = {}

    def _load_rooms_db(self):
        try:
            with open(data_path("rooms.json"), "r", encoding="utf-8") as f:
                self._rooms_db = json.load(f)
        except Exception as e:
            print(f"[ERROR] 加载 rooms.json 失败: {e}")
            self._rooms_db = {}

    def _load_dialogues_db(self):
        try:
            with open(data_path("dialogues.json"), "r", encoding="utf-8") as f:
                self._dialogues_db = json.load(f)
        except Exception as e:
            print(f"[ERROR] 加载 dialogues.json 失败: {e}")
            self._dialogues_db = {}

    def _init_default_inventory(self):
        for item_id in ["ballpoint_pen"]:
            self.inv_mgr.add_by_id(item_id)

    def get_item_def(self, item_id: str) -> Dict[str, Any]:
        return self._items_db.get(item_id, {})

    def get_room(self, room_id: str) -> Dict[str, Any]:
        room_data = self._rooms_db.get(room_id)
        if room_data:
            return {"id": room_id, **room_data}
        return {}

    def get_dialogue(self, dialogue_id: str) -> Dict[str, Any]:
        dlg_data = self._dialogues_db.get(dialogue_id)
        if dlg_data:
            return {"id": dialogue_id, **dlg_data}
        return {}

    def resolve_stats_changes(self, effects: Dict[str, Any]) -> List[Dict[str, Any]]:
        changes = []

        for stat_key in DIRECT_STATS:
            if stat_key in effects:
                changes.append({"key": stat_key, "delta": effects[stat_key]})

        for stat_key, delta in effects.get("stats", {}).items():
            changes.append({"key": stat_key, "delta": delta})

        return changes

    def save_game(self, slot: int) -> bool:
        return self.save_mgr.save(self.state, slot)

    def load_game(self, slot: int) -> bool:
        return self.save_mgr.load(self.state, slot)

    def validate_save(self, slot: int) -> bool:
        return self.save_mgr.validate(slot)

    def delete_save(self, slot: int) -> bool:
        return self.save_mgr.delete(slot)

    def get_save_slots(self) -> List[Dict[str, Any]]:
        return self.save_mgr.get_slots()

    def load_settings(self):
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, "r", encoding="utf-8") as f:
                    saved = json.load(f)
                self.settings.update(saved)
                if self.settings.get("text_speed") not in ("instant", "fast", "medium", "slow"):
                    self.settings["text_speed"] = "medium"
            except Exception as e:
                print(f"[ERROR] 加载设置失败: {e}")

    def save_settings(self):
        try:
            with open(self.config_file, "w", encoding="utf-8") as f:
                json.dump(self.settings, f, ensure_ascii=False, indent=4)
        except Exception as e:
            print(f"[ERROR] 保存设置失败: {e}")

    def set_player_name(self, name: str):
        if not name.strip():
            name = "无名"
        self.state.stats["player_name"] = name
        self.state.flags["has_named"] = True

    def check_option_visible(self, option: Dict[str, Any]) -> str:
        excludes = option.get("exclude", {})
        for flag_key, expected_bool in excludes.get("flags", {}).items():
            if self.state.flags.get(flag_key, False) == expected_bool:
                return "excluded"

        reqs = option.get("require", {})
        if not reqs:
            return "visible"

        for stat_key, required_val in reqs.get("stats", {}).items():
            if self.state.stats.get(stat_key, 0) < required_val:
                return "hidden"

        for flag_key, expected_bool in reqs.get("flags", {}).items():
            if self.state.flags.get(flag_key, False) != expected_bool:
                return "hidden"

        item_reqs = reqs.get("items", {})
        if item_reqs:
            has_id = item_reqs.get("has")
            if has_id and not self.inv_mgr.has(has_id):
                return "hidden"

        return "visible"

    def resolve_room_description(self, room_data: Dict[str, Any]) -> str:
        alts = room_data.get("description_alt", [])
        for alt in alts:
            cond = alt.get("if", {})
            match = True
            for fk, fv in cond.get("flags", {}).items():
                if self.state.flags.get(fk, False) != fv:
                    match = False
                    break
            for sk, sv in cond.get("stats", {}).items():
                if self.state.stats.get(sk, 0) < sv:
                    match = False
                    break
            if match:
                return alt.get("text", room_data.get("description", ""))
        return room_data.get("description", "")

    def select_option(self, option: Dict[str, Any]) -> Dict[str, Any]:
        effects = option.get("effects", {})

        MAX_STAT = 99
        NATURAL_CAPPED = {"hp", "san"}

        if effects:
            for stat_key in DIRECT_STATS:
                if stat_key in effects:
                    delta = effects[stat_key]
                    if stat_key in self.state.stats:
                        if stat_key in NATURAL_CAPPED:
                            self.state.stats[stat_key] = max(0, self.state.stats[stat_key] + delta)
                        else:
                            self.state.stats[stat_key] = max(0, min(MAX_STAT, self.state.stats[stat_key] + delta))

            if "hp" in self.state.stats and "max_hp" in self.state.stats:
                self.state.stats["hp"] = min(self.state.stats["hp"], self.state.stats["max_hp"])
            if "san" in self.state.stats:
                self.state.stats["san"] = min(self.state.stats["san"], 100)

            for stat_key, delta in effects.get("stats", {}).items():
                if stat_key in self.state.stats:
                    if stat_key in NATURAL_CAPPED:
                        self.state.stats[stat_key] = max(0, self.state.stats[stat_key] + delta)
                    else:
                        self.state.stats[stat_key] = max(0, min(MAX_STAT, self.state.stats[stat_key] + delta))

            for flag_key, new_val in effects.get("flags", {}).items():
                self.state.flags[flag_key] = new_val

            for item in effects.get("items", {}).get("add", []):
                if isinstance(item, str):
                    self.inv_mgr.add_by_id(item)
                else:
                    self.inv_mgr.add(
                        item.get("id", ""),
                        item.get("name", ""),
                        item.get("desc", ""),
                        item.get("type", "misc"),
                        item.get("qty", 1),
                    )

            for item_id in effects.get("items", {}).get("remove", []):
                self.inv_mgr.remove(item_id)

            for task in effects.get("tasks", {}).get("add", []):
                existing = self.state.diary["tasks"]
                task_id = task.get("id", f"task_{len(existing)}")
                if not any(t.get("id") == task_id for t in existing):
                    existing.append({
                        "id": task_id,
                        "title": task.get("title", "未命名任务"),
                        "content": task.get("content", ""),
                        "done": False,
                    })
                    self.state.flags["diary_unread"] = True

            for task_id in effects.get("tasks", {}).get("complete", []):
                for t in self.state.diary["tasks"]:
                    if t.get("id") == task_id:
                        t["done"] = True
                        self.state.flags["diary_unread"] = True
                        break

        next_room = option.get("target_room")
        next_dialogue = option.get("target_dialogue")

        if next_dialogue:
            self.state.dialogue_id = next_dialogue
        elif next_room:
            self.state.room_id = next_room
            self.state.dialogue_id = ""

        return {
            "success": True,
            "next_room": self.state.room_id,
            "next_dialogue": self.state.dialogue_id,
            "effects_applied": effects,
        }