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
@onready var _btn_diary: Button = $Root/Layout/BottomConsole/SystemPanel/LeftButtons/BtnDiary
@onready var _btn_shop: Button = $Root/Layout/BottomConsole/SystemPanel/RightButtons/BtnShop

## 当前画面上的选项（已按条件过滤、去掉了 excluded 项）
var _compacted_options: Array = []
## 6 个选项按钮，按顺序对应 _compacted_options 的下标
var _option_buttons: Array[Button] = []

## 弹窗栈：后进的在最上面。栈非空时主画面不响应键盘。
var _modal_stack: Array[GameModal] = []

## 物品栏的临时状态（弹窗关闭时清空）
var _inv_modal: GameModal = null
var _inv_list_box: VBoxContainer = null
var _inv_detail: RichTextLabel = null
var _inv_discard_btn: Button = null
var _inv_items: Array = []
var _inv_selected: int = 0

## 装备界面的提示行（装备失败时显示原因）
var _equip_status: Label = null

## 商店界面状态（弹窗关闭时清空）
var _shop_modal: GameModal = null
var _shop_list_box: VBoxContainer = null
var _shop_detail: RichTextLabel = null
var _shop_buy_btn: Button = null
var _shop_coins_label: Label = null
var _shop_items: Array = []
var _shop_selected: int = 0
var _shop_id: String = ""

## 日记界面状态
var _diary_modal: GameModal = null
var _diary_list_box: VBoxContainer = null
var _diary_detail: RichTextLabel = null
var _diary_entries: Array = []
var _diary_selected: int = 0
var _diary_track_btn: Button = null
var _diary_delete_btn: Button = null
## 未读时日记按钮的闪烁动画
var _diary_flash_tween: Tween = null

## 商店 / 日记界面的强调色（沿用弹窗那套配色）
const ACCENT_SHOP := Color(1, 0.666667, 0)            # #ffaa00 金（商店）
const ACCENT_DIARY := Color(0.901961, 0.721569, 0)    # #e6b800 黄（日记）


func _ready() -> void:
	for child in _option_grid.get_children():
		if child is Button:
			_option_buttons.append(child)
			child.pressed.connect(_on_option_pressed.bind(_option_buttons.size() - 1))

	_btn_profile.pressed.connect(_open_profile)
	_btn_inventory.pressed.connect(_open_inventory)
	_btn_save.pressed.connect(_open_save)
	_btn_settings.pressed.connect(_open_settings)
	_btn_diary.pressed.connect(_open_diary)
	_btn_shop.pressed.connect(_open_room_shop)

	GameEngine.stats_changed.connect(_refresh_status_bar)
	GameEngine.game_loaded.connect(load_current_room)

	load_current_room()


func _unhandled_key_input(event: InputEvent) -> void:
	if not _modal_stack.is_empty():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	# 系统界面快捷键（与原 Python 版 BINDINGS 一致）
	match event.keycode:
		KEY_P:
			accept_event()
			_open_profile()
			return
		KEY_I:
			accept_event()
			_open_inventory()
			return
		KEY_D:
			accept_event()
			_open_diary()
			return
		KEY_T:
			accept_event()
			_open_room_shop()
			return
		KEY_S:
			accept_event()
			_open_save()
			return
		KEY_O:
			accept_event()
			_open_settings()
			return

	var index := -1
	match event.keycode:
		KEY_1: index = 0
		KEY_2: index = 1
		KEY_3: index = 2
		KEY_4: index = 3
		KEY_5: index = 4
		KEY_6: index = 5
		_:
			return
	accept_event()
	_select_option(index)


## ────────────────────────── 场景渲染 ──────────────────────────

func load_current_room() -> void:
	if _check_game_over():
		return
	_refresh_status_bar()
	_refresh_tracked_task()
	_refresh_diary_button()

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

	# 商店交易：打开交易界面，不刷新房间（与原版一致，交易完仍停在原画面）
	var shop_id := str(option.get("shop", ""))
	if not shop_id.is_empty():
		_open_shop(shop_id)
		return

	# 战斗系统尚未移植，遇到就先提示并停在原地
	if option.has("battle"):
		_append_history("[color=#ffaa00]（战斗系统尚未移植，本次遭遇被跳过）[/color]")

	load_current_room()


## 生命归零就切到结局画面。返回 true 表示已经切换、调用方不要再刷新画面。
func _check_game_over() -> bool:
	if int(GameEngine.state.stats.get("hp", 1)) > 0:
		return false
	get_tree().change_scene_to_file("res://scenes/GameOver.tscn")
	return true


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


