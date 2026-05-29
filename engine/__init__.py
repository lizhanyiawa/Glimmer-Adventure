import os
import json
import datetime
from typing import Dict, Any, List, Optional

class GameState:
    """玩家状态与世界线标记寄存器 (FSM State)"""
    def __init__(self):
        # 1. 基础属性
        self.room_id: str = "start_classroom"  # 当前所在的房间/剧本ID
        self.play_time: float = 0.0            # 游玩时间
        self.last_saved: str = ""              # 上次保存时间
        
        # 2. 玩家底层数值 (三大体系与理智度)
        self.stats: Dict[str, Any] = {
            "energy_level": 1,      # 生命阶位 (1-10)
            "logic_mind": 99,       # 现代逻辑思维
            "magic_power": 0,       # 传统魔法能级
            "martial_qi": 0,        # 斗气气血强度
            "tech_level": 5,        # 科技解构能力
            "hp": 100,              # 精气神上限
            "max_hp": 100,
            "san": 100,             # 理智值 (SAN)
            "corruption": 0         # 灵魂污染度/黄油侵蚀度 (0-100)
        }
        
        # 3. 随身物品
        self.inventory: List[Dict[str, Any]] = [
            {"id": "electric_license", "name": "低压电工证", "desc": "盖有异界审查局钢印的神秘证书。", "qty": 1},
            {"id": "electric_pen", "name": "测电笔", "desc": "能感应微弱的能量流动（或电流）。", "qty": 1}
        ]
        
        # 4. 因果与剧情标记 (Story Flags)
        self.flags: Dict[str, bool] = {
            "met_alice": False,
            "classroom_power_cut": False,
            "corridor_guarded": True
        }

    def to_dict(self) -> Dict[str, Any]:
        """序列化为字典"""
        return {
            "room_id": self.room_id,
            "play_time": self.play_time,
            "last_saved": self.last_saved,
            "stats": self.stats,
            "inventory": self.inventory,
            "flags": self.flags
        }

    def load_dict(self, data: Dict[str, Any]):
        """从字典反序列化"""
        self.room_id = data.get("room_id", "start_classroom")
        self.play_time = data.get("play_time", 0.0)
        self.last_saved = data.get("last_saved", "")
        self.stats = data.get("stats", self.stats)
        self.inventory = data.get("inventory", self.inventory)
        self.flags = data.get("flags", self.flags)


class GameEngine:
    """MUD 核心逻辑驱动器 (Core Controller)"""
    def __init__(self):
        self.state: GameState = GameState()
        self.saves_dir: str = "saves"
        self.config_file: str = "engine_config.json"
        
        # 默认引擎系统设置
        self.settings: Dict[str, Any] = {
            "debug_mode": False,           # 真理视界 (显示选项背后的逻辑判定)
            "text_speed": "normal",        # 文本渲染速度
            "corruption_rate": 1.0,        # 黄油侵蚀倍率
            "sound_enabled": False         # 音频输出开关
        }
        
        self.ensure_saves_dir()
        self.load_settings()

    def ensure_saves_dir(self):
        """确保存档目录存在"""
        if not os.path.exists(self.saves_dir):
            os.makedirs(self.saves_dir)

    # ==========================================
    # 💾 存档与读档管理接口 (Save/Load Subsystem)
    # ==========================================
    def get_save_slots(self) -> List[Dict[str, Any]]:
        """扫描存档目录，返回所有可用存档槽位的信息"""
        self.ensure_saves_dir()
        slots = []
        for i in range(1, 6):  # 支持 5 个标准存档位
            file_path = os.path.join(self.saves_dir, f"slot_{i}.json")
            if os.path.exists(file_path):
                try:
                    with open(file_path, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    slots.append({
                        "slot": i,
                        "exists": True,
                        "room_id": data.get("room_id", "未知区域"),
                        "last_saved": data.get("last_saved", "未知时间"),
                        "level": data.get("stats", {}).get("energy_level", 1)
                    })
                except Exception:
                    slots.append({"slot": i, "exists": False, "corrupted": True})
            else:
                slots.append({"slot": i, "exists": False})
        return slots

    def save_game(self, slot: int) -> bool:
        """保存当前游戏世界线到指定槽位"""
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

    def load_game(self, slot: int) -> bool:
        """从指定槽位恢复游戏世界线"""
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

    # ==========================================
    # ⚙️ 配置读取与持久化
    # ==========================================
    def load_settings(self):
        """读取系统设置"""
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, "r", encoding="utf-8") as f:
                    self.settings.update(json.load(f))
            except Exception:
                pass

    def save_settings(self):
        """保存系统设置"""
        try:
            with open(self.config_file, "w", encoding="utf-8") as f:
                json.dump(self.settings, f, ensure_ascii=False, indent=4)
        except Exception:
            pass

    # ==========================================
    # 判定与逻辑跳转中心 (Rules/Checks Engine)
    # ==========================================
    def check_option_visible(self, option: Dict[str, Any]) -> bool:
        """判定一个剧情选项是否应该显示给玩家"""
        # 如果选项中没有设定限制，默认可见
        reqs = option.get("require", {})
        if not reqs:
            return True
            
        # 逐一检查属性阈值
        for stat_key, required_val in reqs.get("stats", {}).items():
            if self.state.stats.get(stat_key, 0) < required_val:
                return False
                
        # 检查特定的世界线剧情 Flag
        for flag_key, expected_bool in reqs.get("flags", {}).items():
            if self.state.flags.get(flag_key, False) != expected_bool:
                return False
                
        return True

    def select_option(self, option: Dict[str, Any]) -> Dict[str, Any]:
        """玩家选择某个选项后的状态结算器"""
        # 1. 触发效果 (数值加减、Flag 改变、背包变动)
        effects = option.get("effects", {})
        if effects:
            # 修改数值
            for stat_key, delta in effects.get("stats", {}).items():
                if stat_key in self.state.stats:
                    self.state.stats[stat_key] = max(0, self.state.stats[stat_key] + delta)
            
            # 修改世界线 Flags
            for flag_key, new_val in effects.get("flags", {}).items():
                self.state.flags[flag_key] = new_val

        # 2. 推进房间跳转指针
        next_room = option.get("target_room", self.state.room_id)
        self.state.room_id = next_room
        
        # 返回结算上下文，方便前端进行事件广播（如展示伤害数值等）
        return {
            "success": True,
            "next_room": next_room,
            "effects_applied": effects
        }