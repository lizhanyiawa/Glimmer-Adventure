extends Control
## 主玩法画面（对应 Python 的 view/game_menu.py: GamePlayScreen）。
##
## 职责：把 GameEngine 的状态渲染成画面，并把玩家的点击转回引擎。
## 不包含任何游戏规则——规则全在 scripts/core/ 里。

const MODAL_SCENE := preload("res://scenes/Modal.tscn")

## 属性中文名，与 Python 版 game_menu.py 的 STATS_NAMES 一致
const STATS_NAMES: Dictionary = {
	"hp": "生命",
	"max_hp": "最大生命",
	"san": "理智",
	"corruption": "腐化",
	"attack": "攻击",
	"defense": "防御",
	"intelligence": "智力",
	"agility": "敏捷",
	"coins": "铜币",
}

@onready var _hp_label: Label = $Root/Layout/StatusBar/StatusRow/StatsLeft/HpLabel
@onready var _hp_bar: ProgressBar = $Root/Layout/StatusBar/StatusRow/StatsLeft/HpBar
@onready var _san_label: Label = $Root/Layout/StatusBar/StatusRow/StatsLeft/SanLabel
@onready var _san_bar: ProgressBar = $Root/Layout/StatusBar/StatusRow/StatsLeft/SanBar
@onready var _location_label: Label = $Root/Layout/StatusBar/StatusRow/LocationCenter/LocationLabel
@onready var _combat_label: Label = $Root/Layout/StatusBar/StatusRow/StatsRight/CombatLabel
@onready var _mind_label: Label = $Root/Layout/StatusBar/StatusRow/StatsRight/MindLabel
@onready var _corruption_label: Label = $Root/Layout/StatusBar/StatusRow/StatsRight/CorruptionLabel

@onready var _story_text: RichTextLabel = $Root/Layout/MainViewport/StoryBox/StoryText
@onready var _history_text: RichTextLabel = $Root/Layout/MainViewport/RightPanel/HistoryBox/HistoryText
@onready var _tracked_label: Label = $Root/Layout/MainViewport/RightPanel/TrackedTask/TrackedLabel

@onready var _option_grid: GridContainer = $Root/Layout/BottomConsole/OptionGrid
@onready var _btn_profile: Button = $Root/Layout/BottomConsole/SystemPanel/LeftButtons/BtnProfile
@onready var _btn_inventory: Button = $Root/Layout/BottomConsole/SystemPanel/LeftButtons/BtnInventory
@onready var _btn_save: Button = $Root/Layout/BottomConsole/SystemPanel/LeftButtons/BtnSave
@onready var _btn_settings: Button = $Root/Layout/BottomConsole/SystemPanel/LeftButtons/BtnSettings
@onready var _btn_shop: Button = $Root/Layout/BottomConsole/SystemPanel/RightButtons/BtnShop

## 当前画面上的选项（已按条件过滤、去掉了 excluded 项）
var _compacted_options: Array = []
## 6 个选项按钮，按顺序对应 _compacted_options 的下标
var _option_buttons: Array[Button] = []
## 正在显示的弹窗，非 null 时屏蔽主画面的操作
var _active_modal: GameModal = null


func _ready() -> void:
	for child in _option_grid.get_children():
		if child is Button:
			_option_buttons.append(child)
			child.pressed.connect(_on_option_pressed.bind(_option_buttons.size() - 1))

	_btn_profile.pressed.connect(_open_profile)
	# 其余系统按钮对应的弹窗尚未移植，等各自做好再接上
	_btn_inventory.disabled = true
	_btn_save.disabled = true
	_btn_settings.disabled = true
	_btn_shop.disabled = true

	GameEngine.stats_changed.connect(_refresh_status_bar)
	GameEngine.game_loaded.connect(load_current_room)

	load_current_room()


func _unhandled_key_input(event: InputEvent) -> void:
	if _active_modal != null:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var index := -1
	match event.keycode:
		KEY_1: index = 0
		KEY_2: index = 1
		KEY_3: index = 2
		KEY_4: index = 3
		KEY_5: index = 4
		KEY_6: index = 5
		KEY_P:
			accept_event()
			_open_profile()
			return
		_:
			return
	accept_event()
	_select_option(index)


