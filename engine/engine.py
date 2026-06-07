import os
import json
import datetime
import logging
from typing import Dict, Any, List
from engine.inventory import InventoryManager
from engine.save_manager import SaveManager
from engine.paths import data_path, config_path

logger = logging.getLogger("engine")

# ==========================================
# Flag 命名空间系统
# ==========================================
# 所有 flag 必须遵循 [前缀]_[子域]_[具体含义] 格式。
# 前缀决定作用域，防止 flag 数量膨胀后出现命名冲突。
FLAG_PREFIXES: Dict[str, str] = {
    "loc_":    "地点状态（房间解锁/探索/交互状态）",
    "battle_": "战斗相关（击败/逃跑/首次遭遇）",
    "npc_":    "NPC 相关（见面/对话进度）",
    "item_":   "物品相关（获取/使用/消耗标记）",
    "story_":  "主线剧情推进阶段",
    "q_":      "支线任务状态",
    "sys_":    "系统/教程/UI 状态",
    "char_":   "主角名义状态（不存 stats 的临时标记）",
    "san_":    "理智相关的触发/阈值标记",
}

# 硬编码旧版 flag -> 新版 flag 映射（可逐步迁移）
FLAG_RENAME_MAP: Dict[str, str] = {}

# 旧版 flag 白名单：已存在但未带前缀的 flag（临时兼容，未来重构时统一）
_LEGACY_FLAG_WHITELIST: set = set()


def validate_flag_name(flag_name: str) -> bool:
    """校验 flag 名称是否遵循命名空间规范。
    返回 True 表示合法，False 表示需要警告。
    """
    if flag_name in _LEGACY_FLAG_WHITELIST:
        return True
    for prefix in FLAG_PREFIXES:
        if flag_name.startswith(prefix) and len(flag_name) > len(prefix):
            return True
    return False


def _warn_flag(flag_name: str):
    """记录未命名空间的 flag 警告"""
    logger.warning(
        "Flag '%s' 未使用前缀命名空间。请使用以下前缀之一: %s",
        flag_name,
        list(FLAG_PREFIXES.keys()),
    )


DIRECT_STATS = ["hp", "max_hp", "san", "corruption", "attack", "defense", "intelligence", "agility"]


