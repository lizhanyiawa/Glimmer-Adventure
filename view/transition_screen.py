from textual.screen import Screen
from textual.widgets import Static
from textual import work
import asyncio

from engine.effects import TypewriterLog, FXManager

class TransitionScreen(Screen):
    BINDINGS = [
        ("enter", "continue", "继续"),
        ("space", "continue", "继续"),
    ]

    CSS = """
    TransitionScreen {
        align: center middle;
        background: #0b0c10;
    }
    #trans_text {
        color: #c5c6c7;
        text-align: center;
        width: 50;
        height: auto;
    }
    #trans_prompt {
        color: #666666;
        text-align: center;
        width: 50;
        height: 1;
        margin-top: 1;
    }
    """

    def compose(self):
        yield TypewriterLog("", id="trans_text")
        yield Static("", id="trans_prompt")

    def on_mount(self):
        self._cont = asyncio.Event()
        self.play_transition()

    def action_continue(self):
        self._cont.set()

    def on_click(self):
        self._cont.set()

    @work(exclusive=True)
    async def play_transition(self):
        widget = self.query_one("#trans_text", TypewriterLog)
        prompt = self.query_one("#trans_prompt", Static)

        # 初始清空
        widget.update("")
        
        lines = [
            "[dim]高数课上，老师在讲台上滔滔不绝地推导着傅里叶变换....[/dim]",
            "[dim]你趴在桌上，眼皮越来越重。[/dim]",
            "[dim]讲台上的声音渐渐远去，变成了模糊的嗡鸣...[/dim]",
            "[dim]. . .[/dim]",
            "[#444444]你坠入了一片无边的黑暗。[/#444444]",
            "[#333333]耳边有奇怪的低语，像电流，又像古老的咒文。[/#333333]",
            "[#555555]意识在混沌中漂浮，你分不清过了多久。[/#555555]",
            "[#777777]远处似乎有一点微光...[/#777777]",
            "[#999999]光越来越近，越来越亮。[/#999999]",
            "[#bbbbbb]你猛地睁开了眼睛。[/#bbbbbb]",
            "[#c5c6c7]你躺在一张硬邦邦的床上，头顶是低矮的茅草屋顶。[/#c5c6c7]",
            "[#c5c6c7]床头柜上，一盏蜡烛摇曳着微弱的火光。[/#c5c6c7]",
            "[#c5c6c7]这不是你的教室。[/#c5c6c7]",
        ]

        for i, line in enumerate(lines):
            prompt.update("")
            self._cont.clear()
            await self._type_line(widget, line)
            prompt.update("[#666666]▼ [Enter] 继续[/#666666]")
            self._cont.clear()
            await self._cont.wait()

        # 逐行扫描消失效果 (调用封装好的特效)
        prompt.update("")
        await FXManager.play_opacity_fade(widget, duration=0.8, steps=8)
        
        await asyncio.sleep(0.5)
        
        self.app.pop_screen()
        from view.game_menu import GamePlayScreen
        self.app.push_screen(GamePlayScreen())

    async def _type_line(self, widget, text, speed=0.015):
        done = asyncio.Event()
        widget.type_text(text, speed=speed, on_complete=lambda: done.set())
        await done.wait()