## ────────────────────────── 场景渲染 ──────────────────────────

func load_current_room() -> void:
	_refresh_status_bar()
	_refresh_tracked_task()

	var room_id: String = GameEngine.state.room_id
	var dialogue_id: String = GameEngine.state.dialogue_id

	# 有对话就用对话节点，否则退回房间节点
	var node_data: Dictionary = {}
	var is_dialogue := false
	if not dialogue_id.is_empty():
		node_data = GameEngine.get_dialogue(dialogue_id)
		is_dialogue = not node_data.is_empty()
	if node_data.is_empty():
		node_data = GameEngine.get_room(room_id)
		is_dialogue = false

	if node_data.is_empty():
		_story_text.text = "[错误] 数据不存在 (Room: %s, Dialogue: %s)" % [room_id, dialogue_id]
		_set_options_pending()
		return

	if is_dialogue:
		var room_data: Dictionary = GameEngine.get_room(room_id)
		var place: String = room_data.get("title", room_id) if not room_data.is_empty() else "未知地点"
		_location_label.text = "位置：%s (对话中)" % place
	else:
		_location_label.text = "位置：%s" % node_data.get("title", room_id)

	_set_options_pending()

	var full_text := ""
	if is_dialogue:
		var speaker: String = node_data.get("speaker", "???")
		var dialogue_text: String = node_data.get("text", "")
		if speaker.is_empty():
			full_text = dialogue_text
		else:
			full_text = "【 %s 】\n\n%s" % [speaker, dialogue_text]
			_append_history("[color=#66fcf1][b]【 %s 】[/b][/color]" % speaker)
			_append_history(TextFormat.render(dialogue_text))
	else:
		var title: String = node_data.get("title", room_id)
		var story_text: String = GameEngine.resolve_room_description(node_data)
		full_text = "【 %s 】\n\n%s" % [title, story_text]
		_append_history("\n[color=#ffffff][b]【 %s 】[/b][/color]" % title)
		_append_history(TextFormat.render(story_text))

	# 本期直接显示全文；打字机逐字效果留到视觉打磨阶段接
	_story_text.text = TextFormat.render(full_text)
	_rebuild_options(node_data)


func _refresh_status_bar() -> void:
	var stats: Dictionary = GameEngine.state.stats

	var hp := int(stats.get("hp", 0))
	var max_hp := maxi(1, int(stats.get("max_hp", 100)))
	_hp_label.text = "HP: %d/%d" % [hp, max_hp]
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp

	var san := int(stats.get("san", 0))
	_san_label.text = "SAN: %d/100" % san
	_san_bar.max_value = 100
	_san_bar.value = san

	_combat_label.text = "ATK: %d   DEF: %d" % [int(stats.get("attack", 0)), int(stats.get("defense", 0))]
	_mind_label.text = "INT: %d   AGI: %d" % [int(stats.get("intelligence", 0)), int(stats.get("agility", 0))]
	_corruption_label.text = "COR: %d%%" % int(stats.get("corruption", 0))


func _refresh_tracked_task() -> void:
	var tracked_id: String = GameEngine.get_flag("sys_tracked_task_id", "")
	if tracked_id.is_empty():
		_tracked_label.text = "追踪任务：无"
		return
	for task in GameEngine.state.diary.get("tasks", []):
		if task.get("id") == tracked_id:
			var prefix := "✓ " if task.get("done", false) else ""
			_tracked_label.text = "追踪任务：%s%s" % [prefix, task.get("title", "???")]
			return
	_tracked_label.text = "追踪任务：无"


func _append_history(bbcode: String) -> void:
	_history_text.append_text(bbcode + "\n")


## ────────────────────────── 选项 ──────────────────────────

## 回到"还没读完正文"的等待态（对应原版的「聆听常识流动中…」）
func _set_options_pending() -> void:
	_compacted_options = []
	for i in range(_option_buttons.size()):
		_option_buttons[i].text = "[·] 聆听常识流动中..."
		_option_buttons[i].disabled = true


func _rebuild_options(node_data: Dictionary) -> void:
	_compacted_options = _compact_options(node_data.get("options", []))
	for i in range(_option_buttons.size()):
		var button := _option_buttons[i]
		if i < _compacted_options.size():
			var entry: Dictionary = _compacted_options[i]
			button.text = "[%d] %s" % [i + 1, entry["text"]]
			button.disabled = entry["disabled"]
		else:
			button.text = "[%d] ---" % [i + 1]
			button.disabled = true