## ────────────────────────── 弹窗基础设施 ──────────────────────────

## 实例化一个弹窗并入树，返回配置好的实例（尚未打开）
func _make_modal(title: String, accent: Color, width: float, body_height: float) -> GameModal:
	var modal := MODAL_SCENE.instantiate() as GameModal
	add_child(modal)
	modal.configure({
		"title": title,
		"accent": accent,
		"width": width,
		"body_height": body_height,
	})
	return modal


## 压栈并打开。栈里已有弹窗时，屏蔽下面那层的 ESC，避免一次按键关掉两层。
func _push_modal(modal: GameModal) -> void:
	if not _modal_stack.is_empty():
		_modal_stack.back().input_blocked = true
	_modal_stack.append(modal)
	modal.closed.connect(_on_modal_closed.bind(modal))
	modal.open()


func _on_modal_closed(modal: GameModal) -> void:
	var idx := _modal_stack.find(modal)
	if idx != -1:
		_modal_stack.remove_at(idx)
	if not _modal_stack.is_empty():
		_modal_stack.back().input_blocked = false
	if modal == _inv_modal:
		_inv_modal = null
		_inv_list_box = null
		_inv_detail = null
		_inv_discard_btn = null
	if modal == _shop_modal:
		_shop_modal = null
		_shop_list_box = null
		_shop_detail = null
		_shop_buy_btn = null
	if modal == _diary_modal:
		_diary_modal = null
		_diary_list_box = null
		_diary_detail = null
		_diary_track_btn = null
		_diary_delete_btn = null


func _close_all_modals() -> void:
	while not _modal_stack.is_empty():
		_modal_stack.back().close()


## 轻量确认框，叠在当前弹窗之上；确认后执行 on_confirm
func _open_confirm(title: String, message: String, on_confirm: Callable,
		accent: Color = GameModal.ACCENT_PINK) -> void:
	var modal := _make_modal(title, accent, 460.0, 60.0)
	modal.add_text(message)
	modal.add_action("confirm", "[Y] 确认", accent)
	modal.add_action("cancel", "[N] 取消")
	modal.action_pressed.connect(func(id: String) -> void:
		if id == "confirm":
			modal.close()
			on_confirm.call()
		else:
			modal.close()
	)
	_push_modal(modal)


## ────────────────────────── 人物详情 ──────────────────────────

func _open_profile() -> void:
	var modal := _make_modal("人物详情", GameModal.ACCENT_PINK, 560.0, 300.0)

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
	modal.add_action("equipment", "[E] 装备", GameModal.ACCENT_AMBER)
	modal.add_action("close", "[ESC] 关闭")

	modal.action_pressed.connect(func(id: String) -> void:
		if id == "equipment":
			_open_equipment()
		else:
			modal.close()
	)
	_push_modal(modal)


## ────────────────────────── 物品栏 ──────────────────────────

func _open_inventory() -> void:
	var modal := _make_modal("物品栏", GameModal.ACCENT_CYAN, 760.0, 340.0)
	_inv_modal = modal
	_inv_selected = 0

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 左：物品列表（可滚动）
	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(260, 300)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inv_list_box = VBoxContainer.new()
	_inv_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_inv_list_box)
	main.add_child(list_scroll)

	# 右：详情 + 操作
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)

	_inv_detail = RichTextLabel.new()
	_inv_detail.bbcode_enabled = true
	_inv_detail.scroll_active = false
	_inv_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inv_detail.add_theme_color_override("default_color", GameModal.BODY_TEXT)
	right.add_child(_inv_detail)

	_inv_discard_btn = Button.new()
	_inv_discard_btn.text = "丢弃"
	_inv_discard_btn.custom_minimum_size = Vector2(0, 34)
	_inv_discard_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_discard_btn.disabled = true
	modal.style_button(_inv_discard_btn, Color(1, 0.333333, 0.333333))
	_inv_discard_btn.pressed.connect(_discard_selected_item)
	right.add_child(_inv_discard_btn)

	main.add_child(right)
	modal.add_node(main)

	modal.add_text("铜币: %d" % int(GameEngine.state.stats.get("coins", 0)), GameModal.ACCENT_GOLD)
	modal.add_action("close", "[ESC] 关闭")
	modal.action_pressed.connect(func(id: String) -> void:
		if id == "close":
			modal.close()
	)

	_refresh_inventory()
	_push_modal(modal)