class GameState:
    """玩家状态容器。

    flags 字段存储所有布尔标记。新 flag 务必遵循命名空间规范：
    loc_ / battle_ / npc_ / item_ / story_ / q_ / sys_ / char_ / san_
    """
    def __init__(self):
        self.room_id: str = "thatched_hut_bed"
        self.dialogue_id: str = ""
        self.play_time: float = 0.0
        self.last_saved: str = ""

        self.stats: Dict[str, Any] = {
            "attack": 5,
            "defense": 5,
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

        self.flags: Dict[str, bool] = {}


class GameEngine:
    def __init__(self):
        self._items_db: Dict[str, Any] = {}
        self._rooms_db: Dict[str, Any] = {}
        self._dialogues_db: Dict[str, Any] = {}

        self._load_items_db()
        self._load_rooms_db()
        self._load_dialogues_db()
        self._init_flag_whitelist()

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

    def reset_game(self):
        self.state = GameState()
        self.inv_mgr = InventoryManager(self.state, self._items_db)
        self._init_default_inventory()

    def _load_items_db(self):
        try:
            with open(data_path("items.json"), "r", encoding="utf-8") as f:
                self._items_db = json.load(f)
        except Exception as e:
            print(f"[ERROR] 加载 items.json 失败: {e}")
            self._items_db = {}
        # merge text
        try:
            with open(data_path("items_text.json"), "r", encoding="utf-8") as f:
                texts = json.load(f)
            for item_id, text_data in texts.items():
                if item_id in self._items_db:
                    self._items_db[item_id]["desc"] = text_data.get("desc", "")
        except Exception as e:
            print(f"[WARN] 加载 items_text.json 失败: {e}")

    def _load_rooms_db(self):
        rooms_dir = data_path("rooms")
        rooms_text_dir = data_path("rooms_text")
        self._rooms_db = {}
        # load logic
        if os.path.isdir(rooms_dir):
            for filename in sorted(os.listdir(rooms_dir)):
                if filename.endswith(".json"):
                    filepath = os.path.join(rooms_dir, filename)
                    try:
                        with open(filepath, "r", encoding="utf-8") as f:
                            self._rooms_db.update(json.load(f))
                    except Exception as e:
                        print(f"[ERROR] 加载 {filename} 失败: {e}")
        # merge text
        if os.path.isdir(rooms_text_dir):
            for filename in sorted(os.listdir(rooms_text_dir)):
                if filename.endswith(".json"):
                    filepath = os.path.join(rooms_text_dir, filename)
                    try:
                        with open(filepath, "r", encoding="utf-8") as f:
                            texts = json.load(f)
                        for room_id, text_data in texts.items():
                            if room_id in self._rooms_db:
                                room = self._rooms_db[room_id]
                                room["title"] = text_data.get("title", room.get("title", ""))
                                room["description"] = text_data.get("description", room.get("description", ""))
                                alt_texts = text_data.get("description_alt", [])
                                alts = room.get("description_alt", [])
                                for i, alt_text in enumerate(alt_texts):
                                    if i < len(alts):
                                        alts[i]["text"] = alt_text
                    except Exception as e:
                        print(f"[ERROR] 加载 rooms_text/{filename} 失败: {e}")
        if not self._rooms_db:
            print("[ERROR] 未能加载任何房间数据")

    def _load_dialogues_db(self):
        try:
            with open(data_path("dialogues.json"), "r", encoding="utf-8") as f:
                self._dialogues_db = json.load(f)
        except Exception as e:
            print(f"[ERROR] 加载 dialogues.json 失败: {e}")
            self._dialogues_db = {}
        # merge text
        try:
            with open(data_path("dialogues_text.json"), "r", encoding="utf-8") as f:
                texts = json.load(f)
            for dlg_id, text_data in texts.items():
                if dlg_id in self._dialogues_db:
                    self._dialogues_db[dlg_id]["text"] = text_data.get("text", "")
        except Exception as e:
            print(f"[WARN] 加载 dialogues_text.json 失败: {e}")

    def _init_default_inventory(self):
        for item_id in ["ballpoint_pen"]:
            self.inv_mgr.add_by_id(item_id)

    def _init_flag_whitelist(self):
        """扫描所有已加载数据，将已有的旧版 flag 加入白名单。

        白名单中的 flag 在运行时不会触发命名空间警告。
        新增 flag 时应使用带前缀的命名规范。
        """
        whitelist: set = set()

        def _collect_flags(data: dict):
            if not isinstance(data, dict):
                return
            for value in data.values():
                if isinstance(value, dict):
                    for key, flag_val in value.get("flags", {}).items():
                        if isinstance(key, str) and key:
                            whitelist.add(key)
                    _collect_flags(value)
                elif isinstance(value, list):
                    for item in value:
                        if isinstance(item, dict):
                            for key, flag_val in item.get("flags", {}).items():
                                if isinstance(key, str) and key:
                                    whitelist.add(key)
                            _collect_flags(item)

        _collect_flags(self._rooms_db)
        _collect_flags(self._dialogues_db)
        # items_db 不使用 flags，但为了完整性也扫描
        _collect_flags(self._items_db)

        # 更新模块级白名单
        global _LEGACY_FLAG_WHITELIST
        _LEGACY_FLAG_WHITELIST = whitelist

        # 检查是否有未命名空间的旧版 flag
        unflagged = {f for f in whitelist if not any(f.startswith(p) for p in FLAG_PREFIXES)}
        if unflagged:
            logger.info(
                "Legacy flags detected (no namespace prefix, whitelisted for compatibility): %s",
                sorted(unflagged),
            )

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
        self.set_flag("sys_has_named", True)

    # ── Flag 访问器（view 层请通过这组方法操作 flags，不要直接访问 state.flags）──
    def get_flag(self, key: str, default: Any = False) -> Any:
        """安全读取 flag。返回 default 如果不存在。"""
        return self.state.flags.get(key, default)

    def set_flag(self, key: str, value: Any):
        """安全写入 flag。若 flag 名不合规范且不在白名单中，会记录警告。"""
        if not validate_flag_name(key):
            _warn_flag(key)
        self.state.flags[key] = value

    def delete_flag(self, key: str):
        """删除 flag（用于清理不需要持久化的临时标记）。"""
        self.state.flags.pop(key, None)

    # ── 选项可见性 ──
    def check_option_visible(self, option: Dict[str, Any]) -> str:
        """检测选项的可见状态。

        exclude 逻辑说明：
        - exclude.flags 使用 OR 逻辑：只要任意一个 flag 条件匹配，整个选项就被排除隐藏。
          例如 exclude.flags = {a: True, b: True} 意味着 a=true OR b=true 时排除。
          如果需要"a 和 b 同时为 true 才排除"，应将它们拆成两个独立选项，
          或在数据中只写一个复合 flag（如 flag_combined）。
        - require.flags 使用 AND 逻辑：所有条件必须同时满足才显示选项。

        返回值: "visible" / "hidden"（灰字显示） / "excluded"（完全不显示）
        """
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

    def apply_effects(self, effects: Dict[str, Any]):
        """应用效果（flag、属性、物品、任务），不处理房间跳转"""
        if not effects:
            return

        MAX_STAT = 99
        NATURAL_CAPPED = {"hp", "san"}

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
            self.set_flag(flag_key, new_val)

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
                self.set_flag("sys_diary_unread", True)

        for task_id in effects.get("tasks", {}).get("complete", []):
            for t in self.state.diary["tasks"]:
                if t.get("id") == task_id:
                    t["done"] = True
                    self.set_flag("sys_diary_unread", True)
                    break

        for note in effects.get("notes", {}).get("add", []):
            existing = self.state.diary["notes"]
            note_id = note.get("id", f"note_{len(existing)}")
            if not any(n.get("id") == note_id for n in existing):
                existing.append({
                    "id": note_id,
                    "title": note.get("title", "未命名笔记"),
                    "content": note.get("content", ""),
                    "created": note.get("created", datetime.datetime.now().strftime("%Y-%m-%d %H:%M")),
                })
                self.set_flag("sys_diary_unread", True)

    def select_option(self, option: Dict[str, Any]) -> Dict[str, Any]:
        effects = option.get("effects", {})
        self.apply_effects(effects)

        next_room = option.get("target_room")
        next_dialogue = option.get("target_dialogue")

        if next_dialogue:
            self.state.dialogue_id = next_dialogue
        elif next_room:
            self.state.room_id = next_room
            # enter_dialogue: 进入房间后自动触发的对话
            room_def = self._rooms_db.get(next_room, {})
            enter_dlg = room_def.get("enter_dialogue", "")
            self.state.dialogue_id = enter_dlg

        return {
            "success": True,
            "next_room": self.state.room_id,
            "next_dialogue": self.state.dialogue_id,
            "effects_applied": effects,
        }