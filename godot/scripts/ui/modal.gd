class_name GameModal
extends Control
## 通用模态弹窗控制器（配合 scenes/Modal.tscn 使用）。
##
## 一个外壳吃下原项目的 6 个界面（人物/物品/保存/读取/装备/设置），
## 差异只有标题、强调色、中间内容和底部按钮，全部通过下面的方法编程填充。
##
## 典型用法：
##     var modal := preload("res://scenes/Modal.tscn").instantiate()
##     add_child(modal)                        # 先入树，让 _ready 跑完
##     modal.configure({"title": "人物详情", "accent": GameModal.PINK})
##     modal.add_text("名字: 无名")
##     modal.add_action("close", "[ESC] 关闭")
##     modal.action_pressed.connect(_on_modal_action)

signal action_pressed(id: String)  ## 底部按钮被点击
signal closed                      ## 弹窗已关闭（即将被销毁）

## ── 配色板（沿用原 Textual 版本）──
const BG := Color(0.043137, 0.047059, 0.062745)          # #0b0c10 全局底色
const MODAL_BG := Color(0.086275, 0.098039, 0.137255)    # #161923 弹窗底
const MODAL_BTN := Color(0.137255, 0.156863, 0.231373)   # #23283b 弹窗按钮底
const BODY_TEXT := Color(0.772549, 0.776471, 0.780392)   # #c5c6c7 正文
const MUTED := Color(0.698039, 0.698039, 0.698039)       # #b2b2b2 次要文字
const DISABLED_BG := Color(0.066667, 0.066667, 0.066667) # #111111
const DISABLED_FG := Color(0.2, 0.2, 0.2)                # #333333

const ACCENT_CYAN := Color(0.4, 0.988235, 0.945098)      # #66fcf1 青（物品栏）
const ACCENT_PINK := Color(1, 0, 0.498039)               # #ff007f 粉（人物）
const ACCENT_GOLD := Color(1, 0.666667, 0)               # #ffaa00 金（保存/设置）
const ACCENT_AMBER := Color(0.866667, 0.666667, 0)       # #ddaa00 棕金（装备）
const ACCENT_GREEN := Color(0, 1, 0.4)                   # #00ff66 绿（读取）

const DEFAULT_BODY_HEIGHT := 220.0
const DEFAULT_WIDTH := 640.0

@onready var _dim: ColorRect = $Dim
@onready var _frame: PanelContainer = $Center/Frame
@onready var _title: Label = $Center/Frame/Margin/VBox/Title
@onready var _body_scroll: ScrollContainer = $Center/Frame/Margin/VBox/BodyScroll
@onready var _body: VBoxContainer = $Center/Frame/Margin/VBox/BodyScroll/Body
@onready var _footer: VBoxContainer = $Center/Frame/Margin/VBox/Footer

var accent: Color = ACCENT_CYAN
## 上层又叠了一个弹窗（如确认框）时置 true，屏蔽本层的 ESC，
## 免得一次按键把叠在一起的两层一起关掉。
var input_blocked: bool = false
var _closed: bool = false


func _ready() -> void:
	_dim.gui_input.connect(_on_dim_gui_input)


func _unhandled_key_input(event: InputEvent) -> void:
	if input_blocked:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			accept_event()
			close()


## ────────────────────────── 配置 ──────────────────────────

## 一次性配置外壳，并清空上次的内容。调用后自行追加内容与按钮。
## 可传字段：title / accent / width / body_height
func configure(cfg: Dictionary) -> void:
	clear_body()
	clear_actions()
	set_title(cfg.get("title", ""), cfg.get("accent", accent))
	set_width(cfg.get("width", DEFAULT_WIDTH))
	set_body_height(cfg.get("body_height", DEFAULT_BODY_HEIGHT))


func set_title(text: String, title_accent: Color = accent) -> void:
	_title.text = text
	set_accent(title_accent)


## 同时决定标题颜色与面板描边颜色
func set_accent(color: Color) -> void:
	accent = color
	_title.add_theme_color_override("font_color", color)
	var sb := _frame.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	sb.border_color = color
	_frame.add_theme_stylebox_override("panel", sb)


