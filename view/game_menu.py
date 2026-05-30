import json
import os
import re
from textual.screen import Screen
from textual.widgets import Static, Button, Log, ListItem, ListView
from textual.containers import Vertical, Horizontal, Container
from textual import work, on

from view.global_settings import GlobalSettingsScreen

import asyncio
from rich.markup import MarkupError

# ==========================================
# 1. 智能特效打字机
# ==========================================
class TypewriterLog(Static):
    """带防御装甲与预制特效的打字机组件"""
    
    @work(exclusive=True)
    async def type_text(self, full_text: str, speed: float = 0.02, effect_type: str = "normal"):
        # 预制样式外壳包装
        if effect_type == "warning":
            full_text = f"🚨 [bold red]{full_text}[/bold red]"
        elif effect_type == "lust":
            full_text = f"💋 [bold italic #ff007f]{full_text}[/bold italic #ff007f]"
        elif effect_type == "system":
            full_text = f"⚙️ [cyan]{full_text}[/cyan]"

        current_text = ""
        i = 0
        while i < len(full_text):
            if full_text[i] == '[':
                close_idx = full_text.find(']', i)
                if close_idx != -1:
                    current_text += full_text[i : close_idx + 1]
                    i = close_idx + 1
                    continue
            current_text += full_text[i]
            i += 1
            try:
                self.update(current_text)
            except Exception:
                pass
            await asyncio.sleep(speed)
            
        try:
            self.update(full_text)
        except Exception:
            pass

class LocationWidget(Static):
    """鼠标瞄上去会高亮的位置组件"""
    pass

