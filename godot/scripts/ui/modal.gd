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

## ── 配色板 ──
## 颜色统一放在 Palette 里（scripts/ui/palette.gd），这里只做别名，
## 免得每个界面各写一份色值、改一处漏一处。
const BG := Palette.BG                                   # 全局底色
const MODAL_BG := Palette.MODAL_BG                       # 弹窗底
const MODAL_BTN := Palette.MODAL_BTN                     # 弹窗按钮底
const BODY_TEXT := Palette.BODY_TEXT                     # 正文
const MUTED := Palette.MUTED                             # 次要文字
const DISABLED_BG := Palette.DISABLED_BG
const DISABLED_FG := Palette.DISABLED_FG

const ACCENT_CYAN := Palette.CYAN                        # 青（物品栏）
const ACCENT_PINK := Palette.PINK                        # 粉（人物）
const ACCENT_GOLD := Palette.GOLD                        # 金（保存/设置）
const ACCENT_AMBER := Palette.AMBER                      # 棕金（装备）
const ACCENT_GREEN := Palette.GREEN                      # 绿（读取）

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

## 设计基准尺寸（在 1280×720 下的样子）。实际显示尺寸会按窗口大小等比放大，
## 这样最大化窗口时弹窗也会跟着变大，而不是永远一小块。
var _base_width: float = DEFAULT_WIDTH
var _base_body_height: float = DEFAULT_BODY_HEIGHT


func _ready() -> void:
	_dim.gui_input.connect(_on_dim_gui_input)
	get_viewport().size_changed.connect(_apply_size)
	# 内容或底部按钮一变，重新算一次尺寸，保证弹窗不会长到屏幕外面去
	_body.minimum_size_changed.connect(_apply_size)
	_footer.minimum_size_changed.connect(_apply_size)
	_apply_size()


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
	_base_width = width
	_apply_size()


## 内容区最小高度。内容超出时出现滚动条。
func set_body_height(height: float) -> void:
	_base_body_height = height
	_apply_size()


## 按当前窗口大小换算实际尺寸：1280×720 下就是设计值，窗口更大就等比放大。
##
## 关键约束：标题和底部按钮是"不可压缩"的，内容区只能用剩下的高度，
## 并且左右各留 24px。这样无论窗口被拉多大，弹窗都不会顶出屏幕、
## 不会把按钮挤出可视区——超出部分在弹窗内部滚动。
func _apply_size() -> void:
	var vp := get_viewport_rect().size
	var sx := clampf(vp.x / 1280.0, 0.8, 1.6)
	var sy := clampf(vp.y / 720.0, 0.8, 1.4)

	_frame.custom_minimum_size.x = clampf(_base_width * sx, 320.0, maxf(320.0, vp.x - 48.0))

	var footer_h := 0.0
	var count := _footer.get_child_count()
	if count > 0:
		footer_h = count * 36.0 + (count - 1) * 6.0
	var chrome := footer_h + 150.0  # 150 ≈ 标题 + 面板内外边距 + 分隔
	var max_body := maxf(72.0, vp.y - chrome)

	# 内容高度取「设计高度的下限」：内容比它高就长高（最多到 max_body），
	# 比它矮也不缩回去。
	#
	# 为什么要有这个下限：切换设置项时内容会被整块重建，重建的一瞬间
	# 内容高度是骤降的（旧节点已清空、新节点还没排好），弹窗就会"折叠"一下，
	# 按钮跟着乱跑、点不准。锁住下限之后弹窗尺寸始终稳定。
	var want := _base_body_height * sy
	var needed := _body.get_combined_minimum_size().y
	_body_scroll.custom_minimum_size.y = clampf(maxf(want, minf(needed, max_body)), 48.0, max_body)


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
	Fx.pop_in(_frame, 0.0, 0.26)  # 面板弹入
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