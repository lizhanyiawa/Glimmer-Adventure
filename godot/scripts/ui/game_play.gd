extends Control
## 主玩法画面（对应 Python 的 view/game_menu.py: GamePlayScreen）。
##
## 职责：把 GameEngine 的状态渲染成画面，并把玩家的点击转回引擎。
## 不包含任何游戏规则——规则全在 scripts/core/ 里。

const MODAL_SCENE := preload("res://scenes/Modal.tscn")
const BATTLE_SCENE := preload("res://scenes/Battle.tscn")

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
@onready var _location_label: Label = $Root/Layout/LocationLabel
@onready var _combat_label: Label = $Root/Layout/StatusBar/StatusRow/StatsRight/CombatLabel
@onready var _mind_label: Label = $Root/Layout/StatusBar/StatusRow/StatsRight/MindLabel
@onready var _corruption_label: Label = $Root/Layout/StatusBar/StatusRow/StatsRight/CorruptionLabel

@onready var _story_text: RichTextLabel = $Root/Layout/MainViewport/StoryBox/StoryText
@onready var _history_text: RichTextLabel = $Root/Layout/MainViewport/RightPanel/HistoryBox/HistoryText
@onready var _tracked_panel: PanelContainer = $Root/Layout/MainViewport/RightPanel/TrackedTask
@onready var _tracked_label: Label = $Root/Layout/MainViewport/RightPanel/TrackedTask/TrackedLabel

## 整屏色调要改色的几块面板（底色 + 描边）
@onready var _bg: ColorRect = $Bg
@onready var _status_panel: PanelContainer = $Root/Layout/StatusBar
@onready var _story_panel: PanelContainer = $Root/Layout/MainViewport/StoryBox
@onready var _history_panel: PanelContainer = $Root/Layout/MainViewport/RightPanel/HistoryBox

@onready var _option_grid: GridContainer = $Root/Layout/BottomConsole/OptionGrid
@onready var _btn_profile: Button = $Root/Layout/BottomConsole/SystemPanel/LeftButtons/BtnProfile
@onready var _btn_inventory: Button = $Root/Layout/BottomConsole/SystemPanel/LeftButtons/BtnInventory
@onready var _btn_save: Button = $Root/Layout/BottomConsole/SystemPanel/LeftButtons/BtnSave
@onready var _btn_settings: Button = $Root/Layout/BottomConsole/SystemPanel/LeftButtons/BtnSettings
@onready var _btn_diary: Button = $Root/Layout/BottomConsole/SystemPanel/LeftButtons/BtnDiary
@onready var _btn_shop: Button = $Root/Layout/BottomConsole/SystemPanel/RightButtons/BtnShop
@onready var _btn_codex: Button = $Root/Layout/BottomConsole/SystemPanel/RightButtons/BtnCodex

## 文字速度档位 → 每个字多少秒。取值与 Python 版 engine/effects.py 的
## SPEED_PRESETS、以及 battle.gd 完全一致，战斗内外的手感才统一。
const SPEED_PRESETS: Dictionary = {"instant": 0.0, "fast": 0.01, "medium": 0.03, "slow": 0.06}

## 当前画面上的选项（已按条件过滤、去掉了 excluded 项）
var _compacted_options: Array = []
## 6 个选项按钮，按顺序对应 _compacted_options 的下标
var _option_buttons: Array[Button] = []
## 每个选项按钮里那个负责显示文字的子 Label。按钮本身 text 留空、
## 由 Label 自动换行——否则长文本会把 Button 的最小宽度撑开，把整列挤变形。
var _option_labels: Array[Label] = []
## 每个选项按钮一份独立的 normal / hover 样式副本，按动作类型改描边与悬停底色
var _option_styles: Array[StyleBoxFlat] = []
var _option_hover_styles: Array[StyleBoxFlat] = []
## 每个选项按钮当前的类型色（悬停/常态的文字色都用它）
var _option_type_colors: Array[Color] = []

## 整屏色调：保存面板样式的原始底色，退出特殊状态时好还原
var _tone_panels: Array = []
## 系统按钮的 normal 样式（只跟着整屏色调改底色）
var _sys_styles: Array = []
## 正在跑的整屏换调补间。重算前要先 kill，否则两条会抢同一个颜色属性
var _tone_tween: Tween = null
## 氛围粒子，跟着整屏色调一起换颜色
var _ambient: CPUParticles2D = null

## 本次正文是否还在逐字显示（此时点击 / 回车 = 快进）
var _typing := false
## 打字机代号：每次重开一段正文 +1，旧的那段 while 循环看到代号变了就退出，
## 免得快速连点选项时两条打字动画互相抢 visible_ratio。
var _type_gen := 0
## 正在跑的打字补间。切房间时要先 kill 掉上一条，否则两条补间会抢同一个属性。
var _type_tween: Tween = null
## 当前正在打字的那份节点数据。快进时用它重建选项。
var _current_node_data: Dictionary = {}

## 血条上一帧的比例（-1 = 还没记录过）。首次刷新是"初始值"而不是掉血，
## 不能画残影，所以用 -1 当哨兵。
var _bar_prev: Dictionary = {}
## 血条长度动画（按最大值伸缩），key 是 ProgressBar，切换最大值时先 kill 上一条
var _bar_width_tweens: Dictionary = {}

## 位置栏上次显示的文字：变了才做一次高亮，免得每次刷新正文都重播
var _last_location_text := ""
## 只记地点部分（不含时间），时间刷新时用它重拼整行
var _location_place := ""

## 日记按钮当前是否处于"有未读"状态（只在 0→1 的那一次提醒）
var _diary_flash_on := false
## 未读时的呼吸动画
var _diary_flash_tween: Tween = null

## 弹窗栈：后进的在最上面。栈非空时主画面不响应键盘。
var _modal_stack: Array[GameModal] = []

## 物品栏的临时状态（弹窗关闭时清空）
var _inv_modal: GameModal = null
var _inv_list_box: VBoxContainer = null
var _inv_detail: RichTextLabel = null
## 当前分区："bag"（背包+已装备）/ "ground"（本房间地上）
var _inv_tab: String = "bag"
var _inv_tab_btns: Array[Button] = []
## 当前分类筛选（对应 INV_FILTERS 的 id），默认「全部」
var _inv_filter: String = "all"
var _inv_filter_btns: Array[Button] = []
## 详情下方那一排动态操作按钮（装备/卸下、使用、丢弃、捡起）
var _inv_actions: HBoxContainer = null
## 操作反馈行：丢弃/使用/装备之后在这里给一句提示
var _inv_status: Label = null
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
## 日记当前分类筛选（对应 DIARY_FILTERS 的 id），默认「全部」
var _diary_filter: String = "all"
var _diary_filter_btns: Array[Button] = []

## 百科界面状态（列表 + 正文 + 分类筛选）
var _codex_modal: GameModal = null
var _codex_list_box: VBoxContainer = null
var _codex_detail: RichTextLabel = null
var _codex_entries: Array = []
var _codex_selected: int = 0
var _codex_filter: String = "all"
var _codex_filter_btns: Array[Button] = []

## 商店 / 日记 / 百科界面的强调色（沿用弹窗那套配色）
const ACCENT_SHOP := Palette.GOLD                     # #ffaa00 金（商店）
const ACCENT_DIARY := Palette.AMBER                   # #e6b800 黄（日记）
const ACCENT_CODEX := Palette.BLUE                    # #5aa9ff 蓝（百科）

## 整屏换调（常态青 ↔ 对话绿 / 濒死红 / 理智紫 / 重伤琥珀）的过渡时长
const TONE_FADE := 0.35