# ==========================================
# 2. 真正联动局内主视窗
# ==========================================
class GamePlayScreen(Screen):
    BINDINGS = [
        ("1", "option1", "选项 1"),
        ("2", "option2", "选项 2"),
        ("3", "option3", "选项 3"),
        ("4", "option4", "选项 4"),
        ("p", "profile", "人物详情"),
        ("s", "save", "保存"),
        ("o", "settings", "设置"),
        ("escape", "menu", "返回菜单"),
    ]

    CSS = """
    GamePlayScreen { padding: 1; background: #0b0c10; }
    #status_bar { height: 3; background: #1f2833; border: solid #45f3ff; margin-bottom: 1; }
    #status_layout { layout: grid; grid-size: 3; grid-columns: 1fr 2fr 1fr; height: 100%; align: center middle; }
    .status_label { text-align: center; color: #66fcf1; content-align: center middle; }
    
    LocationWidget { background: #23283b; color: #ffaa00; text-align: center; content-align: center middle; text-style: bold; }
    LocationWidget:hover { background: #ffaa00; color: #0b0c10; }

    #main_viewport { height: 16; margin-bottom: 1; }
    #story_box { width: 65%; height: 100%; border: solid #45f3ff; background: #1f2833; padding: 1 2; }
    #history_box { width: 35%; height: 100%; border: dashed #555555; background: #0f1016; margin-left: 1; }

    #bottom_console { height: auto; }
    #story_options { width: 65%; layout: grid; grid-size: 2 2; grid-columns: 1fr 1fr; grid-rows: 1fr 1fr; }
    #system_options { width: 35%; margin-left: 1; layout: grid; grid-size: 1 3; }
    
    .opt_btn { background: #11141e; border: tall #45f3ff; color: #66fcf1; margin: 0 1; }
    .opt_btn:hover { background: #66fcf1; color: #0b0c10; text-style: bold; }
    .opt_btn:disabled { background: #1a1a24; color: #444444; border: tall #333333; }
    
    .sys_btn { background: #1f2833; border: none; color: #ffffff; margin: 1 0; min-height: 2; }
    #btn_profile:hover { background: #ff007f; text-style: bold; }
    #btn_save:hover { background: #00ff66; color: #0b0c10; text-style: bold; }
    #btn_menu_settings:hover { background: #ffaa00; color: #0b0c10; text-style: bold; }
    """

    def compose(self):
        with Container(id="status_bar"):
            with Horizontal(id="status_layout"):
                yield Static("🧠 精气神: 加载中...", id="lbl_hp", classes="status_label")
                yield LocationWidget("📍 位置: 获取中...", id="lbl_location")
                yield Static("🔮 理智/污染: 加载中...", id="lbl_san", classes="status_label")

        with Horizontal(id="main_viewport"):
            yield TypewriterLog("故事加载中...", id="story_box")
            yield Log(id="history_box")

        with Horizontal(id="bottom_console"):
            with Container(id="story_options"):
                yield Button("[1] 选项 1", id="opt1", classes="opt_btn")
                yield Button("[2] 选项 2", id="opt2", classes="opt_btn")
                yield Button("[3] 选项 3", id="opt3", classes="opt_btn")
                yield Button("[4] 选项 4", id="opt4", classes="opt_btn")
            with Container(id="system_options"):
                yield Button("[P] 人物详情 / 背包", id="btn_profile", classes="sys_btn")
                yield Button("[S] 刻录当前世界线断点 (Save)", id="btn_save", classes="sys_btn")
                yield Button("[O] 游戏设置", id="btn_menu_settings", classes="sys_btn")

    def on_mount(self):
        """游戏大画面挂载时，接入大后方全局引擎"""
        self.engine = self.app.engine  
        self.query_one("#history_box", Log).write_line("[系统]: 因果链接成功，开始读取世界常识。")
        self.refresh_ui()

    def refresh_ui(self):
        """核心数据流驱动：根据大后方状态，全面刷新整个前台画面"""
        state = self.engine.state
        
        # 1. 刷新顶部状态栏数据
        self.query_one("#lbl_hp", Static).update(f"精气神: [bold green]{state.stats['hp']}/{state.stats['max_hp']}[/bold green]")
        self.query_one("#lbl_san", Static).update(f"理智: {state.stats['san']} | 污染: {state.stats['corruption']}%")
        
        # 2. 读取房间剧本 JSON 数据
        with open("data/rooms.json", "r", encoding="utf-8") as f:
            rooms_data = json.load(f)
        
        room = rooms_data.get(state.room_id, rooms_data["start_classroom"])
        self.query_one("#lbl_location", LocationWidget).update(f"当前位置: {room['title']}")
        
        # 3. 呼叫特效打字机吐字
        effect = room.get("style", "normal")
        debug_tag = f" [ID: {state.room_id}]" if self.engine.settings["debug_mode"] else ""
        story_text = f"[bold magenta]【{room['title']}{debug_tag}】[/bold magenta]\n\n{room['description']}"
        self.query_one("#story_box", TypewriterLog).type_text(story_text, effect_type=effect)
        
        # 写入右侧历史日志中
        history = self.query_one("#history_box", Log)
        history.write_line(f"\n--- 【{room['title']}】 ---")
        history.write_line(room['description'])

        # 4. 动态过滤并绑定左下角的四个剧情按钮
        options = room.get("options", [])
        self.current_visible_options = []  
        
        for idx in range(4):
            btn = self.query_one(f"#opt{idx+1}", Button)
            if idx < len(options):
                opt_data = options[idx]
                
                # 引擎因果拦截：判断玩家属性或Flag够不够格看这个选项
                if self.engine.check_option_visible(opt_data):
                    btn.label = opt_data["text"]
                    btn.disabled = False
                    self.current_visible_options.append(opt_data)
                else:
                    if self.engine.settings["debug_mode"]:
                        btn.label = f"锁定: {opt_data['text']} (条件不足)"
                    else:
                        btn.label = "（因果迷雾遮蔽）"
                    btn.disabled = True
            else:
                btn.label = "（因果留白）"
                btn.disabled = True

    def on_button_pressed(self, event: Button.Pressed):
        btn_id = event.button.id
        
        # 右下角系统按钮分流
        if btn_id == "btn_profile":
            self.app.push_screen(CharacterProfileScreen())
            
        elif btn_id == "btn_save":
            # 真实物理写入本地 slot_1.json
            if self.app.engine.save_game(1):
                self.notify("当前时空断点已成功刻录入磁盘。", title="系统")
            else:
                self.notify("刻录失败，检测到未知因果抗性。", title="错误")
                
        elif btn_id == "btn_delete_save":
            # 🌟 真实物理删除本地 slot_1.json
            if self.app.engine.delete_save(1):
                self.notify("该世界线的磁盘数据已被抹除。", title="系统")
                
        elif btn_id == "btn_menu_settings":
            # 连线到我们独立的全局设置菜单
            self.app.push_screen(GlobalSettingsScreen())
            
        # 左下角剧情选项按钮分流 (opt1 ~ opt4)
        elif btn_id in ["opt1", "opt2", "opt3", "opt4"]:
            btn_idx = int(btn_id[-1]) - 1  # 算出点的是第几个按钮 (0~3)
            if btn_idx < len(self.current_visible_options):
                chosen_opt = self.current_visible_options[btn_idx]
                
                # 把选择喂给引擎进行数值加减和房间跳转
                self.app.engine.select_option(chosen_opt)
                
                # 在历史日志里记一笔
                self.query_one("#history_box", Log).write_line(f" > 降临者选择: {chosen_opt['text']}")
                
                # 刷新整个局内UI，完成时空跃迁
                self.refresh_ui()

    def action_option1(self):
        self.action_option(0)

    def action_option2(self):
        self.action_option(1)

    def action_option3(self):
        self.action_option(2)

    def action_option4(self):
        self.action_option(3)

    def action_option(self, idx):
        if idx < len(self.current_visible_options):
            chosen_opt = self.current_visible_options[idx]
            self.app.engine.select_option(chosen_opt)
            self.query_one("#history_box", Log).write_line(f" > 降临者选择: {chosen_opt['text']}")
            self.refresh_ui()

    def action_profile(self):
        self.app.push_screen(CharacterProfileScreen())

    def action_save(self):
        if self.app.engine.save_game(1):
            self.notify("当前时空断点已成功刻录入磁盘。", title="系统")
        else:
            self.notify("刻录失败，检测到未知因果抗性。", title="错误")

    def action_settings(self):
        self.app.push_screen(GlobalSettingsScreen())

    def action_menu(self):
        self.app.pop_screen()

