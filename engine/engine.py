import os
import json
import datetime
from typing import Dict, Any, List
from engine.inventory import InventoryManager

# 玩家状态管理
class GameState:
    def __init__(self):
        self.room_id: str = "thatched_hut_bed"  # 当前房间ID
        self.dialogue_id: str = ""             # 当前对话ID（如果有）
        self.play_time: float = 0.0            # 游玩时间
        self.last_saved: str = ""              # 上次保存时间

        # 属性
        self.stats: Dict[str, Any] = {
            "attack": 5,
            "defense": 3,
            "intelligence": 5,
            "agility": 5,
            "hp": 100,
            "max_hp": 100,
            "san": 100,
            "corruption": 0
        }

        self.inventory: List[Dict[str, Any]] = [
            {"id": "ballpoint_pen", "name": "圆珠笔", "desc": "一支普通的圆珠笔，不知为何和你一起穿越了。", "type": "misc", "qty": 1}
        ]

        self.diary: Dict[str, Any] = {
            "tasks": [],
            "notes": []
        }

        self.flags: Dict[str, bool] = {
            "met_alice": False,
            "classroom_power_cut": False,
            "corridor_guarded": True
        }

    def to_dict(self) -> Dict[str, Any]:
        return {
            "room_id": self.room_id,
            "dialogue_id": self.dialogue_id,
            "play_time": self.play_time,
            "last_saved": self.last_saved,
            "stats": self.stats,
            "inventory": self.inventory,
            "diary": self.diary,
            "flags": self.flags
        }

    def load_dict(self, data: Dict[str, Any]):
        if not isinstance(data, dict):
            return

        self.room_id = str(data.get("room_id", "thatched_hut_bed"))
        self.dialogue_id = str(data.get("dialogue_id", ""))

        pt = data.get("play_time")
        self.play_time = float(pt) if pt is not None else 0.0

        self.last_saved = str(data.get("last_saved", ""))

        saved_stats = data.get("stats", {})
        if isinstance(saved_stats, dict):
            for key in self.stats:
                if key in saved_stats:
                    try:
                        self.stats[key] = type(self.stats[key])(saved_stats[key])
                    except (ValueError, TypeError):
                        pass
            for key in saved_stats:
                if key not in self.stats:
                    self.stats[key] = saved_stats[key]

        saved_inv = data.get("inventory", [])
        if isinstance(saved_inv, list):
            clean = []
            for item in saved_inv:
                if isinstance(item, dict) and "id" in item and "name" in item:
                    clean.append(item)
            self.inventory = clean if clean else self.inventory

        saved_flags = data.get("flags", {})
        if isinstance(saved_flags, dict):
            for key in self.flags:
                if key in saved_flags:
                    self.flags[key] = bool(saved_flags[key])
            for key in saved_flags:
                if key not in self.flags:
                    self.flags[key] = bool(saved_flags[key])

        saved_diary = data.get("diary", {})
        if isinstance(saved_diary, dict):
            tasks = saved_diary.get("tasks", [])
            self.diary["tasks"] = tasks if isinstance(tasks, list) else []
            notes = saved_diary.get("notes", [])
            self.diary["notes"] = notes if isinstance(notes, list) else []


