import re
from textual.screen import Screen
from textual.widgets import Static, Button, Input
from textual.containers import Vertical
from textual import on

from view.transition_screen import TransitionScreen

# 命名界面
class NamingScreen(Screen):
    """角色命名

    限制：最多 16 个汉字 / 32 个英文字符，禁止会引起代码解析问题的字符。
    """
    MAX_CJK = 16       # 中文字符上限
    MAX_ASCII = 32     # 英文字符上限
    FORBIDDEN = re.compile(r'[\x00-\x08\x0b\x0c\x0e-\x1f\\\'\"\n\r\t]')

    BINDINGS = [
        ("enter", "confirm", "确认"),
        ("escape", "cancel", "取消"),
    ]

    CSS = """
    NamingScreen { 
        align: center middle; 
        background: rgba(0, 0, 0, 0.85); 
    }
    #naming_box { 
        width: 50; 
        border: thick #00ffff; 
        background: #161923; 
        padding: 1 4; 
    }
    .label { 
        text-align: center; 
        color: #66fcf1; 
        margin-bottom: 1; 
    }
    Input { 
        background: #1f2833; 
        color: #ffffff; 
        border: tall #45f3ff; 
        margin-bottom: 2; 
    }
    #confirm_name_btn { 
        width: 100%; 
        background: #23283b; 
        color: white; 
        border: none; 
    }
    #confirm_name_btn:hover { 
        background: #00ffff; 
        color: #0b0c10; 
        text-style: bold; 
    }
    """

    def compose(self):
        with Vertical(id="naming_box"):
            yield Static("命名", classes="label")
            yield Static("输入你的名字:", classes="label")
            inp = Input(placeholder="", id="name_input")
            inp.submit_on_wrap = True
            yield inp
            yield Static("Enter 确认，ESC 取消", classes="label")
            yield Button("[Enter] 确认", id="confirm_name_btn")

    @on(Input.Submitted, "#name_input")
    def handle_submit(self):
        self.action_confirm()

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "confirm_name_btn":
            self.action_confirm()

    def action_confirm(self):
        raw = self.query_one("#name_input", Input).value.strip()
        if not raw:
            self.notify("请输入一个名字", title="提示")
            return

        if self.FORBIDDEN.search(raw):
            self.notify("名字中包含不允许的字符（如引号、斜杠、控制字符等）", title="命名失败")
            return

        # 统计字符数：CJK 字符 vs 其他
        cjk = 0
        ascii_chars = 0
        for ch in raw:
            if '\u4e00' <= ch <= '\u9fff' or '\u3400' <= ch <= '\u4dbf' or '\uf900' <= ch <= '\ufaff':
                cjk += 1
            else:
                ascii_chars += 1

        if cjk > self.MAX_CJK:
            self.notify(f"中文字符不能超过 {self.MAX_CJK} 个", title="命名失败")
            return
        if ascii_chars > self.MAX_ASCII:
            self.notify(f"英文字符不能超过 {self.MAX_ASCII} 个", title="命名失败")
            return

        self.app.engine.set_player_name(raw)
        real_name = self.app.engine.state.stats["player_name"]
        self.notify(f"命名成功: {real_name}", title="系统")

        self.app.pop_screen()
        self.app.push_screen(TransitionScreen())

    def action_cancel(self):
        self.app.pop_screen()
