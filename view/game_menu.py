import json
import os
from textual.screen import Screen
from textual.widgets import Static, Button, RichLog
from textual.containers import Horizontal, Vertical, Container
from textual.events import Key
from textual import on
from rich.text import Text

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
        ("i", "inventory", "物品"),
        ("d", "diary", "日记"),
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
        height: 100%;
        align: center middle;
    }
    LocationWidget {
        color: #ffaa00;
        text-align: center;
        content-align: center middle;
        text-style: bold;
        width: 100%;
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
    }
    #primary_buttons {
        width: 1fr;
        height: 100%;
        margin-right: 1;
    }
    #secondary_buttons {
        width: 1fr;
        height: 100%;
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
        width: 100%;
        height: 2;
        margin-bottom: 1;
    }
    #btn_profile:hover {
        background: #ff007f;
        text-style: bold;
    }
    #btn_inventory:hover {
        background: #66fcf1;
        color: #0b0c10;
        text-style: bold;
    }
    #btn_diary:hover {
        background: #e6b800;
        color: #0b0c10;
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
                yield LocationWidget("位置: 加载中...", id="lbl_location")

        with Horizontal(id="main_viewport"):
            yield TypewriterLog("", id="story_box")
            yield RichLog(id="history_box", markup=True)

        with Horizontal(id="bottom_console"):
            with Container(id="story_options"):
                yield Button("[1] 选项 1", id="opt1", classes="opt_btn")
                yield Button("[2] 选项 2", id="opt2", classes="opt_btn")
                yield Button("[3] 选项 3", id="opt3", classes="opt_btn")
                yield Button("[4] 选项 4", id="opt4", classes="opt_btn")
            with Horizontal(id="system_options"):
                with Vertical(id="primary_buttons"):
                    yield Button("[P] 人物", id="btn_profile", classes="sys_btn")
                    yield Button("[I] 物品", id="btn_inventory", classes="sys_btn")
                    yield Button("[S] 保存", id="btn_save", classes="sys_btn")
                with Vertical(id="secondary_buttons"):
                    self._btn_diary = Button("[D] 日记", id="btn_diary", classes="sys_btn")
                    yield self._btn_diary
                    yield Button("[O] 设置", id="btn_menu_settings", classes="sys_btn")
                    yield Button("[ ] ---", id="btn_empty", classes="sys_btn", disabled=True)

    def on_mount(self):
        self.call_after_refresh(self.load_current_room)
        self._refresh_diary_button()

    def _refresh_diary_button(self):
        state = self.app.engine.state
        inventory = state.inventory
        # 同时检查物品ID和进度标记，确保逻辑严密
        has_diary_item = any(item.get("id") in ["diary", "old_diary"] for item in inventory)
        has_diary_flag = state.flags.get("has_diary", False)
        
        has_diary = has_diary_item or has_diary_flag
        
        # 为了保持 3x2 布局稳定，我们使用 disabled 而不是 display=False
        self._btn_diary.disabled = not has_diary
        if not has_diary:
            self._btn_diary.label = "[D] (未获得日记)"
        else:
            self._btn_diary.label = "[D] 日记"
            # 激活状态下可以添加一些视觉提示
            self._btn_diary.styles.color = "#e6b800"
            self._btn_diary.styles.text_style = "bold"

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

        # 3. 呼叫打字机，并且把"等会刷按钮"的口令扔给它
        story_text = engine.resolve_room_description(room_data)
        room_style = room_data.get("style", "normal")
        full_text = f"【 {room_data.get('title', room_id)} 】\n\n{story_text}"
        
        # 将故事文本记录到历史记录
        history_log = self.query_one("#history_box", RichLog)
        history_log.write(f"[bold white]【 {room_data.get('title', room_id)} 】[/bold white]")
        history_log.write(story_text)

        # 🌟 重点：把用来刷按钮的闭包函数当成 on_complete 参数传过去！
        def show_options_after_typing():
            self.refresh_options(room_data)

        self.query_one("#story_box", TypewriterLog).type_text(
            full_text, 
            speed=engine.settings.get("text_speed", "medium"), 
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
                    hidden = option.get("hidden_text", "???")
                    btn.label = f"[{i+1}] {hidden}"
                    btn.disabled = True
            else:
                btn.label = f"[{i+1}] ---"
                btn.disabled = True

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
        
        # 记录玩家的选择到历史记录
        history_log = self.query_one("#history_box", RichLog)
        history_log.write(f"\n[cyan]> {option.get('text', '')}[/cyan]")

        # 属性变化我们直接用底部的弹窗 notify 或者写进右侧 history_box
        effects = result.get("effects_applied", {})
        if effects:
            stats_change = effects.get("stats", {})
            if stats_change:
                change_str = ", ".join([f"{k}: {v:+d}" for k, v in stats_change.items()])
                self.notify(f"因果扭曲：{change_str}", title="状态变更")
                history_log.write(f"[yellow]状态变更: {change_str}[/yellow]")

        self.load_current_room()
        self._refresh_diary_button()

    def action_profile(self):
        from view.profile_screen import ProfileScreen
        self.app.push_screen(ProfileScreen())

    def action_inventory(self):
        from view.inventory_screen import InventoryScreen
        self.app.push_screen(InventoryScreen())

    def action_diary(self):
        from view.diary_screen import DiaryScreen
        self.app.push_screen(DiaryScreen())

    def action_save(self):
        from view.save_game_screen import SaveGameScreen
        self.app.push_screen(SaveGameScreen())

    def action_settings(self):
        from view.global_settings import GlobalSettingsScreen
        self.app.push_screen(GlobalSettingsScreen())

    def action_menu(self):
        if len(self.app.screen_stack) <= 1:
            return
        self.app.pop_screen()
        self.app.push_screen(self.app.main_menu_screen)

    def on_button_pressed(self, event: Button.Pressed):
        btn_id = event.button.id

        if btn_id == "btn_profile":
            self.action_profile()
        elif btn_id == "btn_inventory":
            self.action_inventory()
        elif btn_id == "btn_diary":
            self.action_diary()
        elif btn_id == "btn_save":
            self.action_save()
        elif btn_id == "btn_menu_settings":
            self.action_settings()
        elif btn_id in ("opt1", "opt2", "opt3", "opt4"):
            index = int(btn_id[-1]) - 1
            self.select_option(index)
