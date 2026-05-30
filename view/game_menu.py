import json
import os
from textual.screen import Screen
from textual.widgets import Static, Button, Input, Log, ListView, ListItem
from textual.containers import Horizontal, Container, Vertical
from textual.events import Key
from textual import on

from engine.effects import TypewriterLog

class LocationWidget(Static):
    def update_location(self, location: str):
        self.update(f"位置: {location}")

# 游戏主界面
class GamePlayScreen(Screen):
    BINDINGS = [
        ("1", "option1", "选项 1"),
        ("2", "option2", "选项 2"),
        ("3", "option3", "选项 3"),
        ("4", "option4", "选项 4"),
        ("p", "profile", "人物"),
        ("s", "save", "保存"),
        ("o", "settings", "设置"),
        ("escape", "menu", "菜单"),
    ]

    CSS = """
    GamePlayScreen {
        padding: 1;
        background: #0b0c10;
    }
    #status_bar {
        height: 3;
        background: #1f2833;
        border: solid #45f3ff;
        margin-bottom: 1;
    }
    #status_layout {
        layout: grid;
        grid-size: 3;
        grid-columns: 1fr 2fr 1fr;
        height: 100%;
        align: center middle;
    }
    .status_label {
        text-align: center;
        color: #66fcf1;
        content-align: center middle;
    }
    LocationWidget {
        background: #23283b;
        color: #ffaa00;
        text-align: center;
        content-align: center middle;
        text-style: bold;
    }
    #main_viewport {
        height: 16;
        margin-bottom: 1;
    }
    #story_box {
        width: 65%;
        height: 100%;
        border: solid #45f3ff;
        background: #1f2833;
        padding: 1 2;
    }
    #history_box {
        width: 35%;
        height: 100%;
        border: dashed #555555;
        background: #0f1016;
        margin-left: 1;
    }
    #bottom_console {
        height: 9;
    }
    #story_options {
        width: 65%;
        layout: grid;
        grid-size: 2 2;
        grid-columns: 1fr 1fr;
        grid-rows: 1fr 1fr;
        grid-gutter: 1 2;
    }
    #system_options {
        width: 35%;
        margin-left: 1;
        layout: grid;
        grid-size: 1 3;
        grid-rows: 1fr 1fr 1fr;
        grid-gutter: 0 0;
    }
    .opt_btn {
        background: #11141e;
        border: solid #45f3ff;
        color: #66fcf1;
        width: 100%;
        height: 100%;
        content-align: center middle;
    }
    .opt_btn:hover {
        background: #66fcf1;
        color: #0b0c10;
        text-style: bold;
    }
    .opt_btn:disabled {
        background: #1a1a24;
        color: #444444;
        border: solid #333333;
    }
    .sys_btn {
        background: #1f2833;
        border: none;
        color: #ffffff;
    }
    #btn_profile:hover {
        background: #ff007f;
        text-style: bold;
    }
    #btn_save:hover {
        background: #00ff66;
        color: #0b0c10;
        text-style: bold;
    }
    #btn_menu_settings:hover {
        background: #ffaa00;
        color: #0b0c10;
        text-style: bold;
    }
    """

    def compose(self):
        with Container(id="status_bar"):
            with Horizontal(id="status_layout"):
                yield Static("生命: 加载中...", id="lbl_hp", classes="status_label")
                yield LocationWidget("位置: 加载中...", id="lbl_location")
                yield Static("理智/污染: 加载中...", id="lbl_san", classes="status_label")

        with Horizontal(id="main_viewport"):
            yield TypewriterLog("", id="story_box")
            yield Log(id="history_box")

        with Horizontal(id="bottom_console"):
            with Container(id="story_options"):
                yield Button("[1] 选项 1", id="opt1", classes="opt_btn")
                yield Button("[2] 选项 2", id="opt2", classes="opt_btn")
                yield Button("[3] 选项 3", id="opt3", classes="opt_btn")
                yield Button("[4] 选项 4", id="opt4", classes="opt_btn")
            with Container(id="system_options"):
                yield Button("[P] 人物", id="btn_profile", classes="sys_btn")
                yield Button("[S] 保存", id="btn_save", classes="sys_btn")
                yield Button("[O] 设置", id="btn_menu_settings", classes="sys_btn")

    def on_mount(self):
        self.call_after_refresh(self.load_current_room)

    # 加载当前房间数据并刷新UI
   # 加载当前房间数据并刷新UI
    # 加载当前房间数据并刷新UI
    def load_current_room(self):
        engine = self.app.engine
        room_id = engine.state.room_id

        room_data = self.load_room_from_file(room_id)
        if not room_data:
            self.query_one("#story_box", TypewriterLog).update(f"[错误] 房间 {room_id} 不存在")
            return

        # 1. 刷新顶部位置
        self.query_one("#lbl_location", LocationWidget).update_location(room_data.get("title", room_id))

        # 2. 【先让按钮闭嘴】：一进房间，不管三七二十一，先把四个按钮全部刷成静默状态
        btn_map = ["opt1", "opt2", "opt3", "opt4"]
        for btn_id in btn_map:
            btn = self.query_one(f"#{btn_id}", Button)
            btn.label = "[·] 聆听常识流动中..."
            btn.disabled = True

        self.refresh_ui()

        # 3. 呼叫打字机，并且把“等会刷按钮”的口令扔给它
        story_text = room_data.get("description", "（无描述）")
        room_style = room_data.get("style", "normal")
        full_text = f"【 {room_data.get('title', room_id)} 】\n\n{story_text}"
        
        # 🌟 重点：把用来刷按钮的闭包函数当成 on_complete 参数传过去！
        def show_options_after_typing():
            self.refresh_options(room_data)

        self.query_one("#story_box", TypewriterLog).type_text(
            full_text, 
            speed=0.015, 
            effect_type=room_style, 
            on_complete=show_options_after_typing
        )

    # 从JSON加载房间数据
    def load_room_from_file(self, room_id: str):
        try:
            with open("data/rooms.json", "r", encoding="utf-8") as f:
                all_rooms = json.load(f)
                room_data = all_rooms.get(room_id)
                if room_data:
                    return {"id": room_id, **room_data}
        except Exception as e:
            self.query_one("#story_box", TypewriterLog).type_text(f"[错误] 读取房间失败: {e}", speed=0)
        return None

    # 刷新选项按钮
    def refresh_options(self, room_data: dict):
        options = room_data.get("options", [])
        engine = self.app.engine

        btn_map = ["opt1", "opt2", "opt3", "opt4"]
        for i, btn_id in enumerate(btn_map):
            btn = self.query_one(f"#{btn_id}", Button)
            if i < len(options):
                option = options[i]
                if engine.check_option_visible(option):
                    btn.label = f"[{i+1}] {option.get('text', '选项')}"
                    btn.disabled = False
                else:
                    btn.label = f"[{i+1}] ???"
                    btn.disabled = True
            else:
                btn.label = f"[{i+1}] ---"
                btn.disabled = True

    # 刷新状态栏
    def refresh_ui(self):
        engine = self.app.engine
        stats = engine.state.stats

        hp = stats.get("hp", 0)
        max_hp = stats.get("max_hp", 100)
        self.query_one("#lbl_hp", Static).update(f"生命: {hp}/{max_hp}")

        san = stats.get("san", 0)
        corruption = stats.get("corruption", 0)
        self.query_one("#lbl_san", Static).update(f"理智: {san} 污染: {corruption}")

    # 键盘动作：选项1-4
    def action_option1(self): self.select_option(0)
    def action_option2(self): self.select_option(1)
    def action_option3(self): self.select_option(2)
    def action_option4(self): self.select_option(3)

    def select_option(self, index: int):
        engine = self.app.engine
        room_data = self.load_room_from_file(engine.state.room_id)
        if not room_data:
            return

        options = room_data.get("options", [])
        if index >= len(options):
            return

        option = options[index]
        if not engine.check_option_visible(option):
            self.notify("当前不可用", title="提示")
            return

        # 执行因果改变
        result = engine.select_option(option)
        self.query_one("#history_box", Log).write_line(f"> {option.get('text', '')}")

        # 🌟 重点防炸：删掉原先这里对 story_box 的 type_text() 乱入！
        # 属性变化我们直接用底部的弹窗 notify 或者写进右侧 history_box，绝对不要去干扰中央打字机！
        effects = result.get("effects_applied", {})
        if effects:
            stats_change = effects.get("stats", {})
            if stats_change:
                change_str = ", ".join([f"{k}: {v:+d}" for k, v in stats_change.items()])
                self.notify(f"因果扭曲：{change_str}", title="状态变更")

        # 🌟 重点清理：删掉原先这里的 self.refresh_ui() 冗余调用，直接单线进新房间
        self.load_current_room()

    def action_profile(self):
        self.app.push_screen(ProfileScreen())

    def action_save(self):
        if self.app.engine.save_game(1):
            self.notify("保存成功")
        else:
            self.notify("保存失败", title="错误")

    def action_settings(self):
        from view.global_settings import GlobalSettingsScreen
        self.app.push_screen(GlobalSettingsScreen())

    def action_menu(self):
        self.app.pop_screen()
        self.app.push_screen(self.app.main_menu_screen)

    def on_button_pressed(self, event: Button.Pressed):
        btn_id = event.button.id

        if btn_id == "btn_profile":
            self.action_profile()
        elif btn_id == "btn_save":
            self.action_save()
        elif btn_id == "btn_menu_settings":
            self.action_settings()
        elif btn_id in ("opt1", "opt2", "opt3", "opt4"):
            index = int(btn_id[-1]) - 1
            self.select_option(index)