func _refresh_inventory() -> void:
	_inv_items = GameEngine.inv_mgr.all()

	for child in _inv_list_box.get_children():
		_inv_list_box.remove_child(child)
		child.queue_free()

	if _inv_items.is_empty():
		var empty := Label.new()
		empty.text = "（背包空空如也）"
		empty.add_theme_color_override("font_color", GameModal.MUTED)
		_inv_list_box.add_child(empty)
		_inv_detail.text = ""
		_inv_discard_btn.disabled = true
		return

	for i in range(_inv_items.size()):
		var item: Dictionary = _inv_items[i]
		var qty := int(item.get("qty", 1))
		var btn := Button.new()
		btn.text = "%s x%d" % [item.get("name", "???"), qty] if qty > 1 else str(item.get("name", "???"))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 30)
		_inv_modal.style_button(btn, GameModal.ACCENT_CYAN)
		btn.add_theme_color_override("font_color",
			GameModal.ACCENT_CYAN if i == _inv_selected else GameModal.MUTED)
		btn.pressed.connect(_select_inventory_item.bind(i))
		_inv_list_box.add_child(btn)

	_inv_selected = clampi(_inv_selected, 0, _inv_items.size() - 1)
	_show_inventory_detail(_inv_selected)


func _select_inventory_item(index: int) -> void:
	_inv_selected = index
	for i in range(_inv_list_box.get_child_count()):
		var child := _inv_list_box.get_child(i)
		if child is Button:
			child.add_theme_color_override("font_color",
				GameModal.ACCENT_CYAN if i == index else GameModal.MUTED)
	_show_inventory_detail(index)


func _show_inventory_detail(index: int) -> void:
	if index < 0 or index >= _inv_items.size():
		return
	var item: Dictionary = _inv_items[index]
	var is_important: bool = item.get("type") == "quest" or item.get("type") == "key" or item.get("is_important", false)
	_inv_detail.text = "\n".join([
		"[b][color=#66fcf1]%s[/color][/b]" % item.get("name", "???"),
		"[color=#ffaa00]类型: %s[/color]" % GameEngine.inv_mgr.type_name(item.get("type", "misc")),
		"[color=#ffaa00]数量: %d[/color]" % int(item.get("qty", 1)),
		"",
		"[color=#b2b2b2]%s[/color]" % item.get("desc", "(无描述)"),
	])
	# 任务物品与钥匙不可丢弃（与原 Python 版一致）
	_inv_discard_btn.disabled = is_important
	_inv_discard_btn.text = "丢弃（重要物品）" if is_important else "丢弃"


func _discard_selected_item() -> void:
	if _inv_selected < 0 or _inv_selected >= _inv_items.size():
		return
	var item: Dictionary = _inv_items[_inv_selected]
	if GameEngine.inv_mgr.remove(item.get("id", ""), 1):
		GameEngine.inventory_changed.emit()
		_refresh_inventory()


## ────────────────────────── 装备 ──────────────────────────

const EQUIP_SLOT_NAMES: Dictionary = {"weapon": "武器", "armor": "防具", "accessory": "饰品"}
const EQUIP_STAT_NAMES: Dictionary = {"attack": "攻击", "defense": "防御", "intelligence": "智力", "agility": "敏捷"}


func _open_equipment() -> void:
	var modal := _make_modal("装备", GameModal.ACCENT_AMBER, 660.0, 300.0)
	modal.action_pressed.connect(func(id: String) -> void:
		if id.begins_with("equip:"):
			_do_equip(id.substr(6), modal)
		else:
			modal.close()
	)
	_fill_equipment(modal)
	_push_modal(modal)