# 游戏核心逻辑
class GameEngine:
    def __init__(self):
        self.state: GameState = GameState()
        self.saves_dir: str = "saves"
        self.config_file: str = "engine_config.json"

        # 游戏设置
        self.settings: Dict[str, Any] = {
            "debug_mode": False,
            "text_speed": "medium",
            "corruption_rate": 1.0,
            "sound_enabled": False,
            "skip_intro": False,
            "confirm_return": True,
            "confirm_exit": True,
            "confirm_save": True
        }

        self.ensure_saves_dir()
        self.load_settings()

    # 确保存档目录存在
    def ensure_saves_dir(self):
        if not os.path.exists(self.saves_dir):
            os.makedirs(self.saves_dir)

    # 获取所有存档槽位信息
    def get_save_slots(self) -> List[Dict[str, Any]]:
        self.ensure_saves_dir()
        slots = []
        for i in range(1, 6):
            file_path = os.path.join(self.saves_dir, f"slot_{i}.json")
            if os.path.exists(file_path):
                if self.validate_save(i):
                    try:
                        with open(file_path, "r", encoding="utf-8") as f:
                            data = json.load(f)
                        slots.append({
                            "slot": i,
                            "exists": True,
                            "room_id": data.get("room_id", "?"),
                            "last_saved": data.get("last_saved", "?"),
                            "level": data.get("stats", {}).get("attack", 1)
                        })
                    except Exception:
                        slots.append({"slot": i, "exists": False, "corrupted": True})
                else:
                    slots.append({"slot": i, "exists": False, "corrupted": True})
            else:
                slots.append({"slot": i, "exists": False})
        return slots

    # 保存游戏到指定槽位
    def save_game(self, slot: int) -> bool:
        self.ensure_saves_dir()
        file_path = os.path.join(self.saves_dir, f"slot_{slot}.json")
        try:
            self.state.last_saved = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            with open(file_path, "w", encoding="utf-8") as f:
                json.dump(self.state.to_dict(), f, ensure_ascii=False, indent=4)
            return True
        except Exception as e:
            print(f"Save failed: {e}")
            return False

    # 从指定槽位加载游戏
    def validate_save(self, slot: int) -> bool:
        file_path = os.path.join(self.saves_dir, f"slot_{slot}.json")
        if not os.path.exists(file_path):
            return False
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if not isinstance(data, dict):
                return False
            required = ["room_id", "stats", "inventory", "flags"]
            for key in required:
                if key not in data:
                    return False
            if not isinstance(data.get("stats"), dict):
                return False
            if not isinstance(data.get("inventory"), list):
                return False
            if not isinstance(data.get("flags"), dict):
                return False
            return True
        except Exception:
            return False

    def load_game(self, slot: int) -> bool:
        file_path = os.path.join(self.saves_dir, f"slot_{slot}.json")
        if not os.path.exists(file_path):
            return False
        if not self.validate_save(slot):
            return False
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            self.state.load_dict(data)
            return True
        except Exception:
            return False

    # 加载设置
    def load_settings(self):
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, "r", encoding="utf-8") as f:
                    saved = json.load(f)
                self.settings.update(saved)
                if self.settings.get("text_speed") not in ("instant", "fast", "medium", "slow"):
                    self.settings["text_speed"] = "medium"
            except Exception:
                pass

    # 保存设置
    def save_settings(self):
        try:
            with open(self.config_file, "w", encoding="utf-8") as f:
                json.dump(self.settings, f, ensure_ascii=False, indent=4)
        except Exception:
            pass

    # 删除存档
    def delete_save(self, slot_id: int) -> bool:
        filepath = f"saves/slot_{slot_id}.json"
        try:
            if os.path.exists(filepath):
                os.remove(filepath)
                return True
        except Exception:
            pass
        return False

    # 设置玩家名字
    def set_player_name(self, name: str):
        if not name.strip():
            name = "无名"
        self.state.stats["player_name"] = name
        self.state.flags["has_named"] = True

    # 检查选项是否可见（属性/标记是否满足条件）
    def check_option_visible(self, option: Dict[str, Any]) -> bool:
        reqs = option.get("require", {})
        if not reqs:
            return True

        # 如果选项有 exclude 字段，当满足 exclude 中的任意条件时，选项隐藏
        excludes = option.get("exclude", {})
        for flag_key, expected_bool in excludes.get("flags", {}).items():
            if self.state.flags.get(flag_key, False) == expected_bool:
                return False

        for stat_key, required_val in reqs.get("stats", {}).items():
            if self.state.stats.get(stat_key, 0) < required_val:
                return False

        for flag_key, expected_bool in reqs.get("flags", {}).items():
            if self.state.flags.get(flag_key, False) != expected_bool:
                return False

        # 检查物品要求
        item_reqs = reqs.get("items", {})
        if item_reqs:
            inv_mgr = InventoryManager(self.state)
            # has: 检查是否有特定ID的物品
            has_id = item_reqs.get("has")
            if has_id and not inv_mgr.has(has_id):
                return False

        return True

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

    # 执行选项选择，应用效果并切换房间/对话
    def select_option(self, option: Dict[str, Any]) -> Dict[str, Any]:
        effects = option.get("effects", {})
        inv_mgr = InventoryManager(self.state)

        if effects:
            # 兼容把 hp/san 这种直接写在 effects 根目录下的写法
            for direct_stat in ["hp", "max_hp", "san", "corruption", "attack", "defense", "intelligence", "agility"]:
                if direct_stat in effects:
                    delta = effects[direct_stat]
                    if direct_stat in self.state.stats:
                        self.state.stats[direct_stat] = max(0, self.state.stats[direct_stat] + delta)
                        
            # 如果想要不超过 max_hp
            if "hp" in self.state.stats and "max_hp" in self.state.stats:
                self.state.stats["hp"] = min(self.state.stats["hp"], self.state.stats["max_hp"])
            if "san" in self.state.stats:
                self.state.stats["san"] = min(self.state.stats["san"], 100)

            for stat_key, delta in effects.get("stats", {}).items():
                if stat_key in self.state.stats:
                    self.state.stats[stat_key] = max(0, self.state.stats[stat_key] + delta)

            for flag_key, new_val in effects.get("flags", {}).items():
                self.state.flags[flag_key] = new_val

            for item in effects.get("items", {}).get("add", []):
                inv_mgr.add(
                    item.get("id", ""),
                    item.get("name", ""),
                    item.get("desc", ""),
                    item.get("type", "misc"),
                    item.get("qty", 1)
                )

            for item_id in effects.get("items", {}).get("remove", []):
                inv_mgr.remove(item_id)

        # 切换房间或对话
        next_room = option.get("target_room")
        next_dialogue = option.get("target_dialogue")

        if next_dialogue:
            self.state.dialogue_id = next_dialogue
            # 如果进入对话，room_id 保持不变（作为背景）
        elif next_room:
            self.state.room_id = next_room
            self.state.dialogue_id = "" # 离开对话回到房间

        return {
            "success": True,
            "next_room": self.state.room_id,
            "next_dialogue": self.state.dialogue_id,
            "effects_applied": effects
        }
