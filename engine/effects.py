import random
import asyncio
import re
from textual.widgets import Static
from rich.text import Text

SPEED_PRESETS = {
    "instant": 0,
    "fast": 0.01,
    "medium": 0.03,
    "slow": 0.06,
}

# ==========================================
# 打字机效果
# ==========================================
class TypewriterLog(Static):
    markup = True

    def on_click(self):
        """点击时跳过打字机效果，直接显示全部"""
        if hasattr(self, '_tw_timer') and self._tw_timer is not None:
            self._stop_typewriter()
            self.update(self._tw_full)
            if self._tw_on_complete:
                try:
                    self._tw_on_complete()
                except Exception:
                    pass

    def type_text(self, full_text: str, speed=0.02, effect_type: str = "normal", on_complete=None):
        self._stop_typewriter()

        if isinstance(speed, str):
            speed = SPEED_PRESETS.get(speed, 0.03)

        if effect_type == "warning":
            full_text = f"[bold red]{full_text}[/bold red]"
        elif effect_type == "lust":
            full_text = f"[bold italic #ff007f]{full_text}[/bold italic #ff007f]"
        elif effect_type == "system":
            full_text = f"[cyan]{full_text}[/cyan]"

        self._tw_full = full_text
        self._tw_display = ""
        self._tw_index = 0
        self._tw_on_complete = on_complete

        # 如果速度为0（瞬时），直接显示全部并完成
        if speed <= 0:
            self.update(self._tw_full)
            if self._tw_on_complete:
                try:
                    self._tw_on_complete()
                except Exception:
                    pass
            return

        self._tw_timer = self.set_interval(speed, self._tw_step)

    def _tw_step(self):
        if self._tw_index >= len(self._tw_full):
            self._stop_typewriter()
            self.update(self._tw_full)
            if self._tw_on_complete is not None:
                try:
                    self._tw_on_complete()
                except Exception:
                    pass
            return

        if self._tw_full[self._tw_index] == '[':
            close_idx = self._tw_full.find(']', self._tw_index)
            if close_idx != -1:
                self._tw_display += self._tw_full[self._tw_index : close_idx + 1]
                self._tw_index = close_idx + 1
                try:
                    self.update(self._tw_display)
                except Exception:
                    pass
                return

        self._tw_display += self._tw_full[self._tw_index]
        self._tw_index += 1
        try:
            self.update(self._tw_display)
        except Exception:
            pass

    def _stop_typewriter(self):
        if hasattr(self, '_tw_timer') and self._tw_timer is not None:
            try:
                self._tw_timer.stop()
            except Exception:
                pass
            self._tw_timer = None


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
            widget.styles.opacity = 1.0  # 恢复透明度以便下次使用
        except Exception:
            pass
