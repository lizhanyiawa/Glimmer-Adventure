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
const GREEN := Color("00ff66")          # 读取 / 正向 / 对话
const RED := Color("ff4444")            # 危险 / 负向 / 战斗
const VIOLET := Color("cc44ff")         # 理智低落
const BLUE := Color("5aa9ff")           # 移动 / 返回

# ────────────────────────── 整屏色调 ──────────────────────────
# 主玩法画面按当前处境给整屏定调（对应 Python 版 game_menu.py 的 _update_ui_colors）：
# 对话中=绿、濒死=红、理智<30=紫、重伤=琥珀、常态=青。
# 这里存的是"整屏底色"，面板底色由 game_play.gd 往这个底色靠拢算出来。

const BG_DIALOGUE := Color("0a1a0a")    # 对话中
const BG_DANGER := Color("1a0505")      # 濒死（HP < 10%）
const BG_MADNESS := Color("0f0a1a")     # 理智 < 30
const BG_HURT := Color("1a1a05")        # 重伤（HP < 30%）

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
	"blight": {"color": Color("bb55ff"), "bold": true},   # 腐化 / 紫斑（官方叫「北病 / 紫斑灾」）
	"warn": {"color": Color("ff4444"), "bold": true},     # 警告 / 危险
	"dim": {"color": Color("888888")},
}

## 动效标签：直接映射到 RichTextLabel 自带的 BBCode 特效。
## 剧情文字里写 <shake>抖一下</shake> 就会动起来，颜色与粗斜体可叠加。
## 只留引擎确定支持的几个，写错了会原样显示成 "[xxx]" 反而难看。
const TEXT_ANIMS: Dictionary = {
	"shake": {"open": "[shake]", "close": "[/shake]"},        # 抖动：剧痛 / 恐惧 / 冲击
	"wave": {"open": "[wave]", "close": "[/wave]"},           # 波浪：轻晃 / 眩晕 / 沉甸甸的分量
	"flash": {"open": "[pulse]", "close": "[/pulse]"},        # 明暗脉动：低语 / 闪烁
	"breathe": {"open": "[pulse]", "close": "[/pulse]"},      # 呼吸：微光 / 月光 / 缓慢的明灭
	"fade": {"open": "[fade]", "close": "[/fade]"},           # 淡入淡出：记忆 / 远去
	"rainbow": {"open": "[rainbow]", "close": "[/rainbow]"},  # 流光变色：辉 / 异象
	"tornado": {"open": "[tornado]", "close": "[/tornado]"},  # 旋转扭曲：失控 / 腐化
}

## 顺手认一下 HTML 写法的 <b> <i>：手写数据时很容易顺手敲成 HTML 风格，
## 不认的话会原样显示成 "<b>极其罕见</b>"，看起来像是加粗没生效。
## 注意匹配的是带尖括号的完整标签，不会误伤 <blight> 这类以 b 开头的自定义标签。
const SIMPLE_TAGS: Dictionary = {
	"b": "b",
	"i": "i",
}

## 流程标签：控制打字节奏，本身不产生文字（本期直接去掉）。
const FLOW_TAGS: Array = ["pause", "retract"]


## 把剧情文本转成可以直接喂给 RichTextLabel 的 BBCode
static func render(text: String) -> String:
	return strip_flow_tags(to_bbcode(text))


## 历史记录 / 日志用：去掉动效标签，只留颜色、粗体这些静态样式。
## 历史框是越积越长的常驻节点，让里面的 <shake> 一直抖既吵又费性能。
static func render_static(text: String) -> String:
	return strip_flow_tags(to_bbcode(strip_anim_tags(text)))


## 去掉 <shake> <wave> 这类动效开闭标签（保留标签之间的文字）
static func strip_anim_tags(text: String) -> String:
	var result := text
	for tag in TEXT_ANIMS:
		result = result.replace("<%s>" % tag, "")
		result = result.replace("</%s>" % tag, "")
	return result


## 自定义样式/动效标签 → BBCode
static func to_bbcode(text: String) -> String:
	var result := text
	for tag in SIMPLE_TAGS:
		result = result.replace("<%s>" % tag, "[%s]" % SIMPLE_TAGS[tag])
		result = result.replace("</%s>" % tag, "[/%s]" % SIMPLE_TAGS[tag])
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


# ────────────────────────── 选项按钮类型配色 ──────────────────────────

## 选项文字形如「【探索】走进森林」，方括号里的词就是动作类型。
## 按类型给按钮描边（悬停时直接拿类型色当底色），扫一眼就知道哪是探索、
## 哪是战斗、哪是交谈。认不出来的类型退回 OPTION_TYPE_DEFAULT。
const OPTION_TYPE_COLORS: Dictionary = {
	# 探索 / 查看
	"探索": CYAN, "观察": CYAN, "调查": CYAN, "检查": CYAN, "查看": CYAN, "搜索": CYAN,
	# 移动 / 退出
	"返回": BLUE, "离开": BLUE,
	# 交谈
	"对话": GREEN, "回答": GREEN, "接受": GREEN,
	# 交易 / 交付
	"交易": GOLD, "交付": GOLD,
	# 战斗 / 拒绝
	"战斗": RED, "拒绝": RED,
	# 拾取 / 开箱
	"拾取": AMBER, "开锁": AMBER,
	# 其他动作
	"动作": PINK, "起身": PINK, "思考": PINK, "休息": CYAN_DEEP,
}
const OPTION_TYPE_DEFAULT := CYAN

## 「查看类」动作：凑近看某个具体东西。这类选项去过一次就算翻过了，按钮会变暗。
##
## 【探索】【前往】【返回】这类"走动 / 往返"不在其中——路是会反复走的，
## 常亮才不会让"回村口""去广场"这种高频路径一直灰着。
const EXPLORE_TYPES: Array = ["观察", "调查", "检查", "查看", "搜索"]


## 从选项文字里取出「【类型】」并返回对应颜色
static func option_type_color(text: String) -> Color:
	var key := option_type_key(text)
	if OPTION_TYPE_COLORS.has(key):
		return OPTION_TYPE_COLORS[key]
	return OPTION_TYPE_DEFAULT


## 选项文字是否属于「查看类」动作
static func option_is_explore(text: String) -> bool:
	return EXPLORE_TYPES.has(option_type_key(text))


## 取出「【探索】」方括号里的类型词，取不到返回空串
static func option_type_key(text: String) -> String:
	var open := text.find("【")
	var close := text.find("】")
	if open >= 0 and close > open:
		return text.substr(open + 1, close - open - 1)
	return ""
