extends Control
## 开场引导：黑屏跑码 → 打出标题 → 自动进主菜单。
## 对应 Python 的 view/intro_screen.py。
##
## 设置里勾了「跳过开场动画」就直接进主菜单。

const MAIN_MENU := "res://scenes/MainMenu.tscn"

const BOOT_LINES: Array = [
	"CONNECTING TO OUTSIDER SERVER...",
	"DECODING REINCARNATION PROTOCOL... [OK]",
	"STABILIZING ISEKAI ENERGY WELL... [100%]",
]

var _text: RichTextLabel = null


func _ready() -> void:
	_build_ui()
	if GameEngine.settings.get("skip_intro", false):
		get_tree().change_scene_to_file(MAIN_MENU)
		return
	_play()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(640, 160)
	_text.add_theme_color_override("default_color", Color(0.4, 0.988235, 0.945098))
	center.add_child(_text)


func _play() -> void:
	var log_text := ""
	for line in BOOT_LINES:
		log_text += line + "\n"
		_text.text = "[center]%s[/center]" % log_text
		await get_tree().create_timer(0.35).timeout

	# 跑码结束，轰出标题
	_text.text = "\n".join([
		"[center]",
		"",
		"[color=#66fcf1][b]W E L C O M E[/b][/color]",
		"",
		"[color=#ffaa00]—— 冒 险 ——[/color]",
		"[/center]",
	])
	await get_tree().create_timer(1.6).timeout
	get_tree().change_scene_to_file(MAIN_MENU)