## 血条 / 理智条的填充样式（运行时按比例改颜色）
var _hp_fill: StyleBoxFlat = null
var _san_fill: StyleBoxFlat = null


func _ready() -> void:
	# 选项按钮：text 留空，内嵌一个会自动换行的 Label 来显示文字。
	# Button 不是容器，子节点不参与它的最小尺寸计算，所以长文本不会再撑宽按钮。
	for child in _option_grid.get_children():
		if child is Button:
			var index := _option_buttons.size()
			_option_buttons.append(child)
			var label := Label.new()
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			child.add_child(label)
			# 铺满按钮：Button 不是容器，不会自动给子节点排版
			label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_option_labels.append(label)
			# 每个按钮一份独立的 normal / hover 样式副本，之后按动作类型改色
			# 才不会互相串（主题里的样式是所有按钮共用的同一份资源）
			var normal_sb := child.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
			var hover_sb := child.get_theme_stylebox("hover").duplicate() as StyleBoxFlat
			child.add_theme_stylebox_override("normal", normal_sb)
			child.add_theme_stylebox_override("focus", normal_sb)
			child.add_theme_stylebox_override("hover", hover_sb)
			child.add_theme_stylebox_override("pressed", hover_sb)
			_option_styles.append(normal_sb)
			_option_hover_styles.append(hover_sb)
			_option_type_colors.append(Palette.OPTION_TYPE_DEFAULT)
			child.text = ""
			child.pressed.connect(_on_option_pressed.bind(index))
			# 悬停时把文字换成深色（按钮底色会变成该选项的类型色），禁用时用灰色
			child.mouse_entered.connect(_on_option_hover.bind(index, true))
			child.mouse_exited.connect(_on_option_hover.bind(index, false))

	_btn_profile.pressed.connect(_open_profile)
	_btn_inventory.pressed.connect(_open_inventory)
	_btn_save.pressed.connect(_open_save)
	_btn_settings.pressed.connect(_open_settings)
	_btn_diary.pressed.connect(_open_diary)
	_btn_shop.pressed.connect(_open_room_shop)
	_btn_codex.pressed.connect(_open_codex)
	_style_system_buttons()
	_collect_tone_styles()
	# 背包有新东西（购买 / 掉落 / 剧情奖励）就让"物品"按钮被注意到
	GameEngine.inv_mgr.item_added.connect(_on_item_added)

	# 把血条填充样式取成独立实例，之后就能按血量实时改颜色
	_hp_fill = _hp_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	_hp_bar.add_theme_stylebox_override("fill", _hp_fill)
	_san_fill = _san_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	_san_bar.add_theme_stylebox_override("fill", _san_fill)

	GameEngine.stats_changed.connect(_refresh_status_bar)
	GameEngine.game_loaded.connect(load_current_room)
	GameEngine.time_changed.connect(_on_time_changed)

	# 背景氛围粒子：插在底色块之后、内容之前，粒子才会在"后面"
	_ambient = Fx.add_ambient(self, Color(Palette.CYAN_DEEP, 0.10), 30)
	move_child(_ambient, 1)

	# 点击 = 快进：把装饰性容器全部放行，点击才会落到本节点的 _gui_input。
	# Button 保持 STOP（它们要能点中），其余 Control 一律 IGNORE。
	_make_passive($Bg)
	_make_passive($Root)

	# 清掉场景里可能残留的占位文本：历史记录只该显示真正发生过的剧情，
	# 否则开场会看见一堆从没发生过的句子。
	_history_text.text = ""
	load_current_room()
	Fx.stagger(_option_buttons, 0.035, 0.22)


## 给系统按钮补上 hover / pressed / focus 三种状态。
## 场景里这几个按钮只写了 normal，一旦鼠标悬停就会掉回 Godot 内置主题的灰底，
## 和整套终端青配色对不上；补齐之后就与选项按钮的表现一致了。
## 悬停时底色变青，所以文字要跟着压成深色，否则糊在一起。
func _style_system_buttons() -> void:
	for button in [_btn_profile, _btn_inventory, _btn_save, _btn_settings, _btn_diary, _btn_shop, _btn_codex]:
		var normal := button.get_theme_stylebox("normal").duplicate() as StyleBoxFlat

		var accent := StyleBoxFlat.new()
		accent.bg_color = Palette.CYAN
		accent.set_corner_radius_all(3)
		accent.content_margin_left = 8.0
		accent.content_margin_right = 8.0
		accent.content_margin_top = 4.0
		accent.content_margin_bottom = 4.0

		button.add_theme_stylebox_override("hover", accent)
		button.add_theme_stylebox_override("pressed", accent)
		button.add_theme_stylebox_override("focus", normal)
		button.add_theme_color_override("font_hover_color", Palette.BG)
		button.add_theme_color_override("font_pressed_color", Palette.BG)


## 把要跟着"整屏色调"走的面板样式取成独立实例，并记下它们的原始底色，
## 这样退出特殊状态（对话结束 / 血量回满）时能精确还原，不会残留绿色。
func _collect_tone_styles() -> void:
	for panel in [_status_panel, _story_panel, _history_panel]:
		var sb := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		panel.add_theme_stylebox_override("panel", sb)
		_tone_panels.append({"sb": sb, "bg": sb.bg_color})
	for button in [_btn_profile, _btn_inventory, _btn_save, _btn_settings, _btn_diary, _btn_shop, _btn_codex]:
		var sb := button.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		button.add_theme_stylebox_override("normal", sb)
		_sys_styles.append({"sb": sb, "bg": sb.bg_color})


## 按当前处境给整屏定调（对应 Python 版 game_menu.py 的 _update_ui_colors）。
## 优先级：对话中（绿）> 濒死（红）> 理智 < 30（紫）> 重伤（琥珀）> 常态（青）。
##
## 面板底色不是直接换成纯色，而是往"整屏底色"靠一半，保留原本的深浅层次，
## 只看得出"整体偏绿/偏红"，不至于变成一块死色。
func _update_ui_colors() -> void:
	var stats: Dictionary = GameEngine.state.stats
	var hp_ratio := float(int(stats.get("hp", 100))) / float(maxi(1, int(stats.get("max_hp", 100))))
	var san := int(stats.get("san", 100))
	var in_dialogue := not str(GameEngine.state.dialogue_id).is_empty()

	var screen_bg := Palette.BG
	var border := Palette.CYAN_DEEP
	var active := false
	if in_dialogue:
		screen_bg = Palette.BG_DIALOGUE
		border = Palette.GREEN
		active = true
	elif hp_ratio < 0.1:
		screen_bg = Palette.BG_DANGER
		border = Palette.RED
		active = true
	elif san < 30:
		screen_bg = Palette.BG_MADNESS
		border = Palette.VIOLET
		active = true
	elif hp_ratio < 0.3:
		screen_bg = Palette.BG_HURT
		border = Palette.GOLD
		active = true

	# 整屏换调走补间，不然从常态青一下跳到"对话绿/濒死红"太生硬。
	# 每次重算先掐掉上一条，避免两条补间抢同一个颜色属性。
	if _tone_tween != null and _tone_tween.is_valid():
		_tone_tween.kill()
	_tone_tween = create_tween().set_parallel(true)
	_tone_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_tone_tween.tween_property(_bg, "color", screen_bg, TONE_FADE)
	for entry in _tone_panels:
		var sb: StyleBoxFlat = entry["sb"]
		var orig: Color = entry["bg"]
		_tone_tween.tween_property(sb, "bg_color", orig.lerp(screen_bg, 0.5) if active else orig, TONE_FADE)
		_tone_tween.tween_property(sb, "border_color", border, TONE_FADE)
	for entry in _sys_styles:
		var sb: StyleBoxFlat = entry["sb"]
		var orig: Color = entry["bg"]
		_tone_tween.tween_property(sb, "bg_color", orig.lerp(screen_bg, 0.5) if active else orig, TONE_FADE)
	if _ambient != null and is_instance_valid(_ambient):
		_tone_tween.tween_property(_ambient, "color", Color(border, 0.10), TONE_FADE)