## 按条件过滤选项：excluded 整条丢掉，hidden 且写了 hidden_text 的灰显占位。
## 过滤后再顺次编号，所以选项按钮的下标始终从 0 连续。
func _compact_options(options: Array) -> Array:
	var result: Array = []
	for option in options:
		if not (option is Dictionary):
			continue
		var visibility: String = GameEngine.check_option_visible(option)
		if visibility == "excluded":
			continue
		if visibility == "visible":
			result.append({
				"option": option,
				"disabled": false,
				"text": option.get("text", "选项"),
			})
		else:
			var hidden_text: String = option.get("hidden_text", "")
			if not hidden_text.is_empty():
				result.append({
					"option": option,
					"disabled": true,
					"text": hidden_text,
				})
	return result


func _on_option_pressed(index: int) -> void:
	_select_option(index)


func _select_option(index: int) -> void:
	if index < 0 or index >= _compacted_options.size():
		return
	var entry: Dictionary = _compacted_options[index]
	if entry["disabled"]:
		return

	var option: Dictionary = entry["option"]
	var result: Dictionary = GameEngine.select_option(option)

	_append_history("\n[color=#ffffff][b]【你】[/b][/color][color=#66fcf1]「%s」[/color]" % option.get("text", ""))
	_append_stat_changes(result.get("effects_applied", {}))

	# 战斗与商店还没移植，遇到就先停在原地，只提示不跳转
	if option.has("battle"):
		_append_history("[color=#ffaa00]（战斗系统尚未移植，本次遭遇被跳过）[/color]")
	if option.has("shop"):
		_append_history("[color=#ffaa00]（商店界面尚未移植，本次交易被跳过）[/color]")

	load_current_room()


func _append_stat_changes(effects: Dictionary) -> void:
	var changes: Array = GameEngine.resolve_stats_changes(effects)
	if changes.is_empty():
		return

	var parts: Array = []
	for change in changes:
		var key: String = change["key"]
		var delta := int(change["delta"])
		var stat_name: String = STATS_NAMES.get(key, key)
		var sign_str := "+" if delta > 0 else ""
		# 腐化是越高越糟，颜色与其他属性相反
		var positive_is_good := key != "corruption"
		var color := "#00ff88" if (delta > 0) == positive_is_good else "#ff5555"
		parts.append("[color=%s]%s %s%d[/color]" % [color, stat_name, sign_str, delta])

	_append_history("✦ 状态变更: %s" % ", ".join(parts))


## ────────────────────────── 弹窗 ──────────────────────────

func _open_profile() -> void:
	var modal := MODAL_SCENE.instantiate() as GameModal
	add_child(modal)

	modal.configure({
		"title": "人物详情",
		"accent": GameModal.ACCENT_PINK,
		"width": 560.0,
		"body_height": 300.0,
	})

	var stats: Dictionary = GameEngine.state.stats
	modal.add_text("名字: %s" % str(stats.get("player_name", "无名")))
	modal.add_text("生命: %d/%d" % [int(stats.get("hp", 0)), int(stats.get("max_hp", 100))])
	modal.add_text("理智: %d" % int(stats.get("san", 0)))
	modal.add_text("污染: %d" % int(stats.get("corruption", 0)))
	modal.add_text("")
	modal.add_text("—— 属性 ——", GameModal.ACCENT_PINK)
	modal.add_text("攻击: %d" % int(stats.get("attack", 0)))
	modal.add_text("防御: %d" % int(stats.get("defense", 0)))
	modal.add_text("智力: %d" % int(stats.get("intelligence", 0)))
	modal.add_text("敏捷: %d" % int(stats.get("agility", 0)))
	modal.add_action("close", "[ESC] 关闭")

	modal.action_pressed.connect(_on_modal_action.bind(modal))
	modal.closed.connect(_on_modal_closed)

	_active_modal = modal
	modal.open()


func _on_modal_action(id: String, modal: GameModal) -> void:
	match id:
		"close":
			modal.close()


func _on_modal_closed() -> void:
	_active_modal = null