# 人物详情界面
class ProfileScreen(Screen):
    BINDINGS = [
        ("escape", "close", "关闭"),
    ]

    CSS = """
    ProfileScreen {
        align: center middle;
        background: rgba(0,0,0,0.7);
    }
    #profile_box {
        width: 58;
        height: auto;
        border: thick #ff007f;
        background: #161923;
        padding: 1 4;
    }
    .prof_title {
        text-align: center;
        text-style: bold;
        color: #ff007f;
        margin-bottom: 2;
    }
    .stat_line {
        color: #b2b2b2;
        text-align: left;
    }
    #close_prof_btn {
        width: 100%;
        background: #23283b;
        color: white;
        border: none;
        margin-top: 2;
    }
    #close_prof_btn:hover {
        background: #ffaa00;
        text-style: bold;
    }
    """

    def compose(self):
        with Vertical(id="profile_box"):
            yield Static("人物详情", classes="prof_title")

            engine = self.app.engine
            stats = engine.state.stats

            yield Static(f"名字: {stats.get('player_name', '无名')}", classes="stat_line")
            yield Static(f"生命: {stats.get('hp', 0)}/{stats.get('max_hp', 100)}", classes="stat_line")
            yield Static(f"理智: {stats.get('san', 0)}", classes="stat_line")
            yield Static(f"污染: {stats.get('corruption', 0)}", classes="stat_line")
            yield Static("--- 属性 ---", classes="prof_title")
            yield Static(f"能量等级: {stats.get('energy_level', 1)}", classes="stat_line")
            yield Static(f"逻辑思维: {stats.get('logic_mind', 0)}", classes="stat_line")
            yield Static(f"科技等级: {stats.get('tech_level', 0)}", classes="stat_line")
            yield Button("[ESC] 关闭", id="close_prof_btn")

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "close_prof_btn":
            self.action_close()

    def action_close(self):
        self.app.pop_screen()
