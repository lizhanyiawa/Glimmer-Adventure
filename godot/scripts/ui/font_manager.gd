extends Node
## 全局字体管理（autoload：FontManager），对应设置里的「字体风格」。
##
## 三种风格都写在同一份主题资源 res://assets/theme/game_theme.tres 上，
## 切换时只改它的 default_font，所有界面立刻跟着变，不用逐个节点改字体。
##
## 新增一种字体的步骤：把字体文件丢进 assets/fonts/，在下面加一行映射即可。

const THEME_PATH := "res://assets/theme/game_theme.tres"
const ARK_PIXEL_PATH := "res://assets/fonts/ark_pixel_12px_zh_hans.woff2"
const ZPIX_PATH := "res://assets/fonts/zpix.ttf"

## 系统字体候选（找不到第一个就用后面的，最后兜底 sans-serif）
const SYSTEM_FONT_NAMES: Array = [
	"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "sans-serif",
]

## 顺序即设置界面里点击循环的顺序
const STYLE_ORDER: Array = ["system", "ark_pixel", "zpix"]
const STYLE_LABELS: Dictionary = {
	"system": "系统默认",
	"ark_pixel": "方舟像素",
	"zpix": "最像素",
}

## ── 字号 ──
## 两款像素字体都按 12px 设计，只有字号是 12 的整数倍时才清晰，
## 所以界面字号只提供两档：1 = 正文 12px，2 = 正文 24px。
const BASE_ATOM: int = 12
const LEVEL_ORDER: Array = [1, 2]
const LEVEL_LABELS: Dictionary = {1: "标准", 2: "放大"}
## 标题比正文大一档，同样保持 12 的整数倍（正文 12 → 标题 24；正文 24 → 标题 36）
const HEADING_EXTRA: int = 12
## 需要跟随字号档位的控件类型 → 它们在主题里的字号项名
const SIZED_TYPES: Dictionary = {
	"Label": "font_size",
	"Button": "font_size",
	"RichTextLabel": "normal_font_size",
}

var _theme: Theme = null
var _fonts: Dictionary = {}
var _current: String = "system"
var _level: int = 1


func _ready() -> void:
	_theme = load(THEME_PATH) as Theme
	_fonts["system"] = _make_system_font()
	_fonts["ark_pixel"] = _load_pixel_font(ARK_PIXEL_PATH)
	_fonts["zpix"] = _load_pixel_font(ZPIX_PATH)
	# GameEngine 在 autoload 里排在前面，此时它的 settings 已经读好了
	apply(GameEngine.settings.get("font_style", "system"))
	apply_level(int(GameEngine.settings.get("ui_font_level", 1)))


## 切换字体风格；未知值或字体加载失败都回退到系统字体
func apply(style: String) -> void:
	if not _fonts.has(style) or _fonts[style] == null:
		style = "system"
	_current = style
	if _theme != null:
		_theme.default_font = _fonts[style]


## 切换界面字号档位（1 = 标准 12px，2 = 放大 24px）
func apply_level(level: int) -> void:
	if not LEVEL_ORDER.has(level):
		level = 1
	_level = level
	if _theme == null:
		return
	var atom := BASE_ATOM * _level
	_theme.default_font_size = atom
	# 显式给几个基础控件定字号，免得它们各自回退到 Godot 内置主题的 16px
	for type in SIZED_TYPES:
		_theme.set_font_size(SIZED_TYPES[type], type, atom)
	# 标题走主题里的 "Heading" 类型变体，Modal.tscn / GamePlay.tscn 的标题都挂了它
	_theme.set_font_size("font_size", "Heading", atom + HEADING_EXTRA)


func current_level() -> int:
	return _level


func level_label(level: int) -> String:
	return LEVEL_LABELS.get(level, str(level))


## 切到下一个字号档位并立即生效，返回新档位
func cycle_level() -> int:
	var idx := LEVEL_ORDER.find(_level)
	apply_level(LEVEL_ORDER[(idx + 1) % LEVEL_ORDER.size()] if idx != -1 else 1)
	return _level


func style_label(style: String) -> String:
	return STYLE_LABELS.get(style, style)


## 当前的字体风格名（设置界面显示用）
func current_style() -> String:
	return _current


## 切到下一个风格并立即生效，返回新风格名
func cycle_style() -> String:
	var idx := STYLE_ORDER.find(_current)
	var next: String = STYLE_ORDER[(idx + 1) % STYLE_ORDER.size()] if idx != -1 else "system"
	apply(next)
	return next


func _make_system_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(SYSTEM_FONT_NAMES)
	return font


## 像素字体按点阵渲染：关掉抗锯齿、亚像素定位和字形微调，边缘才干净。
## 字号统一由 apply_level() 控制，只取 12 的整数倍，所以这里不用逐节点调。
func _load_pixel_font(path: String) -> FontFile:
	var font := load(path) as FontFile
	if font == null:
		push_error("像素字体加载失败: %s" % path)
		return null
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.hinting = TextServer.HINTING_NONE
	return font
