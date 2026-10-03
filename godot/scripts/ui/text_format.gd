class_name TextFormat
extends RefCounted
## 剧情文本的标签转换（对应 Python 的 engine/effects.py 里的标签系统）。
##
## 剧情数据里用 <fire> <shadow> 这类自定义标签描述文字语气，
## 这里转成 RichTextLabel 认得的 BBCode。标签名与 Python 版完全一致，
## 所以 data/ 里的文本一个字都不用改。
##
## 动效标签：原 Python 版靠 ASCII 抖动/逐字换色硬凑，这里直接用
## RichTextLabel 的原生 BBCode 特效——同样是那几个标签名，data/ 不用改。
const ANIM_TAGS: Dictionary = {
	"shake": {"open": "[shake]", "close": "[/shake]"},
	"wave": {"open": "[wave]", "close": "[/wave]"},
	"flash": {"open": "[pulse]", "close": "[/pulse]"},
}

## 样式标签 → BBCode 开闭标签。key 与 Python 版 STYLE_TAGS 保持一致。
const STYLE_TAGS: Dictionary = {
	"fire": {"open": "[b][color=#ff0000]", "close": "[/color][/b]"},
	"ice": {"open": "[b][color=#66ccff]", "close": "[/color][/b]"},
	"poison": {"open": "[b][color=#88ff00]", "close": "[/color][/b]"},
	"heal": {"open": "[b][color=#00ff88]", "close": "[/color][/b]"},
	"holy": {"open": "[b][color=#ffdd00]", "close": "[/color][/b]"},
	"shadow": {"open": "[i][color=#444466]", "close": "[/color][/i]"},
	"whisper": {"open": "[i][color=#888888]", "close": "[/color][/i]"},
	"scream": {"open": "[b][color=#ff0000]", "close": "[/color][/b]"},
	"dim": {"open": "[color=#888888]", "close": "[/color]"},
}

## 流程标签：控制打字节奏，本身不产生文字。
## 本期先直接去掉（等同于"瞬间打完"），做打字机时再接回来。
const FLOW_TAGS: Array = ["pause", "retract"]

const SHAKE_POOL := "@#$%&?!ΞØ∆∇∑∏∫"


## 把剧情文本转成可以直接喂给 RichTextLabel 的 BBCode
static func render(text: String) -> String:
	return strip_flow_tags(to_bbcode(text))


## 自定义样式/动效标签 → BBCode
static func to_bbcode(text: String) -> String:
	var result := text
	for map in [STYLE_TAGS, ANIM_TAGS]:
		for tag in map:
			var pair: Dictionary = map[tag]
			result = result.replace("<%s>" % tag, pair["open"])
			result = result.replace("</%s>" % tag, pair["close"])
	return result


## 去掉 <pause/> <retract/> 这类流程标签
static func strip_flow_tags(text: String) -> String:
	var result := text
	for tag in FLOW_TAGS:
		result = result.replace("<%s/>" % tag, "")
	return result