## 重建装备界面内容。装备/卸下成功后直接再调一次即可刷新。
func _fill_equipment(modal: GameModal) -> void:
	modal.configure({"title": "装备", "accent": GameModal.ACCENT_AMBER,
		"width": 660.0, "body_height": 300.0})

	var equipment: Dictionary = GameEngine.get_equipment()
	for slot in GameEngine.EQUIP_SLOTS:
		var entry: Dictionary = equipment.get(slot, {})
		if entry.is_empty():
			modal.add_text("%s: （空）" % EQUIP_SLOT_NAMES.get(slot, slot), GameModal.MUTED)
			continue
		var bonus: Array = []
		for key in entry.get("stats", {}):
			bonus.append("+%d %s" % [int(entry["stats"][key]), EQUIP_STAT_NAMES.get(key, key)])
		var row := modal.add_row(str(EQUIP_SLOT_NAMES.get(slot, slot)),
			"%s   %s" % [entry.get("name", "?"), ", ".join(bonus)],
			GameModal.ACCENT_AMBER, Color(0.333333, 0.8, 0.333333))
		# 原 Python 版只做了装备、没做卸下，这里补上，否则一个槽位穿上就换不掉
		var unbtn := Button.new()
		unbtn.text = "卸下"
		unbtn.custom_minimum_size = Vector2(76, 28)
		modal.style_button(unbtn, GameModal.ACCENT_AMBER)
		unbtn.pressed.connect(_do_unequip.bind(slot, modal))
		row.add_child(unbtn)

	var summary: Dictionary = GameEngine.get_equipped_stats_summary()
	if summary.is_empty():
		modal.add_text("装备加成: 无", GameModal.MUTED)
	else:
		var parts: Array = []
		for key in summary:
			parts.append("+%d %s" % [int(summary[key]), EQUIP_STAT_NAMES.get(key, key)])
		modal.add_text("装备加成: %s" % ", ".join(parts), Color(0.533333, 0.8, 0.533333))

	_equip_status = modal.add_text("", Color(1, 0.333333, 0.333333))

	var equippable: Array = []
	for item in GameEngine.inv_mgr.all():
		var item_def: Dictionary = GameEngine.get_item_def(item.get("id", ""))
		if not str(item_def.get("equip_slot", "")).is_empty():
			equippable.append(item)

	modal.add_text("")
	if equippable.is_empty():
		modal.add_text("背包里没有可装备的物品。", GameModal.MUTED)
	else:
		modal.add_text("—— 可装备物品 ——", GameModal.ACCENT_AMBER)
		for item in equippable:
			modal.add_action("equip:%s" % item.get("id", ""),
				"%s x%d" % [item.get("name", "?"), int(item.get("qty", 1))],
				GameModal.ACCENT_AMBER)
	modal.add_action("close", "[ESC] 关闭")


func _do_equip(item_id: String, modal: GameModal) -> void:
	var result: Dictionary = GameEngine.equip(item_id)
	if result.get("success", false):
		_fill_equipment(modal)
	else:
		_equip_status.text = str(result.get("message", "无法装备"))


func _do_unequip(slot: String, modal: GameModal) -> void:
	var result: Dictionary = GameEngine.unequip(slot)
	if result.get("success", false):
		_fill_equipment(modal)
	else:
		_equip_status.text = str(result.get("message", "无法卸下"))


## ────────────────────────── 存 / 读档 ──────────────────────────

func _open_save() -> void:
	var modal := _make_modal("保存游戏", GameModal.ACCENT_GOLD, 620.0, 50.0)
	modal.add_text("点击槽位保存。已有存档的槽位会先询问是否覆盖。", GameModal.MUTED)
	modal.action_pressed.connect(func(id: String) -> void:
		if id.begins_with("slot:"):
			_on_save_slot_pressed(int(id.substr(5)), modal)
		else:
			modal.close()
	)
	_fill_save_slots(modal, true, GameModal.ACCENT_GOLD)
	_push_modal(modal)


func _open_load() -> void:
	var modal := _make_modal("读取存档", GameModal.ACCENT_GREEN, 620.0, 50.0)
	modal.add_text("读取会覆盖当前未保存的进度。", GameModal.MUTED)
	modal.action_pressed.connect(func(id: String) -> void:
		if id.begins_with("slot:"):
			_on_load_slot_pressed(int(id.substr(5)))
		else:
			modal.close()
	)
	_fill_save_slots(modal, false, GameModal.ACCENT_GREEN)
	_push_modal(modal)


## 生成 5 个槽位按钮。is_save 为 false 时空槽位禁用（不能读取空档）。
func _fill_save_slots(modal: GameModal, is_save: bool, accent: Color) -> void:
	for s in GameEngine.get_save_slots():
		var i := int(s.get("slot", 0))
		var label := "存档 %d" % i
		var disabled := false
		if s.get("corrupted", false):
			label = "存档 %d: （损坏）" % i
			disabled = true
		elif s.get("exists", false):
			label = "存档 %d: %s ｜ %s ｜ %s" % [i, s.get("player_name", "无名"),
				s.get("room_id", "?"), s.get("last_saved", "")]
		else:
			label = "存档 %d: 空" % i
			disabled = not is_save
		modal.add_action("slot:%d" % i, label, accent, disabled)
	modal.add_action("close", "[ESC] 返回" if is_save else "[ESC] 关闭")


