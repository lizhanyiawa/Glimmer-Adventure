extends Control
## 苏醒：暗框的边框由灰渐亮成青色，然后进入主玩法。
## 对应 Python 的 view/brighten_screen.py。

const GAMEPLAY := "res://scenes/GamePlay.tscn"

const BORDER_DARK := Color(0.2, 0.2, 0.2)     # #333333
const BORDER_BRIGHT := Color(0.271, 0.867, 1.0)  # #45ddff


func _ready() -> void:
	_play()


func _build_ui() -> StyleBoxFlat:
	var bg := ColorRect.new()
	bg.color = Color(0.043137, 0.047059, 0.062745)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 200)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.101961, 0.101961, 0.101961)
	sb.border_color = BORDER_DARK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

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
	await tw.finished
	await get_tree().create_timer(0.3).timeout

	# 第一次进游戏才播苏醒独白
	if not GameEngine.get_flag("intro_monologue_done", false):
		GameEngine.state.dialogue_id = "intro_wake_1"
	get_tree().change_scene_to_file(GAMEPLAY)
