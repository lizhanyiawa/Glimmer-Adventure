class_name Palette
extends RefCounted
## 全局视觉风格：所有颜色 + 剧情文字的标签/特效，唯一出处。
##
## 为什么单独一个文件：以前颜色散落在各个界面脚本和场景里，想调一个颜色要
## 翻好几处，而且改完还容易对不上。现在颜色和文字特效都集中在这里，
## 它不依赖 scripts/core/ 里的任何引擎代码（纯常量 + 静态函数），
## 所以是和引擎解耦的——想换配色只改这一个文件。
##
## 剧情数据里的 <fire> <shadow> <shake> 等自定义标签，也在这里统一转成
## RichTextLabel 认得的 BBCode。标签名与 Python 版完全一致，data/ 不用改。

# ────────────────────────── 底色 / 面板 ──────────────────────────

const BG := Color("0b0c10")             # 全局底色
const PANEL := Color("161923")          # 面板底色（故事框、状态栏）
const PANEL_ALT := Color("0f1016")      # 次级面板（历史记录）
const MODAL_BG := Color("161923")       # 弹窗底
const MODAL_BTN := Color("23283b")      # 弹窗按钮底
const INPUT_BG := Color("1a1e2a")       # 输入框 / 战斗按钮底

# ────────────────────────── 文字 ──────────────────────────

const BODY_TEXT := Color("c5c6c7")      # 正文
const MUTED := Color("b2b2b2")          # 次要文字
const DIM := Color("888888")            # 更弱的文字
const DISABLED_BG := Color("111111")
const DISABLED_FG := Color("333333")

# ────────────────────────── 强调色 ──────────────────────────

const CYAN := Color("66fcf1")           # 主色：终端青
const CYAN_DEEP := Color("45f3ff")      # 更亮的青（描边）
const PINK := Color("ff007f")           # 人物 / 确认
const GOLD := Color("ffaa00")           # 位置 / 保存 / 设置
const AMBER := Color("ddaa00")          # 装备
const GREEN := Color("00ff66")          # 读取 / 正向
const RED := Color("ff4444")            # 危险 / 负向

# ────────────────────────── 血条 / 理智条 ──────────────────────────
# 与 Python 版一致：高=青、中=琥珀、低=红。之前用纯红/纯绿实心条，
# 和整体的终端青风格完全不搭，这里统一回青色系。

const BAR_HIGH := Color("66fcf1")
const BAR_MID := Color("ffaa00")
const BAR_LOW := Color("ff4444")
const BAR_TRACK := Color("232833")      # 空槽
const BAR_BORDER := Color("3a4150")
## 掉血时的"虚血"残影：白色半透明，慢慢排空，避免血条生硬地一跳到底
const BAR_GHOST := Color(0.85, 0.85, 0.9, 0.34)

# ────────────────────────── 剧情文字样式标签 ──────────────────────────
# key 与 Python 版 STYLE_TAGS 一致；颜色是这里唯一的一份。
#
# fire 原来写成 #ff0000 纯红，结果"烛光""灯光""暖意"这类暖色描写也一起变红，
# 看着像警告色。现在改成暖橙，火焰/灯光都读得通；真正表示"痛苦/尖叫"的
# scream 保留偏红，两者语义就不再打架了。

const TEXT_STYLES: Dictionary = {
	"fire": {"color": Color("ff8a3d"), "bold": true},
	"ice": {"color": Color("66ccff"), "bold": true},
	"poison": {"color": Color("88ff00"), "bold": true},
	"heal": {"color": Color("00ff88"), "bold": true},
	"holy": {"color": Color("ffdd00"), "bold": true},
	"shadow": {"color": Color("444466"), "italic": true},
	"whisper": {"color": Color("888888"), "italic": true},
	"scream": {"color": Color("ff5a5a"), "bold": true},
	"dim": {"color": Color("888888")},
}

## 动效标签：直接映射到 RichTextLabel 自带的 BBCode 特效。
const TEXT_ANIMS: Dictionary = {
	"shake": {"open": "[shake]", "close": "[/shake]"},
	"wave": {"open": "[wave]", "close": "[/wave]"},
	"flash": {"open": "[pulse]", "close": "[/pulse]"},
}

## 流程标签：控制打字节奏，本身不产生文字（本期直接去掉）。
const FLOW_TAGS: Array = ["pause", "retract"]


## 把剧情文本转成可以直接喂给 RichTextLabel 的 BBCode
static func render(text: String) -> String:
	return strip_flow_tags(to_bbcode(text))


## 自定义样式/动效标签 → BBCode
static func to_bbcode(text: String) -> String:
	var result := text
	for tag in TEXT_STYLES:
		var pair := _style_pair(TEXT_STYLES[tag])
		result = result.replace("<%s>" % tag, pair["open"])
		result = result.replace("</%s>" % tag, pair["close"])
	for tag in TEXT_ANIMS:
		var pair: Dictionary = TEXT_ANIMS[tag]
		result = result.replace("<%s>" % tag, pair["open"])
		result = result.replace("</%s>" % tag, pair["close"])
	return result


## 去掉 <pause/> <retract/> 这类流程标签
static func strip_flow_tags(text: String) -> String:
	var result := text
	for tag in FLOW_TAGS:
		result = result.replace("<%s/>" % tag, "")
	return result


## 由样式定义拼出 BBCode 开闭标签，如 [b][color=#ff5a5a]…[/color][/b]
static func _style_pair(spec: Dictionary) -> Dictionary:
	var open := ""
	var close := ""
	if spec.get("bold", false):
		open += "[b]"
		close = "[/b]" + close
	if spec.get("italic", false):
		open += "[i]"
		close = "[/i]" + close
	var color: Color = spec["color"]
	open += "[color=#%s]" % color.to_html(false)
	close = "[/color]" + close
	return {"open": open, "close": close}


# ────────────────────────── 血条取色 ──────────────────────────

## 按当前比例取血条颜色：<30% 红、<60% 琥珀、否则青
static func bar_color(ratio: float) -> Color:
	if ratio < 0.3:
		return BAR_LOW
	if ratio < 0.6:
		return BAR_MID
	return BAR_HIGH