# ==========================================
# 3. 完美联动的设置与人物详情面板
# ==========================================
class SettingsScreen(Screen):
    # 保持你原有的精美 CSS 样式不变
    CSS = GamePlayScreen.CSS + """
    SettingsScreen { align: center middle; background: rgba(0,0,0,0.75); }
    #settings_box { width: 52; border: solid #ffaa00; background: #161923; padding: 1 4; }
    .title { text-align: center; color: #ffaa00; text-style: bold; margin-bottom: 1; }
    .item { color: #d5d5d5; margin-bottom: 1; }
    #back_btn { width: 100%; background: #23283b; color: white; border: none; margin-top: 2; }
    #back_btn:hover { background: #ffaa00; text-style: bold; }
    """
    def compose(self):
        engine = self.app.engine
        with Vertical(id="settings_box"):
            yield Static("游戏设置（引擎同步版）", classes="title")
            yield Static(f"· 真理视界(Debug): {'开启' if engine.settings['debug_mode'] else '关闭'}", classes="item")
            yield Static(f"· 异质常识常数: {engine.settings['corruption_rate']}x", classes="item")
            yield Button("返回游戏并同步真理", id="back_btn")
    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "back_btn":
            self.app.pop_screen()
            # 当返回游戏时，让大视窗重新刷新一下（为了响应可能的Debug状态改变）
            if hasattr(self.app, "game_play_screen"):
                self.app.game_play_screen.refresh_ui()

class CharacterProfileScreen(Screen):
    CSS = """
    CharacterProfileScreen { align: center middle; background: rgba(0,0,0,0.7); }
    #profile_box { width: 58; height: auto; border: thick #ff007f; background: #161923; padding: 1 4; }
    .prof_title { text-align: center; text-style: bold; color: #ff007f; margin-bottom: 2; }
    .section { margin-bottom: 1; }
    .stat_group_title { color: #ffaa00; text-style: bold; margin-bottom: 1; }
    .stat_line { color: #b2b2b2; text-align: left; }
    .divider { color: #888888; }
    #close_prof_btn { width: 100%; background: #23283b; color: white; border: none; margin-top: 2; }
    #close_prof_btn:hover { background: #ffaa00; text-style: bold; }
    """
    def compose(self):
        # ✨ 从大后方引出最真实的活数据！
        stats = self.app.engine.state.stats
        flags = self.app.engine.state.flags
        
        with Vertical(id="profile_box"):
            yield Static("★ 局外人实时因果面板 ★", classes="prof_title")

            with Vertical(classes="section"):
                yield Static("— [ 底层数值解构 ] —", classes="stat_group_title")
                yield Static(f" · 生命能级/阶位: [{stats['energy_level']}]", classes="stat_line")
                yield Static(f" · 现代逻辑思维: [{stats['logic_mind']}]", classes="stat_line")
                yield Static(f" · 科技解构能力: [{stats['tech_level']}]", classes="stat_line")
                yield Static(f" · 传统魔法能级: [{stats['magic_power']}]", classes="stat_line")
                yield Static(f" · 精气神状态: {stats['hp']} / {stats['max_hp']}", classes="stat_line")
                yield Static(f" · 灵魂常识污染: {stats['corruption']}%", classes="stat_line")
                yield Static("—" * 48, classes="divider")

            with Vertical(classes="section"):
                yield Static("— [ 随身因果标记追踪 ] —", classes="stat_group_title")
                yield Static(f" · 拔掉老师电线: {'[✓] 已触发' if flags['classroom_power_cut'] else '[ ] 未干涉'}", classes="stat_line")
                yield Static(f" · 偶遇爱丽丝: {'[✓] 已触发' if flags['met_alice'] else '[ ] 未干涉'}", classes="stat_line")

            yield Button("收回视线", id="close_prof_btn")

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "close_prof_btn":
            self.app.pop_screen()