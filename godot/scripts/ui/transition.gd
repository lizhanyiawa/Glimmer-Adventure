extends Control
## 转场独白：逐段打字、逐段等玩家确认，最后整段淡出，进入「苏醒」。
## 对应 Python 的 view/transition_screen.py。
##
## 交互：Enter / 空格 / 鼠标左键都行。正在打字时按一下先"快进"把当前这句打完，
## 再按一下才翻到下一句。

const BRIGHTEN := "res://scenes/Brighten.tscn"
const PROMPT := "[Enter] 继续"

## 打字速度（每个字多少秒），与设置里的文字速度对应
const SPEED_PRESETS: Dictionary = {"instant": 0.0, "fast": 0.01, "medium": 0.03, "slow": 0.06}

## 独白内容，与 Python 版逐字一致（颜色标签已换成 BBCode）
const LINES: Array = [
	"高数课上，老师在讲台上滔滔不绝地推导着傅里叶变换....",
	"你趴在桌上，眼皮越来越重。",
	"讲台上的声音渐渐远去，变成了模糊的嗡鸣...",
	". . .",
	"[color=#444444]你坠入了一片无边的黑暗。[/color]",
	"[color=#333333]耳边有奇怪的低语，像电流，又像古老的咒文。[/color]",
	"[color=#555555]意识在混沌中漂浮，你分不清过了多久。[/color]",
	"[color=#777777]远处似乎有一点微光...[/color]",
	"[color=#999999]光越来越近，越来越亮。[/color]",
	"[color=#bbbbbb]你猛地睁开了眼睛。[/color]",
	"[color=#c5c6c7]你躺在一张硬邦邦的床上，头顶是低矮的茅草屋顶。[/color]",
	"[color=#c5c6c7]床头柜上，一盏蜡烛摇曳着微弱的火光。[/color]",
	"[color=#c5c6c7]这不是你的教室。[/color]",
]

var _text: RichTextLabel = null
var _prompt: Label = null
var _busy := false       ## 正在等玩家确认
var _advance := false    ## 本段是否已被确认
var _typing := false     ## 当前这段是否还在打字（此时按键=快进）


func _ready() -> void:
	# 本屏没有按钮，全部控件都不吃鼠标事件，点击才会落到 _unhandled_input。
	# （CenterContainer / ColorRect 默认是"拦截"鼠标的，不设成忽略的话
	#   鼠标点下去会被它们吃掉，_unhandled_input 永远收不到，于是"鼠标=回车"失效。）
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_play()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_advance_event(event):
		return
	get_viewport().set_input_as_handled()
	if _typing:
		_typing = false   # 快进：把当前这句直接打完，不翻页
		return
	if _busy:
		_advance = true


func _is_advance_event(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		return event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		return true
	return false


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.043137, 0.047059, 0.062745)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	Fx.add_ambient(self, Color(0.27, 0.95, 1.0, 0.16), 22)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.custom_minimum_size = Vector2(760, 120)
	_text.add_theme_color_override("default_color", Color(0.772549, 0.776471, 0.780392))
	center.add_child(_text)
	Fx.fade_in(_text, 0.05, 0.5)

	# 「继续」提示按 UI 惯例放右下角
	_prompt = Label.new()
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_prompt.anchor_left = 1.0
	_prompt.anchor_top = 1.0
	_prompt.anchor_right = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_left = -300.0
	_prompt.offset_top = -52.0
	_prompt.offset_right = -28.0
	_prompt.offset_bottom = -20.0
	add_child(_prompt)


func _play() -> void:
	var speed: float = SPEED_PRESETS.get(str(GameEngine.settings.get("text_speed", "medium")), 0.03)

	for line in LINES:
		_prompt.text = ""
		_text.text = "[center]%s[/center]" % line
		_text.visible_ratio = 0.0
		if speed > 0.0:
			_typing = true
			# 用真实可见字数算时长：BBCode 标签不计入，带颜色的句子不会明显变慢
			var count := maxi(1, _text.get_total_character_count())
			var tw := create_tween()
			tw.tween_property(_text, "visible_ratio", 1.0, maxf(0.25, speed * float(count)))
			# 不用 await tw.finished：玩家快进时 tween 会被 kill，finished 就不会发出来
			while _typing and _text.visible_ratio < 1.0:
				await get_tree().process_frame
			tw.kill()
			_text.visible_ratio = 1.0
			_typing = false
		else:
			_text.visible_ratio = 1.0

		_prompt.modulate.a = 0.0
		_prompt.text = PROMPT
		Fx.fade_in(_prompt, 0.0, 0.3)
		await _wait_advance()

	# 全部看完 → 整段淡出
	_prompt.text = ""
	var fade := create_tween()
	fade.set_parallel(true)
	fade.tween_property(_text, "modulate:a", 0.0, 0.7)
	fade.tween_property(_prompt, "modulate:a", 0.0, 0.7)
	await fade.finished
	Fx.goto(BRIGHTEN)


## 等玩家按 Enter / 空格 / 点击
func _wait_advance() -> void:
	_advance = false
	_busy = true
	while not _advance:
		await get_tree().process_frame
	_busy = false
