extends Control
## 主菜单。对应 Python 的 view/main_menu.py。
##
## 新游戏 → 起名 → 转场独白 → 苏醒 → 主玩法；
## 读取游戏 / 设置 / 退出 都在这里开弹窗。

const MODAL_SCENE := preload("res://scenes/Modal.tscn")
const NAMING := "res://scenes/Naming.tscn"
const GAMEPLAY := "res://scenes/GamePlay.tscn"

## 沿用原 Textual 版配色
const DARK := Color(0.043137, 0.047059, 0.062745)     # #0b0c10
const PANEL := Color(0.121569, 0.156863, 0.2)         # #1f2833
const CYAN := Color(0.270588, 0.952941, 1)            # #45f3ff
const CYAN_TEXT := Color(0.4, 0.988235, 0.945098)     # #66fcf1
const GOLD := Color(1, 0.666667, 0)                   # #ffaa00
const BTN_BG := Color(0.066667, 0.078431, 0.117647)   # #11141e
const BTN_DISABLED_BG := Color(0.101961, 0.133333, 0.176471)  # #1a222d
const DISABLED_TEXT := Color(0.333333, 0.333333, 0.333333)    # #555555

var _btn_load: Button = null
var _modal_stack: Array[GameModal] = []


func _ready() -> void:
	_build_ui()
	_refresh_load_button()


func _unhandled_key_input(event: InputEvent) -> void:
	if not _modal_stack.is_empty():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1:
			accept_event()
			_on_new_game()
		KEY_2:
			accept_event()
			_open_load()
		KEY_3:
			accept_event()
			_open_settings()
		KEY_4:
			accept_event()
			_confirm_quit()


## ────────────────────────── 界面 ──────────────────────────

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = DARK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = CYAN
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 32
	sb.content_margin_right = 32
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "★ THE ADVENTURE ★"
	title.theme_type_variation = &"Heading"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", CYAN_TEXT)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "—— 冒 险 ——"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", GOLD)
	box.add_child(subtitle)

	box.add_child(_make_spacer(8))

	var btn_new := _make_menu_button("[1] 新游戏")
	btn_new.pressed.connect(_on_new_game)
	box.add_child(btn_new)

	_btn_load = _make_menu_button("[2] 读取游戏")
	_btn_load.pressed.connect(_open_load)
	box.add_child(_btn_load)

	var btn_settings := _make_menu_button("[3] 设置")
	btn_settings.pressed.connect(_open_settings)
	box.add_child(btn_settings)

	var btn_exit := _make_menu_button("[4] 退出游戏")
	btn_exit.pressed.connect(_confirm_quit)
	box.add_child(btn_exit)

	box.add_child(_make_spacer(6))

	var hint := Label.new()
	hint.text = "使用 1-4 数字键选择，或用鼠标点击"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.533333, 0.533333, 0.533333))
	box.add_child(hint)


func _make_spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _make_menu_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 40)
	btn.add_theme_stylebox_override("normal", _make_stylebox(BTN_BG))
	btn.add_theme_stylebox_override("hover", _make_stylebox(CYAN))
	btn.add_theme_stylebox_override("pressed", _make_stylebox(CYAN))
	btn.add_theme_stylebox_override("focus", _make_stylebox(BTN_BG))
	btn.add_theme_stylebox_override("disabled", _make_stylebox(BTN_DISABLED_BG))
	btn.add_theme_color_override("font_color", CYAN_TEXT)
	btn.add_theme_color_override("font_hover_color", DARK)
	btn.add_theme_color_override("font_pressed_color", DARK)
	btn.add_theme_color_override("font_focus_color", CYAN_TEXT)
	btn.add_theme_color_override("font_disabled_color", DISABLED_TEXT)
	return btn


