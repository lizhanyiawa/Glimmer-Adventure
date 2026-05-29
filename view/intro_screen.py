# view/intro_screen.py
from textual.screen import Screen
from textual.widgets import Static
from textual import work
import asyncio

class IntroScreen(Screen):
    CSS = """
    IntroScreen {
        align: center middle;
        background: #000000;
    }
    #logo {
        color: #66fcf1;
        text-align: center;
    }
    """

    def compose(self):
        yield Static("系统引导中...", id="logo")

    def on_mount(self):
        """画面一亮起，立刻异步播放动画"""
        self.play_intro_animation()

    @work(exclusive=True)
    async def play_intro_animation(self):
        logo_widget = self.query_one("#logo", Static)
        
        # 1. 跑码效果
        lines = [
            "CONNECTING TO OUTSIDER SERVER...",
            "DECODING REINCARNATION PROTOCOL... [OK]",
            "STABILIZING ISEKAI ENERGY WELL... [100%]",
            "\n"
        ]
        log_text = ""
        for line in lines:
            log_text += line + "\n"
            logo_widget.update(log_text)
            await asyncio.sleep(0.3)
            
        # 2. 轰然炸出大标题
        ascii_art = """
 █     █░▓█████  ██▓     ▄████▄   ▒█████   ███▄ ▄███▓▓█████ 
▓█░ █ ░█░▓█   ▀ ▓██▒    ▒██▀ ▀█  ▒██▒  ██▒▓██▒▀█▀ ██▒▓█   ▀ 
▒█░ █ ░█ ▒███   ▒██░    ▒▓█    ▄ ▒██░  ██▒▓██    ▓██░▒███   
░█░ █ ░█ ▒▓█  ▄ ▒██░    ▒▓▓▄ ▄██▒▒██   ██░▒██    ▒██ ▒▓█  ▄ 
░░██▒██▓ ░▒████▒░██████▒▒ ▓████▀ ░ ████▓▒░▒██▒   ░██▒░▒████▒
        """
        logo_widget.update(ascii_art)
        await asyncio.sleep(1.5) # 停留 1.5 秒让玩家看清楚
        
        # 3. 动画结束，通知总发动机卸载自己，切换到主菜单
        self.app.pop_screen()
        self.app.push_screen(self.app.main_menu_screen)