## 递归把装饰性 Control 放行，让空白处的点击继续上传到本节点。
##   Button → 保持 STOP（要能点中）
##   RichTextLabel → PASS（滚轮还能翻正文/历史，不处理左键时再上传）
##   其余 → IGNORE（纯装饰，不吃任何鼠标事件）
func _make_passive(node: Node) -> void:
	if node is Button:
		return
	if node is RichTextLabel:
		(node as RichTextLabel).mouse_filter = Control.MOUSE_FILTER_PASS
	elif node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_make_passive(child)


## 点到空白处 = 回车（快速跳过打字机）
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_skip_typing()


func _unhandled_key_input(event: InputEvent) -> void:
	if not _modal_stack.is_empty():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	# 正在逐字显示时，回车 / 空格 = 快进（与点击空白等价）
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		if _typing:
			accept_event()
			_skip_typing()
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
		KEY_C:
			accept_event()
			_open_codex()
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

	# 记下"这个地方来过了"：别处的「查看类」选项指向已到过的房间时会变暗，
	# 一眼就能看出哪些是已经翻过的角落。
	if not room_id.is_empty():
		GameEngine.set_flag("loc_visited_%s" % room_id, true)

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
		_cancel_typing()
		_story_text.text = "[错误] 数据不存在 (Room: %s, Dialogue: %s)" % [room_id, dialogue_id]
		_set_options_pending()
		return

	if is_dialogue:
		var room_data: Dictionary = GameEngine.get_room(room_id)
		var place: String = room_data.get("title", room_id) if not room_data.is_empty() else "未知地点"
		_set_location("位置：%s (对话中)" % place)
	else:
		_set_location("位置：%s" % node_data.get("title", room_id))

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
			_append_history(Palette.render_static(dialogue_text))
	else:
		var title: String = node_data.get("title", room_id)
		var story_text: String = GameEngine.resolve_room_description(node_data)
		full_text = "【 %s 】\n\n%s" % [title, story_text]
		_append_history("\n[color=#ffffff][b]【 %s 】[/b][/color]" % title)
		_append_history(Palette.render_static(story_text))

	# 打字机逐字显示，打完再把选项亮出来——和 Python 版
	# （text_type 完成后才 refresh_options）保持一致
	_type_story(full_text, node_data)


## 更新顶部位置栏（地点 + 时间）。文字真的变了才做一次弹入高亮，免得每次刷新正文都重播。
func _set_location(text: String) -> void:
	_location_place = text
	var full := "%s　·　%s" % [text, GameEngine.get_time_display()]
	if full == _last_location_text:
		return
	_last_location_text = full
	_location_label.text = full
	_location_label.modulate.a = 1.0
	Fx.pop_in(_location_label, 0.0, 0.45)


## 时间变了（换房间/睡觉）先把顶栏文字改掉，不做弹入动画，
## 免得紧接着的 load_current_room 又弹一次、看起来闪两下
func _on_time_changed(_day: int, _hour: int) -> void:
	if _location_place.is_empty():
		return
	var full := "%s　·　%s" % [_location_place, GameEngine.get_time_display()]
	if full == _last_location_text:
		return
	_last_location_text = full
	_location_label.text = full


## 打字机：按设置里的文字速度逐字显示 full_text，显示完再重建选项。
## 点空白 / 回车会调 _skip_typing() 直接把整段放出来。
func _type_story(full_text: String, node_data: Dictionary) -> void:
	_cancel_typing()
	_type_gen += 1
	var gen := _type_gen
	_current_node_data = node_data

	_story_text.text = Palette.render(full_text)
	_story_text.visible_ratio = 0.0

	var speed := _typing_speed()
	if speed <= 0.0:
		_story_text.visible_ratio = 1.0
		_rebuild_options(node_data)
		return

	_typing = true
	# 用"真实可见字数"算时长，BBCode 标签不计入，长短句不会忽快忽慢
	var count := maxi(1, _story_text.get_total_character_count())
	_type_tween = create_tween()
	_type_tween.tween_property(_story_text, "visible_ratio", 1.0, maxf(0.15, speed * float(count)))

	# 每帧检查：打完了 / 被快进（_typing=false） / 被下一段正文顶掉（代号变了）
	while _typing and gen == _type_gen and _story_text.visible_ratio < 1.0:
		await get_tree().process_frame
	if gen != _type_gen or not is_instance_valid(_story_text):
		return   # 已经被下一段正文取代，收尾交给新的那一轮

	_cancel_typing()
	_story_text.visible_ratio = 1.0
	_rebuild_options(node_data)


## 点空白 / 回车 = 立刻把本段正文全部显示出来，并把选项亮出来
func _skip_typing() -> void:
	if not _typing:
		return
	_cancel_typing()
	_story_text.visible_ratio = 1.0
	_rebuild_options(_current_node_data)


## 打断当前这段打字（不刷新选项）。
## 会 kill 掉补间——不 kill 的话它还会继续把 visible_ratio 从当前值推向 1.0，
## 和"立刻显示全文"打架；同时把代号 +1，让还在跑的协程认定自己已过期。
func _cancel_typing() -> void:
	_typing = false
	_type_gen += 1
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	_type_tween = null


## 文字速度设置 → 每个字多少秒（0 表示瞬间显示全文）
func _typing_speed() -> float:
	return SPEED_PRESETS.get(str(GameEngine.settings.get("text_speed", "medium")), 0.03)


func _refresh_status_bar() -> void:
	var stats: Dictionary = GameEngine.state.stats

	var hp := int(stats.get("hp", 0))
	var max_hp := maxi(1, int(stats.get("max_hp", 100)))
	_hp_label.text = "HP: %d/%d" % [hp, max_hp]
	_set_bar(_hp_bar, _hp_fill, hp, max_hp)

	var san := int(stats.get("san", 0))
	_san_label.text = "SAN: %d/100" % san
	_set_bar(_san_bar, _san_fill, san, 100)

	_combat_label.text = "ATK: %d   DEF: %d" % [int(stats.get("attack", 0)), int(stats.get("defense", 0))]
	_mind_label.text = "INT: %d   AGI: %d" % [int(stats.get("intelligence", 0)), int(stats.get("agility", 0))]
	_corruption_label.text = "COR: %d%%" % int(stats.get("corruption", 0))

	# 状态一变（掉血 / 扣理智 / 进对话）整屏色调跟着走
	_update_ui_colors()


## 血条/理智条：设值 + 按比例取色（高=青、中=琥珀、低=红，与 Python 版一致）。
## 掉血时叠一层"虚血"残影，让条不是一步跳到新值。
##
## 首次刷新只能当作"初始值"（_bar_prev 里没记录过），否则场景预置的占位数值
## 会被当成掉血，一进游戏先白白流一截残影。
func _set_bar(bar: ProgressBar, fill: StyleBoxFlat, value: int, max_value: int) -> void:
	var new_ratio := float(value) / float(maxi(1, max_value))
	var prev: float = _bar_prev.get(bar, -1.0)

	bar.max_value = max_value
	bar.value = value
	fill.bg_color = Palette.bar_color(new_ratio)
	_sync_bar_width(bar, max_value)

	if prev >= 0.0:
		Fx.ghost_drain(bar, prev, new_ratio)
	_bar_prev[bar] = new_ratio


