import random
import asyncio
import re
import math
from textual.widgets import Static
from rich.text import Text

SPEED_PRESETS = {
    "instant": 0,
    "fast": 0.01,
    "medium": 0.03,
    "slow": 0.06,
}

STYLE_TAGS = {
    "fire": "bold red",
    "ice": "bold #66ccff",
    "poison": "bold #88ff00",
    "heal": "bold #00ff88",
    "holy": "bold #ffdd00",
    "shadow": "italic #444466",
    "whisper": "italic #888888",
    "scream": "bold #ff0000",
    "dim": "dim #888888",
}

FLOW_TAGS_SET = {"retract", "pause"}


def convert_custom_tags(text: str) -> str:
    for tag, style in STYLE_TAGS.items():
        text = text.replace(f"<{tag}>", f"[{style}]")
        text = text.replace(f"</{tag}>", f"[/{style}]")
    for tag in FLOW_TAGS_SET:
        text = text.replace(f"<{tag}/>", "")
    return text

# ==========================================
# 打字机效果  -  支持自定义 XML 标签
# ==========================================
class TypewriterLog(Static):
    markup = True

    STYLE_TAGS = STYLE_TAGS
    ANIM_TAGS = {"shake", "flash", "wave"}
    FLOW_TAGS = FLOW_TAGS_SET

    SHAKE_POOL = [
        '@', '#', '$', '%', '&', '?', '!',
        '\u039e', '\u00d8', '\u2206', '\u2207',
        '\u2211', '\u220f', '\u222b',
    ]

    ANIM_FPS = 20
    ANIM_DURATION = 3.0

    # ---------- 公开接口 ----------

    def on_click(self):

        if hasattr(self, '_tw_timer') and self._tw_timer is not None:
            self._stop_all()
            self.update(self._build_final_display())
            if self._tw_on_complete:
                try:
                    self._tw_on_complete()
                except Exception:
                    pass

    def on_unmount(self):
        self._stop_all()

    def type_text(self, full_text: str, speed=0.02, on_complete=None):
        self._stop_all()

        if isinstance(speed, str):
            speed = SPEED_PRESETS.get(speed, 0.03)

        self._tw_on_complete = on_complete
        self._tw_segments = self._parse(full_text)
        self._tw_seg_index = 0
        self._tw_char_index = 0
        self._tw_state = "typing"

        if speed <= 0:
            self.update(self._build_final_display())
            if self._tw_on_complete:
                try:
                    self._tw_on_complete()
                except Exception:
                    pass
            return

        self._tw_timer = self.set_interval(speed, self._tw_step)

    # ---------- 标签解析 ----------

    def _parse(self, text):
        segments = []
        i = 0
        while i < len(text):
            if text[i] != '<':
                nxt = text.find('<', i)
                if nxt == -1:
                    segments.append({"type": "text", "content": text[i:]})
                    break
                segments.append({"type": "text", "content": text[i:nxt]})
                i = nxt
                continue

            close = text.find('>', i)
            if close == -1:
                segments.append({"type": "text", "content": text[i:]})
                break

            tag_content = text[i + 1:close]

            if tag_content.startswith('/'):
                i = close + 1
                continue

            if tag_content.endswith('/'):
                tag_name = tag_content[:-1].strip()
                if tag_name in self.FLOW_TAGS:
                    segments.append({"type": tag_name, "content": ""})
                else:
                    segments.append({"type": "text", "content": f"<{tag_content}>"})
                i = close + 1
                continue

            tag_name = tag_content.strip()
            closing_tag = f"</{tag_name}>"
            end = text.find(closing_tag, close)

            if end == -1:
                segments.append({"type": "text", "content": text[i:]})
                break

            inner = text[close + 1:end]
            known = (
                tag_name in self.STYLE_TAGS
                or tag_name in self.ANIM_TAGS
                or tag_name in self.FLOW_TAGS
            )
            if known:
                segments.append({"type": tag_name, "content": inner})
            else:
                segments.append({"type": "text", "content": f"<{tag_name}>{inner}</{tag_name}>"})

            i = end + len(closing_tag)

        return segments

    # ---------- 打字机步进 ----------

    def _tw_step(self):
        if self._tw_state == "pausing":
            return

        if self._tw_state == "retracting":
            n = min(4, self._tw_char_index)
            self._tw_char_index -= n
            self.update(self._build_current_display())
            if self._tw_char_index <= 0:
                self._tw_state = "typing"
                self._tw_seg_index += 1
                self._tw_char_index = 0
            return

        while self._tw_seg_index < len(self._tw_segments):
            seg = self._tw_segments[self._tw_seg_index]
            kind = self._classify(seg)
            content = seg["content"]

            if kind == "flow":
                if seg["type"] == "pause":
                    self._tw_state = "pausing"
                    self.set_timer(0.5, self._resume_from_pause)
                    return
                if seg["type"] == "retract":
                    if self._tw_char_index >= len(content):
                        self._tw_state = "pausing"
                        self.set_timer(0.4, self._start_retracting)
                        return
                    self._tw_char_index += 1
                    self.update(self._build_current_display())
                    return

            if self._tw_char_index >= len(content):
                self._tw_seg_index += 1
                self._tw_char_index = 0
                continue

            self._tw_char_index += 1
            self.update(self._build_current_display())
            return

        self._stop_typewriter()
        self._start_animation()

    # ---------- 显示拼接 ----------

    def _build_current_display(self):
        parts = []
        for i in range(self._tw_seg_index):
            parts.append(self._seg_render(i, full=True))

        if self._tw_seg_index < len(self._tw_segments) and self._tw_state != "retracting":
            parts.append(self._seg_render(self._tw_seg_index, full=False))

        return self._strip_incomplete_markup("".join(parts))

    def _strip_incomplete_markup(self, text: str) -> str:
        last_open = text.rfind('[')
        if last_open == -1:
            return text
        close = text.find(']', last_open)
        if close == -1:
            return text[:last_open]
        tag_content = text[last_open + 1:close]
        if tag_content.startswith('/'):
            tag_name = tag_content[1:]
            open_tag = f'[{tag_name}]'
            if open_tag not in text:
                return text[:last_open]
        return text

    def _seg_render(self, idx, full):
        seg = self._tw_segments[idx]
        kind = self._classify(seg)
        content = seg["content"]

        if kind == "flow":
            if seg["type"] == "pause":
                return ""
            if seg["type"] == "retract":
                if self._tw_state == "retracting":
                    return ""
                return content if full else content[:self._tw_char_index]

        if not full and idx == self._tw_seg_index:
            partial = content[:self._tw_char_index]
        else:
            partial = content

        if kind == "style":
            style = self.STYLE_TAGS[seg["type"]]
            return f"[{style}]{partial}[/{style}]"

        return partial

    def _build_final_display(self):
        parts = []
        for seg in self._tw_segments:
            kind = self._classify(seg)
            content = seg["content"]
            if kind == "flow":
                if seg["type"] in ("retract", "pause"):
                    continue
            if kind == "style":
                style = self.STYLE_TAGS[seg["type"]]
                parts.append(f"[{style}]{content}[/{style}]")
            else:
                parts.append(content)
        return "".join(parts)

    # ---------- 流程控制 ----------

    def _resume_from_pause(self):
        self._tw_state = "typing"
        self._tw_seg_index += 1
        self._tw_char_index = 0

    def _start_retracting(self):
        self._tw_state = "retracting"

    # ---------- 动画循环 ----------

    def _start_animation(self):
        has = any(self._classify(s) == "anim" for s in self._tw_segments)
        if not has:
            self._finish_all()
            return

        self._anim_start_time = asyncio.get_event_loop().time()
        self._anim_timer = self.set_interval(1.0 / self.ANIM_FPS, self._anim_step)

    def _anim_step(self):
        elapsed = asyncio.get_event_loop().time() - self._anim_start_time

        if elapsed > self.ANIM_DURATION:
            self._stop_anim()
            self.update(self._build_final_display())
            self._finish_all()
            return

        parts = []
        for seg in self._tw_segments:
            kind = self._classify(seg)
            content = seg["content"]

            if kind == "flow":
                if seg["type"] in ("retract", "pause"):
                    continue
                parts.append(content)
                continue

            if kind == "anim":
                tag = seg["type"]
                if tag == "shake":
                    parts.append("".join(random.choice(self.SHAKE_POOL) for _ in content))
                elif tag == "flash":
                    t = (math.sin(elapsed * 8) + 1) / 2
                    r, g, b = int(255 * t), int(100 * (1 - t)), int(100 * (1 - t))
                    parts.append(f"[#{r:02x}{g:02x}{b:02x}]{content}[/]")
                elif tag == "wave":
                    buf = []
                    for j, ch in enumerate(content):
                        t = (math.sin(elapsed * 6 + j * 0.8) + 1) / 2
                        r, g = int(100 + 155 * t), int(150 + 105 * (1 - t))
                        buf.append(f"[#{r:02x}{g:02x}ff]{ch}[/]")
                    parts.append("".join(buf))
                continue

            if kind == "style":
                parts.append(f"[{self.STYLE_TAGS[seg['type']]}]{content}[/]")
                continue

            parts.append(content)

        self.update("".join(parts))

    # ---------- 辅助 ----------

    def _classify(self, seg):
        t = seg["type"]
        if t == "text":
            return "text"
        if t in self.STYLE_TAGS:
            return "style"
        if t in self.ANIM_TAGS:
            return "anim"
        if t in self.FLOW_TAGS:
            return "flow"
        return "text"

    def _finish_all(self):
        if self._tw_on_complete:
            try:
                self._tw_on_complete()
            except Exception:
                pass

    def _stop_typewriter(self):
        if hasattr(self, '_tw_timer') and self._tw_timer is not None:
            try:
                self._tw_timer.stop()
            except Exception:
                pass
            self._tw_timer = None

    def _stop_anim(self):
        if hasattr(self, '_anim_timer') and self._anim_timer is not None:
            try:
                self._anim_timer.stop()
            except Exception:
                pass
            self._anim_timer = None

    def _stop_all(self):
        self._stop_typewriter()
        self._stop_anim()


