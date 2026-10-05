extends Control
## 苏醒：暗框的边框由灰渐亮成青色，然后进入主玩法。
## 对应 Python 的 view/brighten_screen.py。
## 途中按 Enter / 空格 / 鼠标左键可以跳过。

const GAMEPLAY := "res://scenes/GamePlay.tscn"

const BORDER_DARK := Color(0.2, 0.2, 0.2)        # #333333
const BORDER_BRIGHT := Color(0.271, 0.867, 1.0)  # #45ddff

var _skipped := false
var _went := false
var _bright_done := false


func _ready() -> void:
	# 全屏控件默认会拦截鼠标，设成忽略，点击才能落到 _unhandled_input
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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


func _build_ui() -> StyleBoxFlat:
	var bg := ColorRect.new()
	bg.color = Color(0.043137, 0.047059, 0.062745)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	Fx.add_ambient(self, Color(0.27, 0.95, 1.0, 0.18), 26)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 200)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.101961, 0.101961, 0.101961)
	sb.border_color = BORDER_DARK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	Fx.pop_in(panel, 0.0, 0.4)

	var label := Label.new()
	label.text = "..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.333333, 0.333333, 0.333333))
	panel.add_child(label)

	return sb


func _play() -> void:
	var sb := _build_ui()

	var tw := create_tween()
	tw.tween_method(func(c: Color) -> void: sb.border_color = c, BORDER_DARK, BORDER_BRIGHT, 1.0)
	tw.finished.connect(func() -> void: _bright_done = true)
	while not _bright_done and not _skipped:
		await get_tree().process_frame
	tw.kill()
	sb.border_color = BORDER_BRIGHT

	if not _skipped:
		await get_tree().create_timer(0.3).timeout

	# 第一次进游戏才播苏醒独白
	if not GameEngine.get_flag("intro_monologue_done", false):
		GameEngine.state.dialogue_id = "intro_wake_1"
	_go()


func _go() -> void:
	if _went:
		return
	_went = true
	Fx.goto(GAMEPLAY)