## 血条长度跟着"最大值"走：最大生命/理智越大，条越长，但到上限就不再长。
##
## 为什么要有上限：上限是给成长留的余量，同时保证两张条永远不会长到把
## 状态栏顶破；到顶之后只靠数值增长来体现成长。
## 场景里初始就写成 120（= 100 点最大值对应的长度），所以进游戏不会先跳一下。
## 数值整体收短了一档：状态栏里两张条原来偏长，压住了旁边的属性文字。
const BAR_WIDTH_MIN := 70.0     ## 最短（最大值 ≤ 0 时的兜底）
const BAR_WIDTH_PER_POINT := 0.5  ## 每 1 点最大值加多少像素
const BAR_WIDTH_MAX := 200.0    ## 长度上限：再涨也不加长了

func _sync_bar_width(bar: ProgressBar, max_value: int) -> void:
	var target := clampf(BAR_WIDTH_MIN + float(max_value) * BAR_WIDTH_PER_POINT,
		BAR_WIDTH_MIN, BAR_WIDTH_MAX)
	if is_equal_approx(bar.custom_minimum_size.x, target):
		return
	var tween: Tween = _bar_width_tweens.get(bar)
	if tween != null and tween.is_valid():
		tween.kill()
	tween = bar.create_tween()
	tween.tween_property(bar, "custom_minimum_size:x", target, 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_bar_width_tweens[bar] = tween


func _refresh_tracked_task() -> void:
	var tracked_id: String = GameEngine.get_flag("sys_tracked_task_id", "")
	if tracked_id.is_empty():
		_set_tracked("追踪任务：无", false)
		return
	for task in GameEngine.state.diary.get("tasks", []):
		if task.get("id") == tracked_id:
			var prefix := "✓ " if task.get("done", false) else ""
			_set_tracked("追踪任务：%s%s" % [prefix, task.get("title", "???")], true)
			return
	_set_tracked("追踪任务：无", false)


## 有追踪任务时面板保持金色边框的原样；没有时整块压暗。
## 右边常驻一个空的金框太抢眼，压暗之后它退成背景，有任务了再亮回来。
func _set_tracked(text: String, active: bool) -> void:
	_tracked_label.text = text
	_tracked_panel.modulate = Color.WHITE if active else Color(1, 1, 1, 0.45)


func _append_history(bbcode: String) -> void:
	_history_text.append_text(bbcode + "\n")


## ────────────────────────── 选项 ──────────────────────────

## 回到"还没读完正文"的等待态（对应原版的「聆听常识流动中…」）
func _set_options_pending() -> void:
	_compacted_options = []
	for i in range(_option_buttons.size()):
		_option_buttons[i].disabled = true
		_set_option_text(i, "[·] 聆听常识流动中...")


func _rebuild_options(node_data: Dictionary) -> void:
	_compacted_options = _compact_options(node_data.get("options", []))
	for i in range(_option_buttons.size()):
		var button := _option_buttons[i]
		if i < _compacted_options.size():
			var entry: Dictionary = _compacted_options[i]
			# 先定 disabled 再写文字：文字颜色取决于禁用状态，顺序反了会取错色
			button.disabled = entry["disabled"]
			_set_option_text(i, "[%d] %s" % [i + 1, entry["text"]])
		else:
			button.disabled = true
			_set_option_text(i, "[%d] ---" % [i + 1])


## 选项按钮上的文字统一走这里：写到内嵌 Label，并同步它的颜色。
## 悬停/禁用时 Label 颜色要跟着按钮底色变，否则文字会糊在一起。
func _set_option_text(index: int, text: String) -> void:
	if index < 0 or index >= _option_labels.size():
		return
	_option_labels[index].text = text
	_apply_option_type_color(index, text)
	_apply_option_color(index, _option_buttons[index].is_hovered())


## 按动作类型给按钮定色：normal 换描边色，hover/pressed 直接拿类型色当底色。
## 类型取自文字里的「【探索】」这类前缀，配色表在 Palette.OPTION_TYPE_COLORS。
func _apply_option_type_color(index: int, text: String) -> void:
	if index < 0 or index >= _option_styles.size():
		return
	var color := Palette.option_type_color(text)
	_option_type_colors[index] = color
	# 已经探索过的选项：描边也压暗一档，和文字一起表示"这里翻过了"
	var border_color: Color = color.darkened(0.45) if _option_explored(index) else color
	_option_styles[index].border_color = border_color
	_option_hover_styles[index].bg_color = color
	_option_hover_styles[index].border_color = color


func _on_option_hover(index: int, entered: bool) -> void:
	_apply_option_color(index, entered)


## 按"是否悬停 / 是否禁用"给选项文字取色
func _apply_option_color(index: int, hovered: bool) -> void:
	if index < 0 or index >= _option_labels.size():
		return
	var label := _option_labels[index]
	var button := _option_buttons[index]
	if button.disabled:
		label.add_theme_color_override("font_color", Palette.DISABLED_FG)
	elif hovered:
		label.add_theme_color_override("font_color", Palette.BG)
	elif _option_explored(index):
		var explored_color: Color = _option_type_colors[index]
		label.add_theme_color_override("font_color", explored_color.darkened(0.45))
	else:
		label.add_theme_color_override("font_color", _option_type_colors[index])


## 这个选项是不是"已经翻过了"：查看类动作 + 它指向的房间已经到过。
##
## 但选项自己写了 relight 条件、且条件成立时，说明"再看一眼有新东西"——
## 这时候即使去过也要重新亮起来（拿到地窖钥匙之后的铁皮木箱就是这种）。
## 只有可选状态的选项才算——灰显占位本来就暗，不必再压一档。
func _option_explored(index: int) -> bool:
	if index < 0 or index >= _compacted_options.size():
		return false
	var entry: Dictionary = _compacted_options[index]
	if entry.get("disabled", false):
		return false
	var option: Dictionary = entry.get("option", {})
	if not Palette.option_is_explore(str(option.get("text", ""))):
		return false
	var target := str(option.get("target_room", ""))
	if target.is_empty() or target == str(GameEngine.state.room_id):
		return false
	if GameEngine.is_option_relit(option):
		return false
	return bool(GameEngine.get_flag("loc_visited_%s" % target, false))


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

	# 战斗：盖一层战斗界面，打完再刷新房间（对应 Python 版 select_option 的顺序）
	var battle_id := str(option.get("battle", ""))
	if not battle_id.is_empty():
		_open_battle(battle_id, option.get("post_battle", {}))
		return

	# 商店交易：打开交易界面，不刷新房间（与原版一致，交易完仍停在原画面）
	var shop_id := str(option.get("shop", ""))
	if not shop_id.is_empty():
		_open_shop(shop_id)
		return

	load_current_room()


## 生命归零就切到结局画面。返回 true 表示已经切换、调用方不要再刷新画面。
func _check_game_over() -> bool:
	if int(GameEngine.state.stats.get("hp", 1)) > 0:
		return false
	Fx.goto("res://scenes/GameOver.tscn")
	return true


func _append_stat_changes(effects: Dictionary) -> void:
	var changes: Array = GameEngine.resolve_stats_changes(effects)
	if changes.is_empty():
		return

	var parts: Array = []
	for change in changes:
		var key: String = change["key"]
		var stat_name: String = STATS_NAMES.get(key, key)
		# "直接回满"（如睡觉）不报数字，避免出现 +999 这种出戏的提示
		if change.get("to_max", false):
			parts.append("[color=#00ff88]%s 已回满[/color]" % stat_name)
			continue
		var delta := int(change["delta"])
		var sign_str := "+" if delta > 0 else ""
		# 腐化是越高越糟，颜色与其他属性相反
		var positive_is_good := key != "corruption"
		var color := "#00ff88" if (delta > 0) == positive_is_good else "#ff5555"
		parts.append("[color=%s]%s %s%d[/color]" % [color, stat_name, sign_str, delta])

	_append_history("✦ 状态变更: %s" % ", ".join(parts))


## ────────────────────────── 战斗 ──────────────────────────

## 盖一层战斗界面。战斗期间把本画面的快捷键关掉，避免 1~6 透传到选项上。
func _open_battle(enemy_id: String, post_battle: Dictionary) -> void:
	for child in get_children():
		if child is BattleScene:
			return   # 已经在战斗中，别叠第二层

	set_process_unhandled_key_input(false)
	get_viewport().gui_release_focus()

	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.finished.connect(_on_battle_finished)
	add_child(battle)
	battle.setup(enemy_id, post_battle)


## 战斗结束（胜利 / 逃跑 / 战败）后恢复快捷键并刷新房间。
## 战败时 load_current_room → _check_game_over 会自己切到结局画面。
func _on_battle_finished() -> void:
	set_process_unhandled_key_input(true)
	load_current_room()


## ────────────────────────── 弹窗基础设施 ──────────────────────────

## 实例化一个面板并入树，返回配置好的实例（尚未打开）。
## 默认走右侧抽屉；确认框 / 输入框传 GameModal.MODE_CENTER 走居中弹窗。
func _make_modal(title: String, accent: Color, width: float, body_height: float,
		mode: String = GameModal.MODE_DRAWER) -> GameModal:
	var modal := MODAL_SCENE.instantiate() as GameModal
	add_child(modal)
	modal.configure({
		"title": title,
		"accent": accent,
		"width": width,
		"body_height": body_height,
		"mode": mode,
	})
	return modal


## 压栈并打开。栈里已有面板时屏蔽下面那层的 ESC，避免一次按键关掉两层。
##
## 同一时间只显示一个抽屉：新抽屉打开时把旧抽屉滑出屏幕（保活、不销毁），
## 等新抽屉关闭时再由 _on_modal_closed 把它滑回来——这就是"返回上一层"的观感。
## 居中弹窗（确认框 / 输入框）是叠在抽屉之上的，不能把抽屉收起来。
func _push_modal(modal: GameModal) -> void:
	if not _modal_stack.is_empty():
		var top: GameModal = _modal_stack.back()
		top.input_blocked = true
		if modal.mode == GameModal.MODE_DRAWER and top.mode == GameModal.MODE_DRAWER:
			top.hide_for_stack()
	_modal_stack.append(modal)
	modal.closed.connect(_on_modal_closed.bind(modal))
	modal.open()


func _on_modal_closed(modal: GameModal) -> void:
	var idx := _modal_stack.find(modal)
	if idx != -1:
		_modal_stack.remove_at(idx)
	if not _modal_stack.is_empty():
		var top: GameModal = _modal_stack.back()
		top.input_blocked = false
		# 关掉的是一个抽屉 → 把被它顶下去的抽屉滑回来；
		# 关掉的是居中弹窗（确认框）→ 下面那个抽屉本来就还在，别重播滑入动画
		if modal.mode == GameModal.MODE_DRAWER and top.mode == GameModal.MODE_DRAWER:
			top.show_from_stack()
	if modal == _inv_modal:
		_inv_modal = null
		_inv_list_box = null
		_inv_detail = null
		_inv_actions = null
		_inv_status = null
		_inv_tab_btns = []
		_inv_filter_btns = []
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
		_diary_filter_btns = []
	if modal == _codex_modal:
		_codex_modal = null
		_codex_list_box = null
		_codex_detail = null
		_codex_filter_btns = []


## 一次性收掉所有面板（读档成功后用）。
## 抽屉是"滑出动画放完才 emit closed"的，栈不会同步清空，所以先取快照再清栈，
## 否则 while + back().close() 会因为栈始终没变化而空转。
func _close_all_modals() -> void:
	var stack: Array[GameModal] = _modal_stack.duplicate()
	_modal_stack.clear()
	for modal in stack:
		modal.input_blocked = false
		modal.close()


## 轻量确认框，居中叠在当前面板之上；确认后执行 on_confirm
func _open_confirm(title: String, message: String, on_confirm: Callable,
		accent: Color = GameModal.ACCENT_PINK) -> void:
	var modal := _make_modal(title, accent, 460.0, 60.0, GameModal.MODE_CENTER)
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

## 让 ScrollContainer 里的内容不吞滚轮事件。
## 容器和按钮默认是 STOP，滚轮会被它们吃掉，列表就滚不动了；统一改成 PASS，
## 事件会继续上传到 ScrollContainer 去滚动。按钮用 PASS 仍然能正常点击。
func _make_scroll_friendly(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_PASS
		_make_scroll_friendly(child)


## 建一个纵向可滚动的列表容器，返回 (scroll, 内部的 VBox)
## 详见 _make_scroll_friendly 的注释：里面每一项都要 PASS，滚轮才传得出去。
func _make_list_scroll(size: Vector2) -> Array:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(box)
	return [scroll, box]


## ────────────────────────── 分类筛选条（背包 / 日记共用） ──────────────────────────

## 背包与「地上」的分类：【id, 显示名】。id 只是分组名，真正判定看 INV_FILTER_TYPES。
const INV_FILTERS: Array = [
	["all", "全部"],
	["equip", "装备"],
	["consumable", "消耗品"],
	["key", "钥匙"],
	["quest", "任务"],
	["misc", "其他"],
]
## 每种筛选收纳的物品类型集合（物品库里的 type 字段）。"all" 不在表内，代表不过滤。
const INV_FILTER_TYPES: Dictionary = {
	"equip": ["weapon", "armor"],
	"consumable": ["consumable"],
	"key": ["key"],
	"quest": ["quest"],
	"misc": ["material", "misc"],
}

## 日记的分类：任务与笔记本来就是两类，再留一个「全部」。
const DIARY_FILTERS: Array = [
	["all", "全部"],
	["task", "任务"],
	["note", "笔记"],
]


## 建一排分类筛选按钮（自动换行）。entries 为 [[id, 显示名], ...]，
## 点某个按钮时调 on_pick.call(id)。返回 [按钮容器, 按钮数组]。
func _make_filter_bar(entries: Array, on_pick: Callable) -> Array:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	var buttons: Array[Button] = []
	for entry in entries:
		var btn := Button.new()
		btn.text = str(entry[1])
		btn.custom_minimum_size = Vector2(84, 28)
		btn.pressed.connect(on_pick.bind(str(entry[0])))
		row.add_child(btn)
		buttons.append(btn)
	return [row, buttons]


## 刷新筛选条：当前分类用强调色、其余压成次级色（与「背包 / 地上」分区同理）。
func _refresh_filter_bar(modal: GameModal, entries: Array, buttons: Array,
		current: String, accent: Color) -> void:
	if modal == null:
		return
	for i in range(buttons.size()):
		var on: bool = str(entries[i][0]) == current
		var btn: Button = buttons[i]
		modal.style_button(btn, accent if on else GameModal.MUTED)


## 筛选出的物品是否命中当前分类
func _inv_item_matches_filter(item: Dictionary) -> bool:
	if _inv_filter == "all":
		return true
	var types: Array = INV_FILTER_TYPES.get(_inv_filter, [])
	return types.has(str(item.get("type", "misc")))


func _open_inventory() -> void:
	var modal := _make_modal("物品栏", GameModal.ACCENT_CYAN, 780.0, 380.0)
	_inv_modal = modal
	_inv_selected = 0
	_inv_tab = "bag"
	_inv_filter = "all"

	# 顶部分区切换：背包（含已装备）/ 地上（本房间丢下的东西）
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	_inv_tab_btns = []
	for entry in [["bag", "背包"], ["ground", "地上"]]:
		var tab_btn := Button.new()
		tab_btn.custom_minimum_size = Vector2(140, 30)
		tab_btn.pressed.connect(_switch_inv_tab.bind(entry[0]))
		tabs.add_child(tab_btn)
		_inv_tab_btns.append(tab_btn)
	modal.add_node(tabs)

	# 分类筛选条：按物品类型把列表收窄
	var filter_pair := _make_filter_bar(INV_FILTERS, _switch_inv_filter)
	_inv_filter_btns = filter_pair[1]
	modal.add_node(filter_pair[0])

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 左：物品列表（可滚动）
	var scroll_pair := _make_list_scroll(Vector2(260, 280))
	main.add_child(scroll_pair[0])
	_inv_list_box = scroll_pair[1]

	# 右：详情 + 操作按钮 + 反馈
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)

	_inv_detail = RichTextLabel.new()
	_inv_detail.bbcode_enabled = true
	_inv_detail.scroll_active = true
	_inv_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inv_detail.add_theme_color_override("default_color", GameModal.BODY_TEXT)
	right.add_child(_inv_detail)

	# 操作按钮排成一行：按选中物品的类型动态显示（装备/卸下、使用、丢弃、捡起）
	_inv_actions = HBoxContainer.new()
	_inv_actions.add_theme_constant_override("separation", 8)
	right.add_child(_inv_actions)

	_inv_status = Label.new()
	_inv_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inv_status.add_theme_color_override("font_color", GameModal.MUTED)
	right.add_child(_inv_status)

	main.add_child(right)
	modal.add_node(main)

	modal.add_text("铜币: %d" % int(GameEngine.state.stats.get("coins", 0)), GameModal.ACCENT_GOLD)
	modal.add_text("提示：点左侧物品，再用右侧按钮操作；丢弃的东西会掉在地上，切到「地上」可以捡回。",
		GameModal.MUTED)
	modal.add_action("close", "[ESC] 关闭")
	modal.action_pressed.connect(func(id: String) -> void:
		if id == "close":
			modal.close()
	)

	_refresh_inventory()
	_push_modal(modal)


## 切换「背包 / 地上」分区
func _switch_inv_tab(tab: String) -> void:
	if _inv_tab == tab:
		return
	_inv_tab = tab
	_inv_selected = 0
	_set_inv_status("", true)
	_refresh_inventory()


## 切换分类筛选（切分区不重置，背包与地上用同一套分类）
func _switch_inv_filter(filter_id: String) -> void:
	if _inv_filter == filter_id:
		return
	_inv_filter = filter_id
	_inv_selected = 0
	_set_inv_status("", true)
	_refresh_inventory()


## 主界面上的提示行：成功用绿色、失败用红色
func _set_inv_status(message: String, ok: bool = true) -> void:
	if _inv_status == null:
		return
	_inv_status.text = message
	_inv_status.add_theme_color_override(
		"font_color", Palette.GREEN if ok else Palette.RED)


## 背包分区的条目：先列已装备的（方便快捷卸下），再列背包里的
func _bag_entries() -> Array:
	var result: Array = []
	var equipment := GameEngine.get_equipment()
	for slot in equipment:
		var entry: Dictionary = equipment[slot]
		var item_def := GameEngine.get_item_def(entry.get("item_id", ""))
		result.append({
			"id": entry.get("item_id", ""),
			"name": entry.get("name", ""),
			"desc": item_def.get("desc", ""),
			"type": item_def.get("type", "misc"),
			"qty": 1,
			"equipped": true,
			"slot": slot,
		})
	for item in GameEngine.inv_mgr.all():
		var copy: Dictionary = item.duplicate(true)
		copy["equipped"] = false
		result.append(copy)
	return result


func _refresh_inventory() -> void:
	if _inv_tab == "ground":
		_inv_items = GameEngine.get_ground_items()
	else:
		_inv_items = _bag_entries()
	if _inv_filter != "all":
		_inv_items = _inv_items.filter(_inv_item_matches_filter)

	_refresh_inv_tabs()
	_refresh_filter_bar(_inv_modal, INV_FILTERS, _inv_filter_btns, _inv_filter, GameModal.ACCENT_CYAN)

	for child in _inv_list_box.get_children():
		_inv_list_box.remove_child(child)
		child.queue_free()

	if _inv_items.is_empty():
		var empty := Label.new()
		empty.text = _empty_inv_text()
		empty.add_theme_color_override("font_color", GameModal.MUTED)
		_inv_list_box.add_child(empty)
		_inv_detail.text = ""
		_clear_inv_actions()
		return

	for i in range(_inv_items.size()):
		var item: Dictionary = _inv_items[i]
		var qty := int(item.get("qty", 1))
		var label: String = str(item.get("name", "???"))
		if item.get("equipped", false):
			label += "【已装备】"
		elif qty > 1:
			label += " x%d" % qty
		var btn := Button.new()
		btn.text = label
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 30)
		_inv_modal.style_button(btn, GameModal.ACCENT_CYAN)
		btn.add_theme_color_override("font_color",
			GameModal.ACCENT_CYAN if i == _inv_selected else GameModal.MUTED)
		btn.pressed.connect(_select_inventory_item.bind(i))
		_inv_list_box.add_child(btn)

	_inv_selected = clampi(_inv_selected, 0, _inv_items.size() - 1)
	_show_inventory_detail(_inv_selected)
	_make_scroll_friendly(_inv_list_box)   # 列表项要 PASS，滚轮才滚得动