func _make_stylebox(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.set_corner_radius_all(3)
	return sb


func _refresh_load_button() -> void:
	var has_save := false
	for s in GameEngine.get_save_slots():
		if s.get("exists", false) and not s.get("corrupted", false):
			has_save = true
			break
	_btn_load.disabled = not has_save
	_btn_load.text = "[2] 读取游戏" if has_save else "[2] 读取游戏 (无存档)"


## ────────────────────────── 行为 ──────────────────────────

func _on_new_game() -> void:
	GameEngine.reset_game()
	get_tree().change_scene_to_file(NAMING)


func _confirm_quit() -> void:
	if GameEngine.settings.get("confirm_exit", true):
		_open_confirm("退出游戏", "确定要退出游戏吗？\n未保存的进度将会丢失。",
			func() -> void: get_tree().quit(), GameModal.ACCENT_PINK)
	else:
		get_tree().quit()


## ────────────────────────── 弹窗 ──────────────────────────

func _make_modal(title: String, accent: Color, width: float, body_height: float) -> GameModal:
	var modal := MODAL_SCENE.instantiate() as GameModal
	add_child(modal)
	modal.configure({
		"title": title,
		"accent": accent,
		"width": width,
		"body_height": body_height,
	})
	return modal


func _push_modal(modal: GameModal) -> void:
	if not _modal_stack.is_empty():
		_modal_stack.back().input_blocked = true
	_modal_stack.append(modal)
	modal.closed.connect(_on_modal_closed.bind(modal))
	modal.open()


func _on_modal_closed(modal: GameModal) -> void:
	var idx := _modal_stack.find(modal)
	if idx != -1:
		_modal_stack.remove_at(idx)
	if not _modal_stack.is_empty():
		_modal_stack.back().input_blocked = false


func _open_confirm(title: String, message: String, on_confirm: Callable, accent: Color) -> void:
	var modal := _make_modal(title, accent, 460.0, 60.0)
	modal.add_text(message)
	modal.add_action("confirm", "[Y] 确认", accent)
	modal.add_action("cancel", "[N] 取消")
	modal.action_pressed.connect(func(id: String) -> void:
		modal.close()
		if id == "confirm":
			on_confirm.call()
	)
	_push_modal(modal)


func _open_load() -> void:
	if _btn_load.disabled:
		return
	var modal := _make_modal("读取存档", GameModal.ACCENT_GREEN, 620.0, 50.0)
	modal.add_text("读取会覆盖当前未保存的进度。", GameModal.MUTED)
	modal.action_pressed.connect(func(id: String) -> void:
		if id.begins_with("slot:"):
			_do_load(int(id.substr(5)))
		else:
			modal.close()
	)
	for s in GameEngine.get_save_slots():
		var i := int(s.get("slot", 0))
		var label := "存档 %d: 空" % i
		var disabled := true
		if s.get("corrupted", false):
			label = "存档 %d: （损坏）" % i
		elif s.get("exists", false):
			label = "存档 %d: %s ｜ %s ｜ %s" % [i, s.get("player_name", "无名"),
				s.get("room_id", "?"), s.get("last_saved", "")]
			disabled = false
		modal.add_action("slot:%d" % i, label, GameModal.ACCENT_GREEN, disabled)
	modal.add_action("close", "[ESC] 关闭")
	_push_modal(modal)


func _do_load(slot: int) -> void:
	if GameEngine.load_game(slot):
		get_tree().change_scene_to_file(GAMEPLAY)
	else:
		_open_confirm("读取失败", "这个存档读不出来。", func() -> void: pass, GameModal.ACCENT_PINK)


func _open_settings() -> void:
	var modal := _make_modal("设置", GameModal.ACCENT_GOLD, 660.0, 420.0)
	modal.action_pressed.connect(func(id: String) -> void:
		match id:
			"exit":
				_confirm_quit()
			"save_close":
				GameEngine.save_settings()
				modal.close()
			_:
				if id.begins_with("toggle:"):
					SettingsPanel.toggle(id.substr(7))
					_fill_settings(modal)
	)
	_fill_settings(modal)
	modal.closed.connect(func() -> void: GameEngine.save_settings())
	_push_modal(modal)


func _fill_settings(modal: GameModal) -> void:
	modal.configure({"title": "设置", "accent": GameModal.ACCENT_GOLD,
		"width": 660.0, "body_height": 420.0})
	SettingsPanel.fill(modal)
	modal.add_action("exit", "退出游戏", GameModal.ACCENT_PINK)
	modal.add_action("save_close", "保存并关闭", GameModal.ACCENT_GOLD)
