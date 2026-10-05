extends Control
## 结局（阵亡）画面：红色边框渐亮 + 文字渐红，可返回主菜单。
## 对应 Python 的 view/game_over_screen.py。

const MAIN_MENU := "res://scenes/MainMenu.tscn"

const DARK := Color(0.043137, 0.047059, 0.062745)   # #0b0c10
const BOX_BG := Color(0.101961, 0.039216, 0.039216) # #1a0a0a
const RED := Color(1, 0, 0)
const DIM_RED := Color(0.4, 0.2, 0.2)

var _sb: StyleBoxFlat = null
var _title: Label = null
var _text: Label = null
var _btn: Button = null
## 是否已经点过"返回主菜单"。回车和按钮都能触发，加个哨兵防止连点重复重置。
var _went := false


func _ready() -> void:
	# 全屏控件默认会拦截鼠标：设成忽略后，点画面任意处=回车。
	# 面板里的按钮不受影响——它在最上层，会先拿到点击。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_play()


func _unhandled_input(event: InputEvent) -> void:
	var key_ok: bool = event is InputEventKey and event.pressed and not event.echo \
		and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	var click_ok: bool = event is InputEventMouseButton and event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT
	if key_ok or click_ok:
		get_viewport().set_input_as_handled()
		_return_menu()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = DARK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	Fx.add_ambient(self, Color(1.0, 0.25, 0.15, 0.22), 26)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sb = StyleBoxFlat.new()
	_sb.bg_color = BOX_BG
	_sb.border_color = Color(0.2, 0.2, 0.2)
	_sb.set_border_width_all(2)
	_sb.set_corner_radius_all(4)
	_sb.content_margin_left = 28
	_sb.content_margin_right = 28
	_sb.content_margin_top = 24
	_sb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", _sb)
	center.add_child(panel)
	Fx.pop_in(panel, 0.0, 0.45)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	_title = Label.new()
	_title.text = "你 已 阵 亡"
	_title.theme_type_variation = &"Heading"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Color(0.4, 0.2, 0.2))
	box.add_child(_title)

	_text = Label.new()
	_text.text = "你的冒险到此为止。\n\n黑暗吞噬了你的意识，\n辉光从你的指尖悄然流逝……"
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.add_theme_color_override("font_color", Color(0.4, 0.266667, 0.266667))
	box.add_child(_text)

	_btn = Button.new()
	_btn.text = "[ 返回主菜单 ]"
	_btn.custom_minimum_size = Vector2(0, 40)
	_btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.133333, 0.066667, 0.066667)))
	_btn.add_theme_stylebox_override("hover", _make_stylebox(Color(0.8, 0, 0)))
	_btn.add_theme_stylebox_override("pressed", _make_stylebox(Color(0.8, 0, 0)))
	_btn.add_theme_stylebox_override("focus", _make_stylebox(Color(0.133333, 0.066667, 0.066667)))
	_btn.add_theme_color_override("font_color", Color(0.4, 0.2, 0.2))
	_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	_btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	_btn.pressed.connect(_return_menu)
	box.add_child(_btn)


func _make_stylebox(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.set_corner_radius_all(3)
	return sb


func _play() -> void:
	var border := create_tween()
	border.tween_method(func(c: Color) -> void: _sb.border_color = c, Color(0.2, 0.2, 0.2), RED, 1.2)
	await border.finished
	await get_tree().create_timer(0.5).timeout

	var tint := create_tween()
	tint.tween_method(_tint, DIM_RED, RED, 1.5)


## 标题与按钮渐红，正文比它们暗一档，免得太刺眼
func _tint(c: Color) -> void:
	_title.add_theme_color_override("font_color", c)
	_btn.add_theme_color_override("font_color", c)
	_text.add_theme_color_override("font_color", Color(c.r * 0.7, c.g * 0.8, c.b * 0.8))


func _return_menu() -> void:
	if _went:
		return
	_went = true
	GameEngine.reset_game()
	Fx.goto(MAIN_MENU)