## 分区按钮的选中态：当前分区用青色实底，另一个保持暗底
func _refresh_inv_tabs() -> void:
	var counts := {"bag": _bag_count_hint(), "ground": GameEngine.get_ground_items().size()}
	for i in range(_inv_tab_btns.size()):
		var tab_id: String = ["bag", "ground"][i]
		var btn := _inv_tab_btns[i]
		btn.text = ("背包" if tab_id == "bag" else "地上") + "（%d）" % int(counts[tab_id])
		_inv_modal.style_button(btn, GameModal.ACCENT_CYAN if tab_id == _inv_tab else GameModal.MUTED)


func _bag_count_hint() -> int:
	return GameEngine.inv_mgr.all().size() + GameEngine.get_equipment().size()


## 列表为空时的提示语：区分「真的没东西」和「只是被分类筛掉了」
func _empty_inv_text() -> String:
	if _inv_filter != "all":
		return "（这个分类下没有东西）"
	return "（地上空空的）" if _inv_tab == "ground" else "（背包空空如也）"


func _select_inventory_item(index: int) -> void:
	_inv_selected = index
	_set_inv_status("", true)   # 换一件物品就清掉上一条操作提示
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
	var lines: Array = [
		"[b][color=#66fcf1]%s[/color][/b]" % item.get("name", "???"),
		"[color=#ffaa00]类型: %s[/color]" % GameEngine.inv_mgr.type_name(item.get("type", "misc")),
		"[color=#ffaa00]数量: %d[/color]" % int(item.get("qty", 1)),
	]
	if item.get("equipped", false):
		lines.append("[color=#ddaa00]状态: 已装备[/color]")
	lines.append("")
	lines.append("[color=#b2b2b2]%s[/color]" % item.get("desc", "(无描述)"))
	_inv_detail.text = "\n".join(lines)

	_rebuild_inv_actions(item, index)