func _slot_has_data(slot: int) -> bool:
	for s in GameEngine.get_save_slots():
		if int(s.get("slot", 0)) == slot and s.get("exists", false):
			return true
	return false


func _on_save_slot_pressed(slot: int, modal: GameModal) -> void:
	if _slot_has_data(slot) and GameEngine.settings.get("confirm_save", true):
		_open_confirm("覆盖存档 %d" % slot, "该槽位已有存档，确定要覆盖吗？",
			func() -> void: _do_save(slot, modal), GameModal.ACCENT_PINK)
	else:
		_do_save(slot, modal)


func _do_save(slot: int, modal: GameModal) -> void:
	if GameEngine.save_game(slot):
		_append_history("[color=#ffaa00]已保存到存档 %d[/color]" % slot)
		modal.close()
	else:
		_append_history("[color=#ff5555]保存失败[/color]")


func _on_load_slot_pressed(slot: int) -> void:
	if not _slot_has_data(slot):
		return
	_open_confirm("读取存档确认", "确定要读取存档 %d 吗？\n当前未保存的进度将会丢失。" % slot,
		func() -> void: _do_load(slot), GameModal.ACCENT_GREEN)


func _do_load(slot: int) -> void:
	if GameEngine.load_game(slot):
		_append_history("[color=#00ff66]已读取存档 %d[/color]" % slot)
		_close_all_modals()
	else:
		_append_history("[color=#ff5555]读取失败[/color]")


## ────────────────────────── 设置 ──────────────────────────

func _open_settings() -> void:
	var modal := _make_modal("设置", GameModal.ACCENT_GOLD, 660.0, 420.0)
	modal.action_pressed.connect(func(id: String) -> void:
		match id:
			"menu":
				_on_settings_menu()
			"load":
				_open_load()
			"exit":
				_on_settings_exit()
			"save_close":
				GameEngine.save_settings()
				modal.close()
			_:
				if id.begins_with("toggle:"):
					SettingsPanel.toggle(id.substr(7))
					_fill_settings(modal)
	)
	_fill_settings(modal)
	# 按 ESC 直接关掉时也要落盘（对应原版 action_close 里的 save_settings）
	modal.closed.connect(func() -> void: GameEngine.save_settings())
	_push_modal(modal)


func _fill_settings(modal: GameModal) -> void:
	modal.configure({"title": "设置", "accent": GameModal.ACCENT_GOLD,
		"width": 660.0, "body_height": 420.0})
	SettingsPanel.fill(modal)
	modal.add_action("menu", "返回主菜单", GameModal.ACCENT_CYAN)
	modal.add_action("load", "读取存档", GameModal.ACCENT_GREEN)
	modal.add_action("exit", "退出游戏", GameModal.ACCENT_PINK)
	modal.add_action("save_close", "保存并关闭", GameModal.ACCENT_GOLD)


func _on_settings_menu() -> void:
	GameEngine.save_settings()
	if GameEngine.settings.get("confirm_return", true):
		_open_confirm("返回主菜单", "确定要返回主菜单吗？\n未保存的进度将会丢失。",
			func() -> void: _goto_main_menu(), GameModal.ACCENT_CYAN)
	else:
		_goto_main_menu()


func _goto_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _on_settings_exit() -> void:
	GameEngine.save_settings()
	if GameEngine.settings.get("confirm_exit", true):
		_open_confirm("退出游戏", "确定要退出游戏吗？\n未保存的进度将会丢失。",
			func() -> void: get_tree().quit(), GameModal.ACCENT_PINK)
	else:
		get_tree().quit()


## ────────────────────────── 商店 ──────────────────────────

## 点底部 [T] 交易：开当前房间挂着的商店
func _open_room_shop() -> void:
	var room: Dictionary = GameEngine.get_room(GameEngine.state.room_id)
	var shop_id := str(room.get("shop", "")) if not room.is_empty() else ""
	if shop_id.is_empty():
		_append_history("[color=#ffaa00]这里没有可以交易的对象。[/color]")
		return
	_open_shop(shop_id)


