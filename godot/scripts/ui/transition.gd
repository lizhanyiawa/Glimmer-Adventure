extends Control
## 转场独白：逐段打字、逐段等玩家确认，最后整段淡出，进入「苏醒」。
## 对应 Python 的 view/transition_screen.py。

const BRIGHTEN := "res://scenes/Brighten.tscn"

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


func _ready() -> void:
	_build_ui()
	_play()


func _unhandled_input(event: InputEvent) -> void:
	if not _busy:
		return
	var advance := false
	if event is InputEventKey and event.pressed and not event.echo:
		advance = event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance = true
	if advance:
		_advance = true
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.043137, 0.047059, 0.062745)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(760, 120)
	_text.add_theme_color_override("default_color", Color(0.772549, 0.776471, 0.780392))
	box.add_child(_text)

	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	box.add_child(_prompt)


func _play() -> void:
	var speed: float = SPEED_PRESETS.get(str(GameEngine.settings.get("text_speed", "medium")), 0.03)

	for line in LINES:
		_prompt.text = ""
		_text.text = "[center]%s[/center]" % line
		_text.visible_ratio = 0.0
		if speed > 0.0:
			var tw := create_tween()
			tw.tween_property(_text, "visible_ratio", 1.0, maxf(0.25, speed * line.length()))
			await tw.finished
		else:
			_text.visible_ratio = 1.0
		_prompt.text = "[Enter] 继续"
		await _wait_advance()

	# 全部看完 → 整段淡出
	_prompt.text = ""
	var fade := create_tween()
	fade.set_parallel(true)
	fade.tween_property(_text, "modulate:a", 0.0, 0.8)
	fade.tween_property(_prompt, "modulate:a", 0.0, 0.8)
	await fade.finished
	get_tree().change_scene_to_file(BRIGHTEN)


## 等玩家按 Enter / 空格 / 点击
func _wait_advance() -> void:
	_advance = false
	_busy = true
	while not _advance:
		await get_tree().process_frame
	_busy = false
