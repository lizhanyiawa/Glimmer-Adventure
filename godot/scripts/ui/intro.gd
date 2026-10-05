extends Control
## 开场引导：黑屏跑码 → 打出标题 → 自动进主菜单。
## 对应 Python 的 view/intro_screen.py。
##
## 设置里勾了「跳过开场动画」就直接进主菜单；
## 动画途中按 Enter / 空格 / 鼠标左键可以快进到结尾。

const MAIN_MENU := "res://scenes/MainMenu.tscn"

## 跑码文本：[说明, 结果]。结果非空时挑成青色高亮，读起来才像终端在输出。
const BOOT_LINES: Array = [
	["CONNECTING TO OUTSIDER SERVER...", ""],
	["DECODING REINCARNATION PROTOCOL...", "[ OK ]"],
	["STABILIZING ISEKAI ENERGY WELL...", "[ 100% ]"],
]

var _log: RichTextLabel = null
var _title_box: VBoxContainer = null
var _hint: Label = null
var _skipped := false
var _went := false


func _ready() -> void:
	# 全屏控件默认会拦截鼠标，设成忽略，点击才能落到 _unhandled_input
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	if GameEngine.settings.get("skip_intro", false):
		_go()
		return
	_play()


func _unhandled_input(event: InputEvent) -> void:
	if _skipped:
		return
	if _is_advance_event(event):
		_skipped = true
		get_viewport().set_input_as_handled()


func _is_advance_event(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		return event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		return true
	return false


func _build_ui() -> void:
	# 背景：纵向渐变 + 一层飘浮尘埃，避免整块死黑，也让后面切到主菜单时更连贯
	Fx.add_backdrop(self, Color("0a0e18"), Color("05060a"))
	Fx.add_ambient(self, Color(0.27, 0.95, 1.0, 0.12), 28)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(column)

	# ── 跑码区 ──
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = true
	_log.scroll_active = false
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.custom_minimum_size = Vector2(560, 96)
	_log.add_theme_color_override("default_color", Color("5a6472"))
	column.add_child(_log)
	Fx.fade_in(_log, 0.0, 0.5)

	# ── 标题区（先建好藏起来，跑完码再逐行淡入）──
	_title_box = VBoxContainer.new()
	_title_box.add_theme_constant_override("separation", 14)
	_title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_box.visible = false
	column.add_child(_title_box)

	var title := Label.new()
	title.text = "THE ADVENTURE"
	title.theme_type_variation = &"Heading"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Palette.CYAN)
	_title_box.add_child(title)

	var rule := ColorRect.new()
	# 半透明写进 color 而不是 modulate，modulate 要留给淡入动画用
	rule.color = Color(Palette.CYAN_DEEP, 0.55)
	rule.custom_minimum_size = Vector2(320, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title_box.add_child(rule)

	var subtitle := Label.new()
	subtitle.text = "—— 冒 险 ——"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Palette.GOLD)
	_title_box.add_child(subtitle)

	# 底部跳过提示。放晚一点淡入，免得一进画面就抢注意力
	_hint = Label.new()
	_hint.text = "按 Enter / 空格 跳过"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Palette.DIM)
	column.add_child(_hint)
	Fx.fade_in(_hint, 1.3, 0.8)


func _play() -> void:
	var shown := ""
	for pair in BOOT_LINES:
		shown += _render_log_line(pair) + "\n"
		_log.text = "[center]%s[/center]" % shown
		await _wait(0.42)
		if _skipped:
			break

	_show_title()

	if _skipped:
		await get_tree().create_timer(0.35).timeout
	else:
		await _wait(1.7)
	_go()


## 把一行日志染成「暗色说明 + 青色结果」。颜色统一从 Palette 取，
## 这里不再散一份色值；方括号要转义，否则会被 RichTextLabel 当成 BBCode 吞掉。
func _render_log_line(pair: Array) -> String:
	var body := "[color=#%s]%s[/color]" % [Palette.MUTED.to_html(false), str(pair[0])]
	var result := str(pair[1])
	if result.is_empty():
		return body
	return "%s [color=#%s][b]%s[/b][/color]" % [
		body, Palette.CYAN.to_html(false), result.replace("[", "[lb]")]


func _show_title() -> void:
	_log.visible = false
	_title_box.visible = true
	# 标题 / 分隔线 / 副标题逐个淡入，比整块跳出来有节奏
	for i in _title_box.get_child_count():
		Fx.fade_in(_title_box.get_child(i), 0.09 * i, 0.45)


func _go() -> void:
	if _went:
		return
	_went = true
	Fx.goto(MAIN_MENU)


## 等待 sec 秒；被快进就立刻返回
func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec and not _skipped:
		await get_tree().process_frame
		t += get_process_delta_time()
