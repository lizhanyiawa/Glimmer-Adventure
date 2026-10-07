class_name GameModal
extends Control
## 通用面板外壳控制器（配合 scenes/Modal.tscn 使用）。
##
## 一个外壳吃下所有界面（人物/物品/保存/读取/装备/设置/商店/日记/确认框），
## 差异只有标题、强调色、中间内容和底部按钮，全部通过下面的方法编程填充。
##
## 两种摆放模式（由 configure 的 mode 字段决定）：
##   MODE_CENTER —— 居中弹窗：确认框、输入框这类"打断一下"的小界面
##   MODE_DRAWER —— 右侧抽屉：人物/物品/设置等主面板，贴右侧撑满整高、滑入滑出
##
## 典型用法：
##     var modal := preload("res://scenes/Modal.tscn").instantiate()
##     add_child(modal)                        # 先入树，让 _ready 跑完
##     modal.configure({"title": "人物详情", "accent": GameModal.PINK,
##                      "mode": GameModal.MODE_DRAWER})
##     modal.add_text("名字: 无名")
##     modal.add_action("close", "[ESC] 关闭")
##     modal.action_pressed.connect(_on_modal_action)
##     modal.open()

signal action_pressed(id: String)  ## 底部按钮被点击
signal closed                      ## 面板已关闭（即将被销毁）

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

## ── 模式 ──
const MODE_CENTER := "center"   ## 居中弹窗：尺寸随内容，点遮罩关闭
const MODE_DRAWER := "drawer"   ## 右侧抽屉：贴右撑满整高，滑入滑出

const DEFAULT_BODY_HEIGHT := 220.0
const DEFAULT_WIDTH := 640.0

## 抽屉与屏幕边缘的间距
const DRAWER_MARGIN := 12.0
## 抽屉打开时主画面的压暗程度（比居中弹窗的 0.72 淡，能看清背景）
const DRAWER_DIM_ALPHA := 0.35
## 居中弹窗的遮罩浓度
const CENTER_DIM_ALPHA := 0.72
## 抽屉滑入 / 滑出的时长
const SLIDE_DUR := 0.26

@onready var _dim: ColorRect = $Dim
@onready var _frame: PanelContainer = $Stage/Frame
@onready var _title: Label = $Stage/Frame/Margin/VBox/Title
@onready var _body_scroll: ScrollContainer = $Stage/Frame/Margin/VBox/BodyScroll
@onready var _body: VBoxContainer = $Stage/Frame/Margin/VBox/BodyScroll/Body
@onready var _footer: VBoxContainer = $Stage/Frame/Margin/VBox/Footer

var accent: Color = ACCENT_CYAN
## 摆放模式，见 MODE_CENTER / MODE_DRAWER
var mode: String = MODE_CENTER
## 上层又叠了一个弹窗（如确认框）时置 true，屏蔽本层的 ESC，
## 免得一次按键把叠在一起的两层一起关掉。
var input_blocked: bool = false
var _closed: bool = false

## 抽屉当前是否处于"打开"位置（被返回栈临时收起时置 false）
var _is_open: bool = false
## 是否正在滑出、以及滑出结束后要不要销毁自己（返回栈收起时只隐藏不销毁）
var _hide_pending: bool = false
var _hide_frees: bool = false
## 正在跑的滑动补间。改尺寸或重新起一段动画前要先 kill，否则两条会抢 offset。
var _slide_tween: Tween = null

## 设计基准尺寸（在 1280×720 下的样子）。实际显示尺寸会按窗口大小等比放大，
## 这样最大化窗口时面板也会跟着变大，而不是永远一小块。
var _base_width: float = DEFAULT_WIDTH
var _base_body_height: float = DEFAULT_BODY_HEIGHT
## 抽屉当前的实际宽度（按窗口换算后的值，滑入滑出用它算起止位置）
var _drawer_width: float = DEFAULT_WIDTH