## 按选中物品的类型，重建这一排可用操作。可用什么就显示什么，避免出现灰按钮。
func _rebuild_inv_actions(item: Dictionary, index: int) -> void:
	_clear_inv_actions()

	# 地上的东西：只有一个动作，捡回来。
	# 注意用的是 ground_index（原始地面列表下标）而不是列表下标——
	# 分类筛选之后两者不再相等，用列表下标会捡错东西。
	if item.get("ground", false):
		_add_inv_action("捡起", GameModal.ACCENT_GREEN,
			func() -> void: _pick_up_ground(int(item.get("ground_index", index))))
		return

	# 已装备的：只能卸下
	if item.get("equipped", false):
		_add_inv_action("卸下", GameModal.ACCENT_AMBER,
			func() -> void: _unequip_from_inv(str(item.get("slot", ""))))
		return

	var item_id: String = str(item.get("id", ""))
	var item_def := GameEngine.get_item_def(item_id)
	if item_def.has("equip_slot"):
		_add_inv_action("装备", GameModal.ACCENT_AMBER,
			func() -> void: _equip_from_inv(item_id))
	if not item_def.get("effect", {}).is_empty():
		_add_inv_action("使用", GameModal.ACCENT_GREEN,
			func() -> void: _use_from_inv(item_id))
	# 任务物品与钥匙不可丢弃（与原 Python 版一致）
	var is_important: bool = item.get("type") == "quest" or item.get("type") == "key" \
		or item.get("is_important", false)
	if not is_important:
		_add_inv_action("丢弃", Palette.RED,
			func() -> void: _discard_selected_item())
	elif _inv_status.text.is_empty():
		# 重要物品没有任何可用操作，给一句中性说明（不覆盖刚发生的操作反馈）
		_inv_status.text = "重要物品不能丢弃。"
		_inv_status.add_theme_color_override("font_color", GameModal.MUTED)