# ==========================================
# 视觉特效管理器
# ==========================================
class FXManager:
    """视觉特效管理器"""

    @staticmethod
    def play_shake(widget, base_text: str, duration: float = 1.0, speed: float = 0.05):
        """组件抖动效果"""
        widget.run_worker(FXManager._shake_worker(widget, base_text, duration, speed), exclusive=True)

    @staticmethod
    async def _shake_worker(widget, base_text: str, duration: float, speed: float):
        end_time = asyncio.get_event_loop().time() + duration
        while asyncio.get_event_loop().time() < end_time:
            spaces = " " * random.randint(0, 2)
            try:
                widget.update(f"{spaces}{base_text}")
            except Exception:
                pass
            await asyncio.sleep(speed)
        try:
            widget.update(base_text)
        except Exception:
            pass

    @staticmethod
    def play_fade_out(widget, base_text: str):
        """文字渐隐效果"""
        widget.run_worker(FXManager._fade_worker(widget, base_text), exclusive=True)

    @staticmethod
    async def _fade_worker(widget, base_text: str):
        clean_text = re.sub(r'\[.*?\]', '', base_text)
        color_steps = ["#ff007f", "#880044", "#440022", "#110005", "#0b0c10"]
        for color in color_steps:
            try:
                widget.update(f"[{color}]{clean_text}[/{color}]")
            except Exception:
                pass
            await asyncio.sleep(0.15)

    @staticmethod
    async def play_opacity_fade(widget, duration: float = 0.5, steps: int = 5):
        """通用透明度渐变消失动画"""
        for i in range(steps):
            opacity = 1.0 - (i + 1) / steps
            try:
                widget.styles.opacity = max(0.0, opacity)
            except Exception:
                pass
            await asyncio.sleep(duration / steps)
        try:
            widget.update("")
            widget.styles.opacity = 1.0
        except Exception:
            pass

    @staticmethod
    async def play_border_brighten(widget, duration: float = 1.0, color: str = None):
        """边框由灰暗渐变到亮色（默认蓝色苏醒，可自定义如红色死亡）"""
        if color:
            target = color
        else:
            target = "#45ddff"
        border_colors = [
            "#333333", "#3a3a3a", "#444444", "#4e4e4e",
            "#555555", "#5a6a7a", "#5a7a8a", "#5599aa",
            "#45aacc", "#45bbdd", target,
        ]
        step_duration = duration / len(border_colors)
        for color in border_colors:
            try:
                widget.styles.border = ("solid", color)
            except Exception:
                pass
            await asyncio.sleep(step_duration)
