class_name BattleScene
extends Control
## 战斗界面（对应 Python 的 view/battle_screen.py: BattleScreen）。
##
## 由 GamePlay 在选项触发战斗时实例化，盖在主玩法之上；战斗结束后发
## finished 信号、自己销毁，GamePlay 收到后刷新房间。
##
## 输入设计（关键）：
##   本节点是整屏的 Control，mouse_filter = STOP，所有内部装饰控件（背景、
##   面板、文字、血条、提示）一律 IGNORE。这样"点到空白处"会落到本节点的
##   _gui_input，等价于按回车继续；而真正可点的 4 个动作按钮保持 STOP。
##   如果反过来把根节点设成 IGNORE，点击会穿透到下层 GamePlay 的选项按钮。
##
## 逻辑全在 scripts/core/battle.gd: BattleManager 里，这里只负责显示与输入。

signal finished

const SPEED_PRESETS: Dictionary = {"instant": 0.0, "fast": 0.01, "medium": 0.03, "slow": 0.06}

var _bm: BattleManager = null
var _post_battle: Dictionary = {}

# 顶部：双方名字 + 血条 + 数值
var _player_name: Label = null
var _enemy_name: Label = null
var _player_bar: ProgressBar = null
var _enemy_bar: ProgressBar = null
var _player_hp_label: Label = null
var _enemy_hp_label: Label = null
var _player_dmg_label: Label = null
var _enemy_dmg_label: Label = null
var _player_fill: StyleBoxFlat = null
var _enemy_fill: StyleBoxFlat = null

# 中部：战斗叙事 + 战斗历史
var _story: RichTextLabel = null
var _history: RichTextLabel = null

# 底部：动作按钮 / 行动子菜单 / 继续提示
var _action_row: HBoxContainer = null
var _submenu: HBoxContainer = null
var _btn_attack: Button = null
var _btn_action: Button = null
var _btn_flee: Button = null
var _btn_item: Button = null
var _btn_defend: Button = null
var _btn_investigate: Button = null
var _prompt: Label = null

var _typing := false        ## 正在打字（此时点击/回车 = 快进本句）
var _cont_waiting := false  ## 正在等玩家确认
var _cont_callback: Callable = Callable()

## 血条上一帧的比例（-1 = 还没记录过）。首次刷新是初始值而非掉血，不画残影。
var _player_prev_ratio := -1.0
var _enemy_prev_ratio := -1.0


func _ready() -> void:
	# 整屏拦截鼠标，见文件头说明
	mouse_filter = Control.MOUSE_FILTER_STOP


## 由 GamePlay 调用：传入敌人 id 与战斗后效果（选项里的 post_battle）
func setup(enemy_id: String, post_battle: Dictionary) -> void:
	_post_battle = post_battle
	_build_ui()

	_bm = BattleManager.new(GameEngine, enemy_id)
	_set_action_enabled(false)
	_refresh_bars()

	# 首次遭遇：附加理智变动提示（对应 Python on_mount 里的 san_extra）
	var san_extra := ""
	if _bm.first_monster:
		var san_text := str(_bm.enemy_data.get("san_text", ""))
		var drop := int(_bm.enemy_data.get("san_drop", 0))
		var num := "%s%d" % ["+" if drop > 0 else "", drop]
		if not san_text.is_empty():
			san_extra = "\n\n<dim>%s（理智%s）</dim>" % [san_text, num]
		else:
			san_extra = "\n\n<dim>（第一次遭遇——理智值%s）</dim>" % num

	var encounter_text := _bm.get_narrative("encounter", "%s出现了！" % _bm.enemy.name)
	encounter_text += san_extra
	_append_history(encounter_text)

	var pre_text := _bm.resolve_pre_battle()
	if not pre_text.is_empty():
		_append_history(pre_text)
		encounter_text += "\n" + pre_text
		_refresh_bars()

	_bm.rebuild_turn_order()
	_cont_callback = _start_turn
	await _type_text(encounter_text)
	_wait_for_continue()


## ────────────────────────── 输入 ──────────────────────────

## 点击空白处（本节点的任何非按钮区域）= 回车
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_advance()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		accept_event()
		_advance()
		return

	if _cont_waiting or _typing or _bm == null:
		return
	# 子菜单打开时，主按钮已隐藏，1/3 不再生效（与 Python 版一致）
	if not _action_row.visible:
		return
	match event.keycode:
		KEY_1:
			accept_event()
			_on_attack()
		KEY_2:
			accept_event()
			_open_action_menu()
		KEY_3:
			accept_event()
			_on_flee()


## 点击/回车：正在打字就先快进，等确认时就继续，其余情况忽略
func _advance() -> void:
	if _typing:
		_typing = false
		return
	if _cont_waiting:
		_do_continue()


