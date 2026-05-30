import os
import json
import datetime
from typing import Dict, Any, List

# 玩家状态管理
class GameState:
    def __init__(self):
        self.room_id: str = "start_classroom"  # 当前房间ID
        self.play_time: float = 0.0            # 游玩时间
        self.last_saved: str = ""              # 上次保存时间

        # 属性
        self.stats: Dict[str, Any] = {
            "energy_level": 1,
            "logic_mind": 99,
            "magic_power": 0,
            "martial_qi": 0,
            "tech_level": 5,
            "hp": 100,
            "max_hp": 100,
            "san": 100,
            "corruption": 0
        }

        # 物品栏
        self.inventory: List[Dict[str, Any]] = [
            {"id": "electric_license", "name": "低压电工证", "desc": "证书。", "qty": 1},
            {"id": "electric_pen", "name": "测电笔", "desc": "能感应能量流动。", "qty": 1}
        ]

        # 剧情标记
        self.flags: Dict[str, bool] = {
            "met_alice": False,
            "classroom_power_cut": False,
            "corridor_guarded": True
        }

    def to_dict(self) -> Dict[str, Any]:
        return {
            "room_id": self.room_id,
            "play_time": self.play_time,
            "last_saved": self.last_saved,
            "stats": self.stats,
            "inventory": self.inventory,
            "flags": self.flags
        }

    def load_dict(self, data: Dict[str, Any]):
        self.room_id = data.get("room_id", "start_classroom")
        self.play_time = data.get("play_time", 0.0)
        self.last_saved = data.get("last_saved", "")
        self.stats = data.get("stats", self.stats)
        self.inventory = data.get("inventory", self.inventory)
        self.flags = data.get("flags", self.flags)


# 游戏核心逻辑
class GameEngine:
    def __init__(self):
        self.state: GameState = GameState()
        self.saves_dir: str = "saves"
        self.config_file: str = "engine_config.json"

        # 游戏设置
        self.settings: Dict[str, Any] = {
            "debug_mode": False,
            "text_speed": "normal",
            "corruption_rate": 1.0,
            "sound_enabled": False
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
                try:
                    with open(file_path, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    slots.append({
                        "slot": i,
                        "exists": True,
                        "room_id": data.get("room_id", "?"),
                        "last_saved": data.get("last_saved", "?"),
                        "level": data.get("stats", {}).get("energy_level", 1)
                    })
                except Exception:
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
    def load_game(self, slot: int) -> bool:
        file_path = os.path.join(self.saves_dir, f"slot_{slot}.json")
        if not os.path.exists(file_path):
            return False
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            self.state.load_dict(data)
            return True
        except Exception as e:
            print(f"Load failed: {e}")
            return False

    # 加载设置
    def load_settings(self):
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, "r", encoding="utf-8") as f:
                    self.settings.update(json.load(f))
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

        for stat_key, required_val in reqs.get("stats", {}).items():
            if self.state.stats.get(stat_key, 0) < required_val:
                return False

        for flag_key, expected_bool in reqs.get("flags", {}).items():
            if self.state.flags.get(flag_key, False) != expected_bool:
                return False

        return True

    # 执行选项选择，应用效果并切换房间
    def select_option(self, option: Dict[str, Any]) -> Dict[str, Any]:
        effects = option.get("effects", {})
        if effects:
            # 应用属性变化
            for stat_key, delta in effects.get("stats", {}).items():
                if stat_key in self.state.stats:
                    self.state.stats[stat_key] = max(0, self.state.stats[stat_key] + delta)

            # 应用标记变化
            for flag_key, new_val in effects.get("flags", {}).items():
                self.state.flags[flag_key] = new_val

        # 切换房间
        next_room = option.get("target_room", self.state.room_id)
        self.state.room_id = next_room

        return {
            "success": True,
            "next_room": next_room,
            "effects_applied": effects
        }
