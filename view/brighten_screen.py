from textual.screen import Screen
from textual.widgets import Static
from textual import work
import asyncio
from engine.effects import FXManager
from view.game_menu import GamePlayScreen


class BrightenScreen(Screen):
    CSS = """
    BrightenScreen {
        align: center middle;
        background: #0b0c10;
    }
    #wake_box {
        width: 50;
        height: 16;
        border: solid #333333;
        background: #1a1a1a;
        align: center middle;
        content-align: center middle;
    }
    #wake_text {
        color: #555555;
        text-align: center;
    }
    """

    def compose(self):
        with Static(id="wake_box"):
            yield Static("...", id="wake_text")

    def on_mount(self):
        self.run_brighten()

    @work(exclusive=True)
    async def run_brighten(self):
        box = self.query_one("#wake_box")

        await FXManager.play_border_brighten(box, duration=1.0)
        await asyncio.sleep(0.3)

        self.app.pop_screen()

        engine = self.app.engine
        if not engine.state.flags.get("intro_monologue_done", False):
            engine.state.dialogue_id = "intro_wake_1"

        self.app.push_screen(GamePlayScreen())