func _open_shop(shop_id: String) -> void:
	var shop: Dictionary = GameEngine.get_shop(shop_id)
	if shop.is_empty():
		_append_history("[color=#ff5555]（商店数据不存在）[/color]")
		return

	_shop_id = shop_id
	_shop_selected = 0
	var modal := _make_modal(str(shop.get("name", "商店")), ACCENT_SHOP, 820.0, 330.0)
	_shop_modal = modal

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 左：商品列表
	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(300, 290)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_shop_list_box = VBoxContainer.new()
	_shop_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_shop_list_box)
	main.add_child(list_scroll)

	# 右：商品详情
	_shop_detail = RichTextLabel.new()
	_shop_detail.bbcode_enabled = true
	_shop_detail.scroll_active = false
	_shop_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_shop_detail.add_theme_color_override("default_color", GameModal.BODY_TEXT)
	main.add_child(_shop_detail)

	modal.add_node(main)

	var greeting := str(shop.get("greeting", ""))
	if not greeting.is_empty():
		modal.add_text(greeting, GameModal.MUTED)
	_shop_coins_label = modal.add_text("", GameModal.ACCENT_GOLD)

	_shop_buy_btn = modal.add_action("buy", "[Enter] 购买", ACCENT_SHOP)
	modal.add_action("close", "[ESC] 关闭")
	modal.action_pressed.connect(func(id: String) -> void:
		if id == "buy":
			_buy_selected()
		else:
			modal.close()
	)

	_refresh_shop()
	_push_modal(modal)


## 重新拉一遍商店数据（买完库存会变），重建列表与详情
func _refresh_shop() -> void:
	_shop_items = GameEngine.get_shop(_shop_id).get("items", [])
	_shop_coins_label.text = "铜币: %d" % int(GameEngine.state.stats.get("coins", 0))

	for child in _shop_list_box.get_children():
		_shop_list_box.remove_child(child)
		child.queue_free()

	if _shop_items.is_empty():
		var empty := Label.new()
		empty.text = "（商品已售罄）"
		empty.add_theme_color_override("font_color", GameModal.MUTED)
		_shop_list_box.add_child(empty)
		_shop_detail.text = ""
		_shop_buy_btn.disabled = true
		return

	for i in range(_shop_items.size()):
		var item: Dictionary = _shop_items[i]
		var stock := int(item.get("stock", -1))
		var label := "%s  %d铜" % [item.get("name", "???"), int(item.get("price", 0))]
		if stock >= 0:
			label += "  [库存:%d]" % stock
		var btn := Button.new()
		btn.text = label
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 30)
		_shop_modal.style_button(btn, ACCENT_SHOP)
		btn.pressed.connect(_select_shop_item.bind(i))
		_shop_list_box.add_child(btn)

	_shop_selected = clampi(_shop_selected, 0, _shop_items.size() - 1)
	_select_shop_item(_shop_selected)


func _select_shop_item(index: int) -> void:
	_shop_selected = index
	for i in range(_shop_list_box.get_child_count()):
		var child := _shop_list_box.get_child(i)
		if child is Button:
			child.add_theme_color_override("font_color",
				ACCENT_SHOP if i == index else GameModal.MUTED)
	_show_shop_detail(index)


func _show_shop_detail(index: int) -> void:
	if index < 0 or index >= _shop_items.size():
		return
	var item: Dictionary = _shop_items[index]
	var stock := int(item.get("stock", -1))
	var stock_text := "库存: %d 个" % stock if stock >= 0 else "无限供应"
	_shop_detail.text = "\n".join([
		"[b][color=#ffaa00]%s[/color][/b]" % item.get("name", "???"),
		"[color=#ffdd00]价格: %d 铜币[/color]" % int(item.get("price", 0)),
		"[color=#888888]%s[/color]" % stock_text,
		"",
		"[color=#b2b2b2]%s[/color]" % item.get("desc", "(无描述)"),
	])
	var coins := int(GameEngine.state.stats.get("coins", 0))
	_shop_buy_btn.disabled = coins < int(item.get("price", 0)) or stock == 0


func _buy_selected() -> void:
	if _shop_selected < 0 or _shop_selected >= _shop_items.size():
		return
	var item: Dictionary = _shop_items[_shop_selected]
	var result: Dictionary = GameEngine.buy_item(_shop_id, item.get("item_id", ""), 1)
	var color := "#00ff66" if result.get("success", false) else "#ff5555"
	_append_history("[color=%s]%s[/color]" % [color, result.get("message", "购买失败")])
	_refresh_shop()


## ────────────────────────── 日记 ──────────────────────────

## 只有拿到「日记本」这个物品（或置了对应 flag）才允许打开
func _refresh_diary_button() -> void:
	var has_diary := bool(GameEngine.get_flag("has_diary", false))
	if not has_diary:
		for item in GameEngine.inv_mgr.all():
			var item_id := str(item.get("id", ""))
			if item_id == "diary" or item_id == "old_diary":
				has_diary = true
				break
	_btn_diary.text = "[D] 日记" if has_diary else "[ ] ---"
	_btn_diary.disabled = not has_diary
	_set_diary_flash(has_diary and bool(GameEngine.get_flag("sys_diary_unread", false)))