## ────────────────────────── 界面搭建 ──────────────────────────

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(root)

	_build_top(root)
	_build_middle(root)
	_build_bottom(root)

	Fx.stagger([_btn_attack, _btn_action, _btn_flee, _btn_item], 0.05, 0.24)


## 顶部：左玩家 / 右敌人，各一行名字 + 血条 + 数值
func _build_top(root: VBoxContainer) -> void:
	var panel := _make_panel(Palette.BAR_BORDER)
	panel.custom_minimum_size = Vector2(0, 118)
	root.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	# 左：玩家
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)

	_player_name = _make_label("", Palette.BODY_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	left.add_child(_player_name)

	var left_hp := HBoxContainer.new()
	left_hp.add_theme_constant_override("separation", 8)
	left_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(left_hp)

	_player_bar = _make_hp_bar()
	left_hp.add_child(_player_bar)
	_player_fill = _player_bar.get_theme_stylebox("fill") as StyleBoxFlat

	_player_hp_label = _make_label("", Palette.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	_player_hp_label.custom_minimum_size = Vector2(96, 0)
	left_hp.add_child(_player_hp_label)

	_player_dmg_label = _make_label("", Palette.RED, HORIZONTAL_ALIGNMENT_LEFT)
	left_hp.add_child(_player_dmg_label)

	# 右：敌人（整体右对齐）
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)

	_enemy_name = _make_label("", Palette.BODY_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	right.add_child(_enemy_name)

	var right_hp := HBoxContainer.new()
	right_hp.alignment = BoxContainer.ALIGNMENT_END
	right_hp.add_theme_constant_override("separation", 8)
	right_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(right_hp)

	_enemy_dmg_label = _make_label("", Palette.RED, HORIZONTAL_ALIGNMENT_RIGHT)
	right_hp.add_child(_enemy_dmg_label)

	_enemy_hp_label = _make_label("", Palette.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_enemy_hp_label.custom_minimum_size = Vector2(96, 0)
	right_hp.add_child(_enemy_hp_label)

	_enemy_bar = _make_hp_bar()
	right_hp.add_child(_enemy_bar)
	_enemy_fill = _enemy_bar.get_theme_stylebox("fill") as StyleBoxFlat


## 中部：叙事 65% / 战斗历史 35%
func _build_middle(root: VBoxContainer) -> void:
	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 12)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(middle)

	var story_panel := _make_panel(Palette.CYAN_DEEP)
	story_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story_panel.size_flags_stretch_ratio = 0.65
	middle.add_child(story_panel)

	_story = RichTextLabel.new()
	_story.bbcode_enabled = true
	_story.scroll_active = true
	_story.scroll_following = true
	_story.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_story.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_story.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_story.add_theme_color_override("default_color", Palette.BODY_TEXT)
	story_panel.add_child(_story)

	var history_panel := _make_panel(Palette.BAR_BORDER)
	history_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_panel.size_flags_stretch_ratio = 0.35
	middle.add_child(history_panel)

	_history = RichTextLabel.new()
	_history.bbcode_enabled = true
	_history.scroll_active = true
	_history.scroll_following = true
	_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_history.add_theme_color_override("default_color", Palette.DIM)
	history_panel.add_child(_history)


## 底部：动作按钮 / 行动子菜单 / 继续提示
func _build_bottom(root: VBoxContainer) -> void:
	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)

	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 12)
	_action_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_action_row)

	_btn_attack = _make_action_button("[1] 攻击")
	_btn_action = _make_action_button("[2] 行动")
	_btn_flee = _make_action_button("[3] 逃跑")
	# 道具功能还没做，按钮常驻禁用。文案不写 [4]，免得承诺一个根本不存在的快捷键。
	_btn_item = _make_action_button("道具（未开放）")
	_btn_item.disabled = true
	for btn in [_btn_attack, _btn_action, _btn_flee, _btn_item]:
		_action_row.add_child(btn)

	_btn_attack.pressed.connect(_on_attack)
	_btn_action.pressed.connect(_open_action_menu)
	_btn_flee.pressed.connect(_on_flee)

	_submenu = HBoxContainer.new()
	_submenu.add_theme_constant_override("separation", 12)
	_submenu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_submenu.visible = false
	bottom.add_child(_submenu)

	_btn_defend = _make_action_button("防御")
	_btn_investigate = _make_action_button("调查")
	_submenu.add_child(_btn_defend)
	_submenu.add_child(_btn_investigate)
	_btn_defend.pressed.connect(_on_defend)
	_btn_investigate.pressed.connect(_on_investigate)

	_prompt = Label.new()
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_color", Palette.BODY_TEXT)
	bottom.add_child(_prompt)