func set_width(width: float) -> void:
	_frame.custom_minimum_size.x = width


## 内容区最小高度。内容超出时出现滚动条。
func set_body_height(height: float) -> void:
	_body_scroll.custom_minimum_size.y = height


## ────────────────────────── 内容填充 ──────────────────────────

func clear_body() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()


## 加一行普通文本
func add_text(text: String, color: Color = BODY_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	_body.add_child(label)
	return label


## 加一段支持 BBCode 的富文本（居中等排版都靠标签控制）
func add_rich_text(bbcode: String, color: Color = BODY_TEXT) -> RichTextLabel:
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.add_theme_color_override("default_color", color)
	rich.text = bbcode
	_body.add_child(rich)
	return rich


## 加一行两列文本：左标签（如属性名）+ 右值
func add_row(label_text: String, value_text: String,
		label_color: Color = MUTED, value_color: Color = BODY_TEXT) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 120
	label.add_theme_color_override("font_color", label_color)
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.add_theme_color_override("font_color", value_color)
	row.add_child(value)

	_body.add_child(row)
	return row


## 加一行「说明 + 右侧按钮」，用于设置界面。返回右侧按钮供后续改文字。
func add_toggle_row(desc: String, button_id: String, button_text: String,
		min_button_width: float = 120.0) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = desc
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", MUTED)
	row.add_child(label)

	var button := Button.new()
	button.text = button_text
	button.custom_minimum_size = Vector2(min_button_width, 32)
	_style_button(button, accent)
	button.pressed.connect(func(): action_pressed.emit(button_id))
	row.add_child(button)

	_body.add_child(row)
	return button


## 把一个自定义节点塞进内容区（物品栏那种列表+详情的复杂布局用）
func add_node(node: Control) -> void:
	_body.add_child(node)


## 给外部自建的按钮套上弹窗按钮的配色（物品栏列表、装备卸下按钮等）
func style_button(button: Button, button_accent: Color) -> void:
	_style_button(button, button_accent)


## ────────────────────────── 底部按钮 ──────────────────────────

func clear_actions() -> void:
	for child in _footer.get_children():
		_footer.remove_child(child)
		child.queue_free()


## 加一个底部按钮。id 会通过 action_pressed 信号带回。
func add_action(id: String, label: String, button_accent: Color = Color.WHITE,
		disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 36)
	button.disabled = disabled
	_style_button(button, button_accent)
	button.pressed.connect(func(): action_pressed.emit(id))
	_footer.add_child(button)
	return button


## ────────────────────────── 开 / 关 ──────────────────────────

## 打开后把键盘焦点放进弹窗，避免方向键漏到底下的游戏画面
func open() -> void:
	_closed = false
	var first := _first_focusable()
	if first != null:
		first.grab_focus.call_deferred()


func close() -> void:
	if _closed:
		return
	_closed = true
	closed.emit()
	queue_free()


func _on_dim_gui_input(event: InputEvent) -> void:
	# 点击遮罩区域关闭（面板上的点击不会传到这里）
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


func _first_focusable() -> Control:
	for container in [_footer, _body]:
		for child in container.get_children():
			if child is Button:
				return child
			for grandchild in child.get_children():
				if grandchild is Button:
					return grandchild
	return null


## ────────────────────────── 内部 ──────────────────────────

func _style_button(button: Button, button_accent: Color) -> void:
	button.add_theme_stylebox_override("normal", _make_stylebox(MODAL_BTN))
	button.add_theme_stylebox_override("hover", _make_stylebox(button_accent))
	button.add_theme_stylebox_override("pressed", _make_stylebox(button_accent))
	button.add_theme_stylebox_override("focus", _make_stylebox(MODAL_BTN))
	button.add_theme_stylebox_override("disabled", _make_stylebox(DISABLED_BG))
	button.add_theme_color_override("font_color", button_accent)
	button.add_theme_color_override("font_hover_color", BG)
	button.add_theme_color_override("font_pressed_color", BG)
	button.add_theme_color_override("font_focus_color", button_accent)
	button.add_theme_color_override("font_disabled_color", DISABLED_FG)


func _make_stylebox(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.set_corner_radius_all(3)
	return sb