func _add_inv_action(label: String, accent: Color, on_pressed: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 34)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_modal.style_button(btn, accent)
	btn.pressed.connect(on_pressed)
	_inv_actions.add_child(btn)


func _clear_inv_actions() -> void:
	if _inv_actions == null:
		return
	for child in _inv_actions.get_children():
		_inv_actions.remove_child(child)
		child.queue_free()


## 在物品栏里直接装备（成功后该物品会移到「已装备」区）
func _equip_from_inv(item_id: String) -> void:
	var result := GameEngine.equip(item_id)
	_set_inv_status(str(result.get("message", "")), result.get("success", false))
	_refresh_inventory()


## 在物品栏里直接卸下
func _unequip_from_inv(slot: String) -> void:
	var result := GameEngine.unequip(slot)
	_set_inv_status(str(result.get("message", "")), result.get("success", false))
	_refresh_inventory()


## 在物品栏里使用消耗品
func _use_from_inv(item_id: String) -> void:
	var result := GameEngine.use_item(item_id)
	_set_inv_status(str(result.get("message", "")), result.get("success", false))
	_refresh_inventory()


## 从地上捡回
func _pick_up_ground(index: int) -> void:
	var result := GameEngine.pick_up_ground_item(index)
	_set_inv_status(str(result.get("message", "")), result.get("success", false))
	_refresh_inventory()


## 丢弃：不是删除，而是掉到当前房间的地上，之后还能在「地上」分区捡回来
func _discard_selected_item() -> void:
	if _inv_tab != "bag" or _inv_selected < 0 or _inv_selected >= _inv_items.size():
		return
	var item: Dictionary = _inv_items[_inv_selected]
	if item.get("equipped", false):
		return
	var result := GameEngine.drop_to_ground(item)
	var ok: bool = result.get("success", false)
	if ok:
		_set_inv_status("已丢弃「%s」——它掉在了地上，可在「地上」分区捡回。" % item.get("name", ""), true)
	else:
		_set_inv_status(str(result.get("message", "丢弃失败。")), false)
	_refresh_inventory()


## ────────────────────────── 装备 ──────────────────────────

const EQUIP_SLOT_NAMES: Dictionary = {"weapon": "武器", "armor": "防具", "accessory": "饰品"}
const EQUIP_STAT_NAMES: Dictionary = {"attack": "攻击", "defense": "防御", "intelligence": "智力", "agility": "敏捷"}


func _open_equipment() -> void:
	var modal := _make_modal("装备", GameModal.ACCENT_AMBER, 560.0, 300.0)
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
		"width": 560.0, "body_height": 300.0})

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
	var modal := _make_modal("保存游戏", GameModal.ACCENT_GOLD, 560.0, 50.0)
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
	var modal := _make_modal("读取存档", GameModal.ACCENT_GREEN, 560.0, 50.0)
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
	var modal := _make_modal("设置", GameModal.ACCENT_GOLD, 560.0, 420.0)
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
		"width": 560.0, "body_height": 420.0})
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
	Fx.goto("res://scenes/MainMenu.tscn")


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
	var modal := _make_modal(str(shop.get("name", "商店")), ACCENT_SHOP, 780.0, 330.0)
	_shop_modal = modal

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 左：商品列表
	var scroll_pair := _make_list_scroll(Vector2(300, 290))
	main.add_child(scroll_pair[0])
	_shop_list_box = scroll_pair[1]

	# 右：商品详情
	_shop_detail = RichTextLabel.new()
	_shop_detail.bbcode_enabled = true
	_shop_detail.scroll_active = true
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
	_make_scroll_friendly(_shop_list_box)


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


## 背包里进了新东西（购买 / 掉落 / 剧情奖励）：让"物品"按钮被注意到一下
func _on_item_added(_item_id: String) -> void:
	Fx.attention(_btn_inventory, Palette.CYAN)


## 有未读任务/笔记时让日记按钮缓慢呼吸（比原来 0.4 秒一次的硬闪耐看）。
## 只在 0→1 的那一次撒一把粒子，之后保持轻微起伏，不会一直抢注意力。
func _set_diary_flash(on: bool) -> void:
	if on == _diary_flash_on:
		return
	_diary_flash_on = on

	if _diary_flash_tween != null and _diary_flash_tween.is_valid():
		_diary_flash_tween.kill()
	_diary_flash_tween = null
	_btn_diary.modulate = Color.WHITE
	if not on:
		return

	Fx.sparkle(_btn_diary, ACCENT_DIARY)
	_diary_flash_tween = create_tween().set_loops()
	_diary_flash_tween.tween_property(_btn_diary, "modulate:a", 0.6, 1.1) \
		.set_trans(Tween.TRANS_SINE)
	_diary_flash_tween.tween_property(_btn_diary, "modulate:a", 1.0, 1.1) \
		.set_trans(Tween.TRANS_SINE)


func _open_diary() -> void:
	if _btn_diary.disabled:
		return
	# 打开即视为已读（与原版 on_mount 一致）
	GameEngine.set_flag("sys_diary_unread", false)
	_set_diary_flash(false)

	_diary_selected = 0
	_diary_filter = "all"
	var modal := _make_modal("日 记", ACCENT_DIARY, 780.0, 330.0)
	_diary_modal = modal

	# 分类筛选条：全部 / 任务 / 笔记
	var filter_pair := _make_filter_bar(DIARY_FILTERS, _switch_diary_filter)
	_diary_filter_btns = filter_pair[1]
	modal.add_node(filter_pair[0])

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var scroll_pair := _make_list_scroll(Vector2(250, 290))
	main.add_child(scroll_pair[0])
	_diary_list_box = scroll_pair[1]

	_diary_detail = RichTextLabel.new()
	_diary_detail.bbcode_enabled = true
	_diary_detail.scroll_active = true
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