## 带描边的面板。内部控件默认不吃鼠标，点击才会落到根节点的 _gui_input
func _make_panel(border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _make_label(text: String, color: Color, align: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	return label


func _make_hp_bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 16)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var track := StyleBoxFlat.new()
	track.bg_color = Palette.BAR_TRACK
	track.border_color = Palette.BAR_BORDER
	track.set_border_width_all(1)
	track.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.BAR_HIGH
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _make_action_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE   # 免得回车去"按"上一个点过的按钮
	btn.custom_minimum_size = Vector2(0, 44)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	btn.add_theme_stylebox_override("normal", _btn_style(Palette.INPUT_BG, Palette.CYAN_DEEP))
	btn.add_theme_stylebox_override("hover", _btn_style(Palette.CYAN_DEEP, Palette.CYAN_DEEP))
	btn.add_theme_stylebox_override("pressed", _btn_style(Palette.CYAN_DEEP.darkened(0.25), Palette.CYAN_DEEP))
	btn.add_theme_stylebox_override("disabled", _btn_style(Palette.DISABLED_BG, Palette.DISABLED_FG))
	btn.add_theme_color_override("font_color", Palette.BODY_TEXT)
	btn.add_theme_color_override("font_hover_color", Palette.BG)
	btn.add_theme_color_override("font_pressed_color", Palette.BG)
	btn.add_theme_color_override("font_disabled_color", Palette.DISABLED_FG)
	return btn


func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	return sb


## ────────────────────────── 刷新 ──────────────────────────

## player_dmg / enemy_dmg 传 -1 表示本次不显示伤害数字
##
## 掉血时给血条叠一层"虚血"残影（Fx.ghost_drain），血条不是一步跳到新值。
func _refresh_bars(player_dmg: int = -1, enemy_dmg: int = -1) -> void:
	if _bm == null:
		return

	_player_name.text = _bm.player.name
	_enemy_name.text = _bm.enemy.name

	var pmax := maxi(1, _bm.player.max_hp)
	var pr := float(_bm.player.hp) / float(pmax)
	_player_bar.max_value = pmax
	_player_bar.value = _bm.player.hp
	_player_hp_label.text = "%d/%d" % [_bm.player.hp, pmax]
	_player_fill.bg_color = Palette.bar_color(pr)
	_player_dmg_label.text = ("-%d" % player_dmg) if player_dmg > 0 else ""
	if _player_prev_ratio >= 0.0:
		Fx.ghost_drain(_player_bar, _player_prev_ratio, pr)
	_player_prev_ratio = pr

	var emax := maxi(1, _bm.enemy.max_hp)
	var er := float(_bm.enemy.hp) / float(emax)
	_enemy_bar.max_value = emax
	_enemy_bar.value = _bm.enemy.hp
	_enemy_hp_label.text = "%d%%" % int(er * 100.0)
	_enemy_fill.bg_color = Palette.bar_color(er)
	_enemy_dmg_label.text = ("-%d" % enemy_dmg) if enemy_dmg > 0 else ""
	if _enemy_prev_ratio >= 0.0:
		Fx.ghost_drain(_enemy_bar, _enemy_prev_ratio, er)
	_enemy_prev_ratio = er


func _append_history(text: String) -> void:
	_history.append_text(Palette.render(text) + "\n")


## 显示一段文本：先打字，打完等玩家确认，确认后执行 cont_callback
func _display(text: String, cont_callback: Callable) -> void:
	_cont_callback = cont_callback
	_append_history(text)
	await _type_text(text)
	_wait_for_continue()


## 打字机。玩家点击/回车时把 _typing 置回 false 即快进（照 transition.gd 的写法）
func _type_text(text: String) -> void:
	_story.text = Palette.render(text)
	_story.visible_ratio = 0.0

	var speed: float = SPEED_PRESETS.get(str(GameEngine.settings.get("text_speed", "medium")), 0.03)
	if speed <= 0.0:
		_story.visible_ratio = 1.0
		return

	_typing = true
	# 用真实可见字数算时长：BBCode 标签不计入可见字符，
	# 按 String.length() 算的话带颜色的句子会明显比纯文本慢。
	var count := maxi(1, _story.get_total_character_count())
	var tw := create_tween()
	tw.tween_property(_story, "visible_ratio", 1.0, maxf(0.15, speed * float(count)))
	while _typing and _story.visible_ratio < 1.0:
		await get_tree().process_frame
	if not is_instance_valid(_story):
		return
	tw.kill()
	_story.visible_ratio = 1.0
	_typing = false


func _wait_for_continue() -> void:
	_prompt.text = "[ 点击 / Enter ] 继续"
	_cont_waiting = true


func _do_continue() -> void:
	if not _cont_waiting:
		return
	_cont_waiting = false
	_prompt.text = ""
	var cb := _cont_callback
	_cont_callback = Callable()
	if cb.is_valid():
		cb.call()


## ────────────────────────── 回合流程 ──────────────────────────

func _start_turn() -> void:
	_close_action_menu()
	if _bm.battle_over:
		_end_battle()
		return
	_refresh_bars()
	if _bm.is_player_turn():
		_set_action_enabled(true)
	else:
		_set_action_enabled(false)
		_enemy_turn()


## 按钮的统一开关。禁用时把 mouse_filter 也设成 IGNORE，
## 否则"点击=继续"会被这些禁用按钮吃掉（禁用按钮默认仍然拦截鼠标）
func _set_action_enabled(enabled: bool) -> void:
	if _btn_attack == null:
		return
	_btn_attack.disabled = not enabled
	_btn_action.disabled = not enabled
	_btn_flee.disabled = not enabled
	_btn_item.disabled = true
	for btn in [_btn_attack, _btn_action, _btn_flee, _btn_item]:
		btn.mouse_filter = Control.MOUSE_FILTER_STOP if not btn.disabled else Control.MOUSE_FILTER_IGNORE


func _open_action_menu() -> void:
	if _cont_waiting or _typing or _bm == null or not _bm.is_player_turn():
		return
	_action_row.visible = false
	_submenu.visible = true
	var can_defend: bool = _bm.can_defend()
	_btn_defend.disabled = not can_defend
	_btn_defend.mouse_filter = Control.MOUSE_FILTER_IGNORE if not can_defend else Control.MOUSE_FILTER_STOP


func _close_action_menu() -> void:
	if _action_row == null:
		return
	_action_row.visible = true
	_submenu.visible = false


func _on_attack() -> void:
	if _cont_waiting or _typing or _bm == null or not _bm.is_player_turn():
		return
	_set_action_enabled(false)
	_close_action_menu()
	var res: Dictionary = _bm.player_attack()
	_refresh_bars(-1, int(res["dmg"]))
	_display(str(res["text"]), _start_turn)


func _on_defend() -> void:
	if _cont_waiting or _typing or _bm == null or not _bm.is_player_turn():
		return
	_set_action_enabled(false)
	_close_action_menu()
	var text: String = _bm.player_defend()
	_refresh_bars()
	_display(text, _start_turn)


func _on_investigate() -> void:
	if _cont_waiting or _typing or _bm == null or not _bm.is_player_turn():
		return
	_set_action_enabled(false)
	_close_action_menu()
	var text: String = _bm.player_investigate()
	_refresh_bars()
	_display(text, _start_turn)


func _on_flee() -> void:
	if _cont_waiting or _typing or _bm == null or not _bm.is_player_turn():
		return
	_set_action_enabled(false)
	_close_action_menu()
	var res: Dictionary = _bm.player_flee()
	if bool(res.get("success", false)):
		_refresh_bars()
		_display(str(res["text"]), _close_battle)
	else:
		_refresh_bars()
		_display(str(res["text"]), _start_turn)


func _enemy_turn() -> void:
	var res: Dictionary = _bm.enemy_act()
	_refresh_bars(int(res["dmg"]), -1)
	_display(str(res["text"]), _start_turn)


## ────────────────────────── 结束 ──────────────────────────

func _end_battle() -> void:
	if _bm.player_won:
		_bm.finalize()
		if not _post_battle.is_empty():
			GameEngine.apply_effects(_post_battle)   # 选项里写的战后效果（开箱、置 flag 等）
		var rewards: Dictionary = _bm.apply_rewards()
		_show_victory(rewards)
	else:
		_bm.finalize()
		_set_action_enabled(false)
		_append_history("<fire>你被击败了……</fire>")
		_display("<fire>你失去了意识……</fire>", _close_battle)


func _show_victory(rewards: Dictionary) -> void:
	_set_action_enabled(false)

	var victory_msg := _bm.get_narrative("victory", "战斗胜利！")
	var lines: Array = [victory_msg]

	var reward_lines: Array = ["[color=#ffdd00]━━ 战利品 ━━[/color]"]
	var xp := int(rewards.get("xp", 0))
	if xp > 0:
		reward_lines.append("[color=#c5c6c7]经验值 +%d[/color]" % xp)
	for drop_id in rewards.get("drops", []):
		var item_def: Dictionary = GameEngine.get_item_def(str(drop_id))
		var item_name := str(drop_id)
		if not item_def.is_empty():
			item_name = str(item_def.get("name", drop_id))
		reward_lines.append("[color=#66fcf1]获得物品: %s[/color]" % item_name)
	if reward_lines.size() > 1:
		lines.append("\n".join(reward_lines))

	_display("\n".join(lines), _close_battle)


## 结束战斗：通知 GamePlay 刷新（死亡时 GamePlay 会自己切到结局画面），然后自毁
func _close_battle() -> void:
	finished.emit()
	queue_free()