## 有未读任务/笔记时让日记按钮呼吸闪烁
func _set_diary_flash(on: bool) -> void:
	if _diary_flash_tween != null and _diary_flash_tween.is_valid():
		_diary_flash_tween.kill()
	_diary_flash_tween = null
	_btn_diary.modulate = Color.WHITE
	if not on:
		return
	_diary_flash_tween = create_tween().set_loops()
	_diary_flash_tween.tween_property(_btn_diary, "modulate:a", 0.35, 0.4)
	_diary_flash_tween.tween_property(_btn_diary, "modulate:a", 1.0, 0.4)


func _open_diary() -> void:
	if _btn_diary.disabled:
		return
	# 打开即视为已读（与原版 on_mount 一致）
	GameEngine.set_flag("sys_diary_unread", false)
	_set_diary_flash(false)

	_diary_selected = 0
	var modal := _make_modal("日 记", ACCENT_DIARY, 720.0, 330.0)
	_diary_modal = modal

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(250, 290)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_diary_list_box = VBoxContainer.new()
	_diary_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_diary_list_box)
	main.add_child(list_scroll)

	_diary_detail = RichTextLabel.new()
	_diary_detail.bbcode_enabled = true
	_diary_detail.scroll_active = false
	_diary_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diary_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_diary_detail.add_theme_color_override("default_color", GameModal.BODY_TEXT)
	main.add_child(_diary_detail)

	modal.add_node(main)

	_diary_track_btn = modal.add_action("track", "[T] 追踪任务", ACCENT_DIARY)
	_diary_delete_btn = modal.add_action("delete", "[D] 删除笔记")
	modal.add_action("new", "[N] 新建笔记", GameModal.ACCENT_GREEN)
	modal.add_action("close", "[ESC] 关闭")
	modal.action_pressed.connect(func(id: String) -> void:
		match id:
			"track":
				_toggle_track_selected()
			"delete":
				_delete_selected_note()
			"new":
				_open_new_note()
			_:
				modal.close()
	)

	_rebuild_diary_entries()
	_push_modal(modal)


func _rebuild_diary_entries() -> void:
	for child in _diary_list_box.get_children():
		_diary_list_box.remove_child(child)
		child.queue_free()

	_diary_entries = []
	var diary: Dictionary = GameEngine.state.diary
	var tasks: Array = diary.get("tasks", [])
	var notes: Array = diary.get("notes", [])

	if not tasks.is_empty():
		_diary_list_box.add_child(_make_section_header("── 任务 ──"))
		for task in tasks:
			_diary_entries.append({"type": "task", "data": task})
			var label := str(task.get("title", "???"))
			if task.get("done", false):
				label = "✓ " + label
			_diary_list_box.add_child(_make_entry_button(_diary_entries.size() - 1, label))

	if not notes.is_empty():
		_diary_list_box.add_child(_make_section_header("── 笔记 ──"))
		for note in notes:
			_diary_entries.append({"type": "note", "data": note})
			_diary_list_box.add_child(_make_entry_button(_diary_entries.size() - 1, str(note.get("title", "???"))))

	if _diary_entries.is_empty():
		var empty := Label.new()
		empty.text = "（日记还是空的）"
		empty.add_theme_color_override("font_color", GameModal.MUTED)
		_diary_list_box.add_child(empty)
		_diary_detail.text = ""
		_diary_track_btn.disabled = true
		_diary_delete_btn.disabled = true
		return

	_diary_selected = clampi(_diary_selected, 0, _diary_entries.size() - 1)
	_select_diary_entry(_diary_selected)


func _make_section_header(text: String) -> Label:
	var header := Label.new()
	header.text = text
	header.add_theme_color_override("font_color", ACCENT_DIARY)
	return header


func _make_entry_button(index: int, text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 30)
	_diary_modal.style_button(btn, ACCENT_DIARY)
	btn.add_theme_color_override("font_color",
		ACCENT_DIARY if index == _diary_selected else GameModal.MUTED)
	btn.pressed.connect(_select_diary_entry.bind(index))
	return btn


