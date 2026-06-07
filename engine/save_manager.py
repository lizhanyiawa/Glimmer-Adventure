import os
import json
import datetime
from typing import Dict, Any, List
from engine.paths import save_path


class SaveManager:
    REQUIRED_KEYS = ["room_id", "stats", "inventory", "flags"]
    MAX_SLOTS = 9

    def __init__(self, saves_dir: str = "saves"):
        self.saves_dir = saves_dir
        self._ensure_dir()

    def _ensure_dir(self):
        saves_dir = os.path.dirname(save_path(""))
        if not os.path.exists(saves_dir):
            os.makedirs(saves_dir)

    def _path(self, slot: int) -> str:
        return save_path(f"slot_{slot}.json")

    def _valid_slot(self, slot: int) -> bool:
        return isinstance(slot, int) and 1 <= slot <= self.MAX_SLOTS

    def state_to_dict(self, state) -> Dict[str, Any]:
        return {
            "room_id": state.room_id,
            "dialogue_id": state.dialogue_id,
            "play_time": state.play_time,
            "last_saved": state.last_saved,
            "stats": dict(state.stats),
            "inventory": list(state.inventory),
            "diary": {
                "tasks": list(state.diary.get("tasks", [])),
                "notes": list(state.diary.get("notes", [])),
            },
            "flags": dict(state.flags),
        }

    def state_from_dict(self, state, data: Dict[str, Any]):
        if not isinstance(data, dict):
            return

        state.room_id = str(data.get("room_id", "thatched_hut_bed"))
        state.dialogue_id = str(data.get("dialogue_id", ""))

        pt = data.get("play_time")
        state.play_time = float(pt) if pt is not None else 0.0

        state.last_saved = str(data.get("last_saved", ""))

        saved_stats = data.get("stats", {})
        if isinstance(saved_stats, dict):
            for key in state.stats:
                if key in saved_stats:
                    try:
                        state.stats[key] = type(state.stats[key])(saved_stats[key])
                    except (ValueError, TypeError):
                        pass
            for key in saved_stats:
                if key not in state.stats:
                    state.stats[key] = saved_stats[key]

        saved_inv = data.get("inventory", [])
        if isinstance(saved_inv, list):
            clean = [item for item in saved_inv if isinstance(item, dict) and "id" in item and "name" in item]
            if clean:
                state.inventory = clean

        saved_flags = data.get("flags", {})
        if isinstance(saved_flags, dict):
            for key in state.flags:
                if key in saved_flags:
                    state.flags[key] = bool(saved_flags[key])
            for key in saved_flags:
                if key not in state.flags:
                    state.flags[key] = bool(saved_flags[key])

        saved_diary = data.get("diary", {})
        if isinstance(saved_diary, dict):
            tasks = saved_diary.get("tasks", [])
            state.diary["tasks"] = tasks if isinstance(tasks, list) else []
            notes = saved_diary.get("notes", [])
            state.diary["notes"] = notes if isinstance(notes, list) else []

        state.flags["diary_unread"] = False

    def save(self, state, slot: int) -> bool:
        if not self._valid_slot(slot):
            return False
        self._ensure_dir()
        state.last_saved = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        try:
            with open(self._path(slot), "w", encoding="utf-8") as f:
                json.dump(self.state_to_dict(state), f, ensure_ascii=False, indent=4)
            return True
        except Exception as e:
            print(f"Save failed: {e}")
            return False

    def load(self, state, slot: int) -> bool:
        if not self._valid_slot(slot):
            return False
        file_path = self._path(slot)
        if not os.path.exists(file_path):
            return False
        if not self.validate(slot):
            return False
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            self.state_from_dict(state, data)
            return True
        except Exception as e:
            print(f"[ERROR] 加载存档 {slot} 失败: {e}")
            return False

    def validate(self, slot: int) -> bool:
        if not self._valid_slot(slot):
            return False
        file_path = self._path(slot)
        if not os.path.exists(file_path):
            return False
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if not isinstance(data, dict):
                return False
            for key in self.REQUIRED_KEYS:
                if key not in data:
                    return False
            if not isinstance(data.get("stats"), dict):
                return False
            if not isinstance(data.get("inventory"), list):
                return False
            if not isinstance(data.get("flags"), dict):
                return False
            # 类型+范围校验
            for stat_key, val in data.get("stats", {}).items():
                if not isinstance(val, (int, float)):
                    return False
                if stat_key == "hp" and not (0 <= val <= 9999):
                    return False
                if stat_key == "san" and not (0 <= val <= 200):
                    return False
                if stat_key == "corruption" and not (0 <= val <= 100):
                    return False
                if not (0 <= val <= 999):
                    return False
            return True
        except Exception:
            return False

    def delete(self, slot: int) -> bool:
        if not self._valid_slot(slot):
            return False
        file_path = self._path(slot)
        try:
            if os.path.exists(file_path):
                os.remove(file_path)
                return True
        except Exception as e:
            print(f"[ERROR] 删除存档 {slot} 失败: {e}")
        return False

    def get_slots(self) -> List[Dict[str, Any]]:
        self._ensure_dir()
        slots = []
        for i in range(1, 6):
            file_path = self._path(i)
            if os.path.exists(file_path):
                if self.validate(i):
                    try:
                        with open(file_path, "r", encoding="utf-8") as f:
                            data = json.load(f)
                        slots.append({
                            "slot": i,
                            "exists": True,
                            "room_id": data.get("room_id", "?"),
                            "last_saved": data.get("last_saved", "?"),
                            "player_name": data.get("stats", {}).get("player_name", "无名"),
                            "level": data.get("stats", {}).get("attack", 1),
                        })
                    except Exception:
                        slots.append({"slot": i, "exists": False, "corrupted": True})
                else:
                    slots.append({"slot": i, "exists": False, "corrupted": True})
            else:
                slots.append({"slot": i, "exists": False})
        return slots