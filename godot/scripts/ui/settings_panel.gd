class_name SettingsPanel
extends RefCounted
## 设置面板里「可循环切换的那些项」，主菜单与游戏内共用。
##
## 只做两件事：把 GameEngine.settings 渲染成一行行按钮、切换它们。
## 底部按钮（读取存档 / 退出 / 返回主菜单）由调用方按场景自己加。
##
## 用法：
##     SettingsPanel.fill(modal)                 # 填内容
##     SettingsPanel.toggle("font_style")        # 点某一行时切换

## 与 Python 版 global_settings.py 的取值顺序保持一致
const SPEED_ORDER: Array = ["instant", "fast", "medium", "slow"]
const SPEED_LABELS: Dictionary = {"instant": "即时", "fast": "快", "medium": "中", "slow": "慢"}
const CORRUPTION_RATES: Array = [0.0, 0.5, 1.0, 1.5, 2.0]
const HISTORY_OPTIONS: Array = [50, 100, 200, 500]


## 把设置项填进弹窗内容区（不清理，调用前请先 configure/clear_body）
static func fill(modal: GameModal) -> void:
	var s: Dictionary = GameEngine.settings
	# 字体风格与界面字号是「立即生效」的，切换后要顺带更新主题
	modal.add_toggle_row("字体风格", "toggle:font_style",
		FontManager.style_label(FontManager.current_style()))
	modal.add_toggle_row("界面字号", "toggle:ui_font_level",
		FontManager.level_label(FontManager.current_level()))
	modal.add_toggle_row("文字速度", "toggle:text_speed",
		str(SPEED_LABELS.get(s.get("text_speed", "medium"), "中")))
	modal.add_toggle_row("调试模式", "toggle:debug_mode",
		"开" if s.get("debug_mode", false) else "关")
	modal.add_toggle_row("侵蚀倍率", "toggle:corruption_rate",
		"%sx" % str(s.get("corruption_rate", 1.0)))
	modal.add_toggle_row("跳过开场动画", "toggle:skip_intro",
		"开" if s.get("skip_intro", false) else "关")
	modal.add_toggle_row("返回主菜单确认", "toggle:confirm_return",
		"开" if s.get("confirm_return", true) else "关")
	modal.add_toggle_row("退出游戏确认", "toggle:confirm_exit",
		"开" if s.get("confirm_exit", true) else "关")
	modal.add_toggle_row("覆盖存档提醒", "toggle:confirm_save",
		"开" if s.get("confirm_save", true) else "关")
	modal.add_toggle_row("历史记录上限(行)", "toggle:history_lines",
		str(s.get("history_lines", 200)))


## 切换某个设置项。只改内存里的 settings，落盘由调用方决定（ESC 关闭时统一保存）。
static func toggle(key: String) -> void:
	var s: Dictionary = GameEngine.settings
	match key:
		"font_style":
			s["font_style"] = FontManager.cycle_style()
		"ui_font_level":
			s["ui_font_level"] = FontManager.cycle_level()
		"text_speed":
			s["text_speed"] = _cycle(s, "text_speed", SPEED_ORDER, "medium")
		"debug_mode":
			s["debug_mode"] = not s.get("debug_mode", false)
		"corruption_rate":
			var rate: float = float(s.get("corruption_rate", 1.0))
			var idx: int = CORRUPTION_RATES.find(rate)
			s["corruption_rate"] = CORRUPTION_RATES[(idx + 1) % CORRUPTION_RATES.size()] if idx != -1 else 1.0
		"skip_intro":
			s["skip_intro"] = not s.get("skip_intro", false)
		"confirm_return":
			s["confirm_return"] = not s.get("confirm_return", true)
		"confirm_exit":
			s["confirm_exit"] = not s.get("confirm_exit", true)
		"confirm_save":
			s["confirm_save"] = not s.get("confirm_save", true)
		"history_lines":
			var lines: int = int(s.get("history_lines", 200))
			var idx2: int = HISTORY_OPTIONS.find(lines)
			s["history_lines"] = HISTORY_OPTIONS[(idx2 + 1) % HISTORY_OPTIONS.size()] if idx2 != -1 else 200


## 在当前值后面取下一个候选值，找不到就用 fallback 打头
static func _cycle(settings: Dictionary, key: String, order: Array, fallback):
	var idx: int = order.find(settings.get(key, fallback))
	return order[(idx + 1) % order.size()] if idx != -1 else fallback