func _ready() -> void:
	_dim.gui_input.connect(_on_dim_gui_input)
	get_viewport().size_changed.connect(_apply_size)
	# 内容或底部按钮一变，重新算一次尺寸，保证面板不会长到屏幕外面去
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
## 可传字段：title / accent / width / body_height / mode
##
## 注意：本方法会在"打开状态下"被重复调用（设置项切换、装备刷新都要重建内容），
## 所以位置必须按当前 _is_open 状态复原，不能每次都缩回关闭位。
func configure(cfg: Dictionary) -> void:
	clear_body()
	clear_actions()
	mode = cfg.get("mode", mode)
	_apply_geometry()   # 先把锚点定下来，后面 set_width 里的 _apply_size 才算得准
	set_title(cfg.get("title", ""), cfg.get("accent", accent))
	set_width(cfg.get("width", DEFAULT_WIDTH))
	set_body_height(cfg.get("body_height", DEFAULT_BODY_HEIGHT))
	_apply_size()
	if mode == MODE_DRAWER:
		_apply_drawer_offsets(_is_open)


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


## 内容区最小高度（仅居中模式用）。内容超出时出现滚动条。
func set_body_height(height: float) -> void:
	_base_body_height = height
	_apply_size()


## 按模式写 Frame 的锚点：居中弹窗锚在正中，抽屉锚在右侧。
## Stage 是中性容器，不参与摆放，所以位置全部由这里决定。
func _apply_geometry() -> void:
	if mode == MODE_DRAWER:
		_frame.anchor_left = 1.0
		_frame.anchor_right = 1.0
		_frame.anchor_top = 0.0
		_frame.anchor_bottom = 1.0
		_frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_frame.grow_vertical = Control.GROW_DIRECTION_BOTH
		_frame.offset_top = DRAWER_MARGIN
		_frame.offset_bottom = -DRAWER_MARGIN
		_dim.color.a = DRAWER_DIM_ALPHA
		_dim.modulate.a = 1.0 if _is_open else 0.0
	else:
		_frame.anchor_left = 0.5
		_frame.anchor_right = 0.5
		_frame.anchor_top = 0.5
		_frame.anchor_bottom = 0.5
		_frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_frame.grow_vertical = Control.GROW_DIRECTION_BOTH
		_frame.offset_left = 0.0
		_frame.offset_right = 0.0
		_frame.offset_top = 0.0
		_frame.offset_bottom = 0.0
		_dim.color.a = CENTER_DIM_ALPHA
		_dim.modulate.a = 1.0


## 按当前窗口大小换算实际尺寸。
##
## 居中模式的关键约束：标题和底部按钮"不可压缩"，内容区只能用剩下的高度，
## 并且左右各留 24px。这样无论窗口被拉多大，面板都不会顶出屏幕。
## 抽屉模式相反：宽度固定、高度撑满，内容区吃掉标题与底部按钮之间的全部空间。
func _apply_size() -> void:
	var vp := get_viewport_rect().size
	var sx := clampf(vp.x / 1280.0, 0.8, 1.6)
	var sy := clampf(vp.y / 720.0, 0.8, 1.4)

	if mode == MODE_DRAWER:
		_drawer_width = clampf(_base_width * sx, 360.0, maxf(360.0, vp.x - 48.0))
		# 宽度由锚点 + offset 决定，别再让自定义最小宽度插手
		_frame.custom_minimum_size = Vector2.ZERO
		# 撑满整高：内容区吃掉剩余空间（scene 里 BodyScroll 已是 EXPAND_FILL）
		_body_scroll.custom_minimum_size.y = 0.0

		if _slide_tween != null and _slide_tween.is_valid():
			# 滑到一半窗口被缩放：按新宽度重起一段动画（从当前 offset 续着走），
			# 否则补间会一路滑向按旧宽度算出的过期坐标
			_start_slide(not _hide_pending)
		else:
			_apply_drawer_offsets(_is_open)
		return

	# ── 居中模式：保持原有尺寸逻辑不变 ──
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
	# 按钮跟着乱跑、点不准。锁住下限之后尺寸始终稳定。
	var want := _base_body_height * sy
	var needed := _body.get_combined_minimum_size().y
	_body_scroll.custom_minimum_size.y = clampf(maxf(want, minf(needed, max_body)), 48.0, max_body)