## 切换日记分类（全部 / 任务 / 笔记）
func _switch_diary_filter(filter_id: String) -> void:
	if _diary_filter == filter_id:
		return
	_diary_filter = filter_id
	_diary_selected = 0
	_rebuild_diary_entries()


func _rebuild_diary_entries() -> void:
	for child in _diary_list_box.get_children():
		_diary_list_box.remove_child(child)
		child.queue_free()

	_refresh_filter_bar(_diary_modal, DIARY_FILTERS, _diary_filter_btns, _diary_filter, ACCENT_DIARY)

	_diary_entries = []
	var diary: Dictionary = GameEngine.state.diary
	var tasks: Array = diary.get("tasks", [])
	var notes: Array = diary.get("notes", [])
	var show_tasks: bool = _diary_filter != "note"
	var show_notes: bool = _diary_filter != "task"

	if show_tasks and not tasks.is_empty():
		_diary_list_box.add_child(_make_section_header("── 任务 ──"))
		for task in tasks:
			_diary_entries.append({"type": "task", "data": task})
			var label := str(task.get("title", "???"))
			if task.get("done", false):
				label = "✓ " + label
			_diary_list_box.add_child(_make_entry_button(_diary_entries.size() - 1, label))

	if show_notes and not notes.is_empty():
		_diary_list_box.add_child(_make_section_header("── 笔记 ──"))
		for note in notes:
			_diary_entries.append({"type": "note", "data": note})
			_diary_list_box.add_child(_make_entry_button(_diary_entries.size() - 1, str(note.get("title", "???"))))

	if _diary_entries.is_empty():
		var empty := Label.new()
		empty.text = "（日记还是空的）" if _diary_filter == "all" else "（这个分类下没有内容）"
		empty.add_theme_color_override("font_color", GameModal.MUTED)
		_diary_list_box.add_child(empty)
		_diary_detail.text = ""
		_diary_track_btn.disabled = true
		_diary_delete_btn.disabled = true
		_make_scroll_friendly(_diary_list_box)
		return

	_diary_selected = clampi(_diary_selected, 0, _diary_entries.size() - 1)
	_select_diary_entry(_diary_selected)
	_make_scroll_friendly(_diary_list_box)   # 列表项要 PASS，滚轮才滚得动


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
	var modal := _make_modal("新建笔记", ACCENT_DIARY, 580.0, 60.0, GameModal.MODE_CENTER)
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


## ────────────────────────── 百科（游戏内 wiki） ──────────────────────────

## 打开百科：左侧按分类列词条，右侧读正文。没解锁的条目只显示「？？？」。
## 数据全在 data/codex.json，解锁条件是该词条的 unlock flag。
func _open_codex() -> void:
	_codex_selected = 0
	_codex_filter = "all"
	_codex_modal = _make_modal("百 科", ACCENT_CODEX, 780.0, 360.0)

	var filter_pair := _make_filter_bar(_codex_filter_defs(), _switch_codex_filter)
	_codex_filter_btns = filter_pair[1]
	_codex_modal.add_node(filter_pair[0])

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var scroll_pair := _make_list_scroll(Vector2(250, 300))
	main.add_child(scroll_pair[0])
	_codex_list_box = scroll_pair[1]

	_codex_detail = RichTextLabel.new()
	_codex_detail.bbcode_enabled = true
	_codex_detail.scroll_active = true
	_codex_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_codex_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_codex_detail.add_theme_color_override("default_color", GameModal.BODY_TEXT)
	main.add_child(_codex_detail)

	_codex_modal.add_node(main)

	var progress: Array = GameEngine.get_codex_progress()
	_codex_modal.add_text("已收录 %d / %d 条。" % [int(progress[0]), int(progress[1])], GameModal.MUTED)
	_codex_modal.add_action("close", "[ESC] 关闭")
	_codex_modal.action_pressed.connect(func(id: String) -> void:
		if id == "close":
			_codex_modal.close()
	)

	_rebuild_codex_entries()
	_push_modal(_codex_modal)


## 百科分类筛选条的定义：全部 + codex.json 里的分类
func _codex_filter_defs() -> Array:
	var defs: Array = [["all", "全部"]]
	for cat in GameEngine.get_codex_categories():
		if not (cat is Dictionary):
			continue
		defs.append([str(cat.get("id", "")), str(cat.get("name", ""))])
	return defs


func _switch_codex_filter(filter_id: String) -> void:
	if _codex_filter == filter_id:
		return
	_codex_filter = filter_id
	_codex_selected = 0
	_rebuild_codex_entries()


func _rebuild_codex_entries() -> void:
	for child in _codex_list_box.get_children():
		_codex_list_box.remove_child(child)
		child.queue_free()

	_refresh_filter_bar(_codex_modal, _codex_filter_defs(), _codex_filter_btns, _codex_filter, ACCENT_CODEX)

	_codex_entries = []
	for entry in GameEngine.get_codex_entries():
		if not (entry is Dictionary):
			continue
		if _codex_filter != "all" and str(entry.get("category", "")) != _codex_filter:
			continue
		_codex_entries.append(entry)
		var unlocked: bool = GameEngine.is_codex_unlocked(entry)
		var label := str(entry.get("title", "???")) if unlocked else "？？？"
		_codex_list_box.add_child(_make_codex_entry_button(_codex_entries.size() - 1, label, unlocked))

	if _codex_entries.is_empty():
		var empty := Label.new()
		empty.text = "（这个分类下还没有条目）"
		empty.add_theme_color_override("font_color", GameModal.MUTED)
		_codex_list_box.add_child(empty)
		_codex_detail.text = ""
		_make_scroll_friendly(_codex_list_box)
		return

	_codex_selected = clampi(_codex_selected, 0, _codex_entries.size() - 1)
	_select_codex_entry(_codex_selected)
	_make_scroll_friendly(_codex_list_box)   # 列表项要 PASS，滚轮才滚得动


func _make_codex_entry_button(index: int, text: String, unlocked: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	# 未解锁的条目留在列表里，但压成灰、点不动——让玩家知道"这里还有东西"
	btn.disabled = not unlocked
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 30)
	_codex_modal.style_button(btn, ACCENT_CODEX)
	btn.add_theme_color_override("font_color",
		ACCENT_CODEX if index == _codex_selected else GameModal.MUTED)
	btn.pressed.connect(_select_codex_entry.bind(index))
	return btn


func _select_codex_entry(index: int) -> void:
	if index < 0 or index >= _codex_entries.size():
		return
	_codex_selected = index
	var entry_index := 0
	for child in _codex_list_box.get_children():
		if not (child is Button):
			continue
		child.add_theme_color_override("font_color",
			ACCENT_CODEX if entry_index == index else GameModal.MUTED)
		entry_index += 1
	_show_codex_detail(index)


func _show_codex_detail(index: int) -> void:
	var entry: Dictionary = _codex_entries[index]
	if not GameEngine.is_codex_unlocked(entry):
		_codex_detail.text = "\n".join(PackedStringArray([
			"[b][color=#888888]？？？[/color][/b]",
			"",
			"[color=#888888]这条记录还没有被唤醒。去这个世界里多走一走、多看一看。[/color]",
		]))
		return

	var lines := PackedStringArray([
		"[b][color=#5aa9ff]%s[/color][/b]" % str(entry.get("title", "???")),
	])
	var subtitle := str(entry.get("subtitle", ""))
	if not subtitle.is_empty():
		lines.append("[color=#888888]%s[/color]" % subtitle)
	lines.append("")
	lines.append(Palette.render(str(entry.get("body", ""))))
	_codex_detail.text = "\n".join(lines)