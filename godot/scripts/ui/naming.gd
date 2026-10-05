extends Control
## 起名界面。对应 Python 的 view/naming_screen.py。
##
## 校验规则照搬：中文 ≤16 个 / 其它字符 ≤32 个，禁止引号、反斜杠、控制字符。
## 确认后写入引擎，进入转场独白。

const TRANSITION := "res://scenes/Transition.tscn"
const MAIN_MENU := "res://scenes/MainMenu.tscn"

const MAX_CJK := 16
const MAX_ASCII := 32

const DARK := Color(0.043137, 0.047059, 0.062745)
const PANEL := Color(0.086275, 0.098039, 0.137255)
const CYAN := Color(0, 1, 1)                     # #00ffff
const CYAN_TEXT := Color(0.4, 0.988235, 0.945098)
const ERR := Color(1, 0.333333, 0.333333)

var _input: LineEdit = null
var _status: Label = null


func _ready() -> void:
	_build_ui()
	_input.grab_focus.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		accept_event()
		Fx.goto(MAIN_MENU)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = DARK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	Fx.add_ambient(self, Color(0.27, 0.95, 1.0, 0.14), 24)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = CYAN
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	Fx.pop_in(panel, 0.0, 0.35)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "命 名"
	title.theme_type_variation = &"Heading"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", CYAN_TEXT)
	box.add_child(title)

	var prompt := Label.new()
	prompt.text = "输入你的名字:"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_color", CYAN_TEXT)
	box.add_child(prompt)

	_input = LineEdit.new()
	_input.placeholder_text = ""
	_input.custom_minimum_size = Vector2(0, 38)
	_input.text_submitted.connect(_on_submitted)
	box.add_child(_input)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", ERR)
	_status.text = "Enter 确认，ESC 取消"
	box.add_child(_status)

	var confirm := Button.new()
	confirm.text = "[Enter] 确认"
	confirm.custom_minimum_size = Vector2(0, 40)
	confirm.add_theme_stylebox_override("normal", _make_stylebox(PANEL))
	confirm.add_theme_stylebox_override("hover", _make_stylebox(CYAN))
	confirm.add_theme_stylebox_override("pressed", _make_stylebox(CYAN))
	confirm.add_theme_stylebox_override("focus", _make_stylebox(PANEL))
	confirm.add_theme_color_override("font_color", Color(1, 1, 1))
	confirm.add_theme_color_override("font_hover_color", DARK)
	confirm.add_theme_color_override("font_pressed_color", DARK)
	confirm.pressed.connect(_confirm)
	box.add_child(confirm)


func _make_stylebox(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.set_corner_radius_all(3)
	return sb


func _on_submitted(_text: String) -> void:
	_confirm()


func _confirm() -> void:
	var raw := _input.text.strip_edges()
	if raw.is_empty():
		_status.text = "请输入一个名字"
		return

	var cjk := 0
	var others := 0
	for ch in raw:
		var code := ch.unicode_at(0)
		if code < 32 or ch == "\\" or ch == "\"" or ch == "'":
			_status.text = "名字中包含不允许的字符（如引号、斜杠）"
			return
		if _is_cjk(code):
			cjk += 1
		else:
			others += 1

	if cjk > MAX_CJK:
		_status.text = "中文字符不能超过 %d 个" % MAX_CJK
		return
	if others > MAX_ASCII:
		_status.text = "其它字符不能超过 %d 个" % MAX_ASCII
		return

	GameEngine.set_player_name(raw)
	Fx.goto(TRANSITION)


func _is_cjk(code: int) -> bool:
	return (code >= 0x4E00 and code <= 0x9FFF) \
		or (code >= 0x3400 and code <= 0x4DBF) \
		or (code >= 0xF900 and code <= 0xFAFF)