## ────────────────────────── 抽屉位移 ──────────────────────────
##
## 抽屉锚在右边缘，offset 都是相对右边缘的量。滑入滑出就是同时平移
## offset_left 与 offset_right（差值为固定宽度，保证宽度不变）：
##     打开：left = -(W+M)  right = -M        → 贴在右边缘，左右各留 M
##     关闭：left = 0       right = W+M       → 整块移出屏幕右侧

func _apply_drawer_offsets(open: bool) -> void:
	if open:
		_frame.offset_left = -(_drawer_width + DRAWER_MARGIN)
		_frame.offset_right = -DRAWER_MARGIN
	else:
		_frame.offset_left = 0.0
		_frame.offset_right = _drawer_width + DRAWER_MARGIN


# ────────────────────────── 内容填充 ──────────────────────────

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

## 打开面板：居中模式弹入，抽屉模式滑入。之后把键盘焦点放进面板，
## 避免方向键漏到底下的游戏画面。
func open() -> void:
	_closed = false
	_is_open = true
	_hide_pending = false

	if mode == MODE_DRAWER:
		_dim.modulate.a = 0.0
		_apply_drawer_offsets(false)
		_start_slide(true)
	else:
		Fx.pop_in(_frame, 0.0, 0.26)  # 面板弹入

	var first := _first_focusable()
	if first != null:
		first.grab_focus.call_deferred()


func close() -> void:
	if _closed:
		return
	_closed = true
	if mode == MODE_DRAWER:
		_animate_hide(true)   # 滑出后再销毁
	else:
		_finish_close()       # 居中弹窗保持原来的立即关闭


## 返回栈用：把本面板滑出屏幕但**不销毁**，给下面那层腾位置。
func hide_for_stack() -> void:
	if _closed:
		return
	_animate_hide(false)


## 返回栈用：上一层关闭了，把自己滑回来。
func show_from_stack() -> void:
	_is_open = true
	_hide_pending = false
	visible = true
	if mode == MODE_DRAWER:
		_start_slide(true)


## 起一段滑动动画（从当前位置滑向目标位置）。
## 会先 kill 掉上一段补间——不 kill 的话两条补间会抢同一组 offset。
func _start_slide(open: bool) -> void:
	_kill_slide()
	var left := -(_drawer_width + DRAWER_MARGIN) if open else 0.0
	var right := -DRAWER_MARGIN if open else (_drawer_width + DRAWER_MARGIN)
	var dim_target := 1.0 if open else 0.0
	var ease_type := Tween.EASE_OUT if open else Tween.EASE_IN

	_slide_tween = create_tween()
	_slide_tween.set_parallel(true)
	_slide_tween.tween_property(_frame, "offset_left", left, SLIDE_DUR) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(ease_type)
	_slide_tween.tween_property(_frame, "offset_right", right, SLIDE_DUR) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(ease_type)
	_slide_tween.tween_property(_dim, "modulate:a", dim_target, SLIDE_DUR) \
		.set_trans(Tween.TRANS_SINE)
	_slide_tween.finished.connect(_on_slide_done)


## 滑出动画收尾：销毁，或（返回栈临时收起时）只是隐藏。
func _on_slide_done() -> void:
	_slide_tween = null
	if not _hide_pending:
		return
	_hide_pending = false
	if _hide_frees:
		_finish_close()
	else:
		visible = false


func _animate_hide(free_after: bool) -> void:
	_is_open = false
	_hide_pending = true
	_hide_frees = free_after
	_start_slide(false)


func _kill_slide() -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = null


func _finish_close() -> void:
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