## 选中某条：列表里只有按钮算条目，小节标题（Label）跳过不编号
func _select_diary_entry(index: int) -> void:
	if index < 0 or index >= _diary_entries.size():
		return
	_diary_selected = index
	var entry_index := 0
	for child in _diary_list_box.get_children():
		if not (child is Button):
			continue
		child.add_theme_color_override("font_color",
			ACCENT_DIARY if entry_index == index else GameModal.MUTED)
		entry_index += 1
	_show_diary_detail(index)


func _show_diary_detail(index: int) -> void:
	var entry: Dictionary = _diary_entries[index]
	var data: Dictionary = entry["data"]
	if entry["type"] == "task":
		_diary_delete_btn.disabled = true
		_diary_track_btn.disabled = false
		var tracked_id := str(GameEngine.get_flag("sys_tracked_task_id", ""))
		_diary_track_btn.text = "[T] 取消追踪" if tracked_id == str(data.get("id", "")) else "[T] 追踪任务"
		var status := "[color=#557766]已完成[/color]" if data.get("done", false) else "[color=#66fcf1]进行中[/color]"
		_diary_detail.text = "\n".join([
			"[b][color=#e6b800]%s[/color][/b]" % data.get("title", "???"),
			"状态: %s" % status,
			"",
			"[color=#c5c6c7]%s[/color]" % data.get("content", "(无描述)"),
		])
	else:
		_diary_delete_btn.disabled = false
		_diary_track_btn.disabled = true
		_diary_detail.text = "\n".join([
			"[b][color=#ffaa00]%s[/color][/b]" % data.get("title", "???"),
			"[color=#888888]记录于: %s[/color]" % data.get("created", ""),
			"",
			"[color=#c5c6c7]%s[/color]" % data.get("content", ""),
		])


func _toggle_track_selected() -> void:
	if _diary_selected < 0 or _diary_selected >= _diary_entries.size():
		return
	var entry: Dictionary = _diary_entries[_diary_selected]
	if entry["type"] != "task":
		return
	var task_id := str(entry["data"].get("id", ""))
	var current := str(GameEngine.get_flag("sys_tracked_task_id", ""))
	GameEngine.set_flag("sys_tracked_task_id", "" if current == task_id else task_id)
	_show_diary_detail(_diary_selected)
	_refresh_tracked_task()


func _delete_selected_note() -> void:
	if _diary_selected < 0 or _diary_selected >= _diary_entries.size():
		return
	var entry: Dictionary = _diary_entries[_diary_selected]
	if entry["type"] != "note":
		return
	var note_id := str(entry["data"].get("id", ""))
	var notes: Array = GameEngine.state.diary.get("notes", [])
	for i in range(notes.size()):
		if str(notes[i].get("id", "")) == note_id:
			notes.remove_at(i)
			break
	_diary_selected = max(0, _diary_selected - 1)
	_rebuild_diary_entries()


func _open_new_note() -> void:
	var modal := _make_modal("新建笔记", ACCENT_DIARY, 580.0, 60.0)
	modal.add_text("标题:", GameModal.MUTED)
	var title_input := LineEdit.new()
	title_input.placeholder_text = "输入笔记标题..."
	title_input.custom_minimum_size = Vector2(0, 34)
	modal.add_node(title_input)

	modal.add_text("内容:", GameModal.MUTED)
	var content_input := LineEdit.new()
	content_input.placeholder_text = "输入笔记内容..."
	content_input.custom_minimum_size = Vector2(0, 34)
	modal.add_node(content_input)

	modal.add_action("save", "[保存]", GameModal.ACCENT_GREEN)
	modal.add_action("cancel", "[ESC] 取消")
	modal.action_pressed.connect(func(id: String) -> void:
		if id == "save":
			_save_new_note(title_input.text, content_input.text)
		modal.close()
	)
	_push_modal(modal)
	# 让光标直接落在标题框里（弹窗 open() 之后抢焦点，才不会被底部按钮抢走）
	title_input.grab_focus.call_deferred()


func _save_new_note(title: String, content: String) -> void:
	var clean_title := title.strip_edges()
	if clean_title.is_empty():
		return
	var now := Time.get_datetime_string_from_system(false, true)
	GameEngine.state.diary["notes"].append({
		"id": "note_%s" % now.replace("-", "").replace(":", "").replace(" ", ""),
		"title": clean_title,
		"content": content.strip_edges(),
		"created": now.substr(0, 16),
	})
	GameEngine.set_flag("sys_diary_unread", true)
	_diary_selected = _diary_entries.size()
	_rebuild_diary_entries()
	_set_diary_flash(false)