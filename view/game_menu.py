import json
import os
from textual.screen import Screen
from textual.widgets import Static, Button, Log
from textual.containers import Vertical, Horizontal, Container

# 自定义一个带高亮边框和点击事件的位置标签
class LocationWidget(Static):
    """鼠标瞄上去会高亮的位置组件"""
    pass

class GamePlayScreen(Screen):
    # ==========================================
    # 🎨 现代工业风 UI 样式表
    # ==========================================
    CSS = """
    GamePlayScreen { padding: 1; background: #0b0c10; }
    
    /* 顶部状态栏 */
    #status_bar { height: 3; background: #1f2833; border: solid #45f3ff; margin-bottom: 1; }
    #status_layout { layout: grid; grid-size: 3; grid-columns: 1fr 2fr 1fr; height: 100%; align: center middle; }
    .status_label { text-align: center; color: #66fcf1; content-align: center middle; }
    
    LocationWidget { background: #23283b; color: #ffaa00; text-align: center; content-align: center middle; text-style: bold; }
    LocationWidget:hover { background: #ffaa00; color: #0b0c10; }

    /* 中间核心视窗：左剧情，右历史 */
    #main_viewport { height: 16; margin-bottom: 1; }
    #story_box { width: 65%; height: 100%; border: solid #45f3ff; background: #1f2833; padding: 1 2; }
    #history_box { width: 35%; height: 100%; border: dashed #555555; background: #0f1016; margin-left: 1; }

    /* 底部总控制台 */
    #bottom_console { height: auto; }
    #story_options { width: 65%; layout: grid; grid-size: 2 2; grid-columns: 1fr 1fr; grid-rows: 1fr 1fr; }
    #system_options { width: 35%; margin-left: 1; layout: grid; grid-size: 1 3; }
    
    /* 按钮基础样式 */
    .opt_btn { background: #11141e; border: tall #45f3ff; color: #66fcf1; margin: 0 1; }
    .opt_btn:hover { background: #66fcf1; color: #0b0c10; text-style: bold; }
    
    .sys_btn { background: #1f2833; border: none; color: #ffffff; margin: 1 0; min-height: 2; }
    #btn_profile:hover { background: #ff007f; text-style: bold; }
    #btn_save:hover { background: #00ff66; color: #0b0c10; text-style: bold; }
    #btn_menu_settings:hover { background: #ffaa00; color: #0b0c10; text-style: bold; }
    """

    def compose(self):
        # 1. 顶部状态栏
        with Container(id="status_bar"):
            with Horizontal(id="status_layout"):
                yield Static("🧠 精气神: 100/100", classes="status_label")
                yield LocationWidget("📍 位置: 催眠的大学教室 (点击探查地图)")
                yield Static("🏷️ 状态: [请查看详情]", classes="status_label")

        # 2. 中间大视窗
        with Horizontal(id="main_viewport"):
            yield Static("故事加载中...", id="story_box")
            yield Log(id="history_box") # Textual自带的滚动日志控件，天然适合做历史对话

        # 3. 底部操作栏
        with Horizontal(id="bottom_console"):
            # 左边四个剧情按键
            with Container(id="story_options"):
                yield Button("选项 1", id="opt1", classes="opt_btn")
                yield Button("选项 2", id="opt2", classes="opt_btn")
                yield Button("选项 3", id="opt3", classes="opt_btn")
                yield Button("选项 4", id="opt4", classes="opt_btn")
            # 右边系统按键
            with Container(id="system_options"):
                yield Button(" 人物详情 / 背包", id="btn_profile", classes="sys_btn")
                yield Button(" 保存游戏", id="btn_save", classes="sys_btn")
                yield Button(" 游戏设置", id="btn_menu_settings", classes="sys_btn")

    def on_mount(self):
        """开机加载第一个房间"""
        # 初始化历史对话框的提示
        history = self.query_one("#history_box", Log)
        history.write_line("[系统]: 历史对话记录从这里开始。")
        
        # 读取静态数据
        with open("data/rooms.json", "r", encoding="utf-8") as f:
            rooms = json.load(f)
        room = rooms["start_classroom"]
        
        # 渲染剧情
        self.query_one("#story_box", Static).update(f"[bold magenta]【{room['title']}】[/bold magenta]\n\n{room['description']}")
        history.write_line(f"【{room['title']}】")
        history.write_line(room['description'])
        
        # 绑定按钮（如果JSON里只有2个选项，剩下2个可以设为不可用）
        self.query_one("#opt1", Button).label = room["options"][0]["text"]
        self.query_one("#opt2", Button).label = room["options"][1]["text"]
        self.query_one("#opt3", Button).disabled = True
        self.query_one("#opt4", Button).disabled = True

    # ==========================================
    # 🕹️ 鼠标点击事件分发中心
    # ==========================================
    def on_button_pressed(self, event: Button.Pressed):
        btn_id = event.button.id
        
        if btn_id == "btn_profile":
            self.app.push_screen(CharacterProfileScreen())
        elif btn_id == "btn_save":
            self.notify("正在写入 world_memory.json ... 存档成功！", title="系统保存")
        elif btn_id == "btn_menu_settings":
            self.app.push_screen(SettingsScreen())

# ==========================================
# 游戏设置界面
# ==========================================
class SettingsScreen(Screen):
    CSS = """
    SettingsScreen {
        align: center middle;
        background: rgba(0,0,0,0.75);
    }
    #settings_box {
        width: 52;
        border: solid #ffaa00;
        background: #161923;
        padding: 1 4;
    }
    .title {
        text-align: center;
        color: #ffaa00;
        text-style: bold;
        margin-bottom: 1;
    }
    .item {
        color: #d5d5d5;
        margin-bottom: 1;
    }
    #back_btn {
        width: 100%;
        background: #23283b;
        color: white;
        border: none;
        margin-top: 2;
    }
    #back_btn:hover {
        background: #ffaa00;
        text-style: bold;
    }
    """

    def compose(self):
        with Vertical(id="settings_box"):
            yield Static("游戏设置", classes="title")
            yield Static("· 开启音效: 未实现", classes="item")
            yield Static("· 画面风格: 终端复古", classes="item")
            yield Static("· 隐藏剧情提示: 关闭", classes="item")
            yield Button("返回游戏", id="back_btn")

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "back_btn":
            self.app.pop_screen()

    def on_click(self, event):
        """捕获位置标签的点击（Meta整活）"""
        # 判断鼠标是不是点在了 LocationWidget 上
        if isinstance(event.screen_handler, LocationWidget) or "LocationWidget" in str(event):
            # 触发你的 Meta 地图创意！
            self.notify("检测到局外人窥探！一张名为 'map_leak.png' 的超古代魔法地图已悄悄扔进了你的游戏根目录，请参照其摸索！", title="👁️ META 规则干扰", timeout=6.0)
            # 在后台真的生成一个txt或假装放个文件
            with open("请在文件夹里查看地图.txt", "w", encoding="utf-8") as f:
                f.write("【超古代魔法地图提示】\n教室后门有一根电线直通村口网吧。但在那之前，你必须拔掉高数老师的投影仪。")
class CharacterProfileScreen(Screen):
    CSS = """
    CharacterProfileScreen {
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
    .section {
        margin-bottom: 1;
    }
    .stat_group_title {
        color: #ffaa00;
        text-style: bold;
        margin-bottom: 1;
    }
    .stat_line {
        color: #b2b2b2;
        text-align: left;
    }
    .inventory_line {
        color: #e5e5e5;
        text-align: left;
        margin-left: 2;
    }
    .tag_line {
        color: #00ff66;
        text-style: italic;
        text-align: left;
        margin-left: 2;
    }
    .divider {
        color: #888888;
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
            yield Static("★ 局外人因果面板 ★", classes="prof_title")

            with Vertical(classes="section"):
                yield Static("— [ 底层数值解构 ] —", classes="stat_group_title")
                yield Static(" · 现代逻辑思维: [99]", classes="stat_line")
                yield Static(" · 传统西幻抗性: [1.0]", classes="stat_line")
                yield Static(" · 精气神: 100 / 100", classes="stat_line")
                yield Static("—" * 48, classes="divider")

            with Vertical(classes="section"):
                yield Static("— [ 随身口袋 ] —", classes="stat_group_title")
                yield Static(" · 【低压电工证】x1 (已绑定)", classes="inventory_line")
                yield Static(" · 绝缘胶布, 测电笔 x1", classes="inventory_line")
                yield Static("—" * 48, classes="divider")

            with Vertical(classes="section"):
                yield Static("— [ 当前缠绕的因果法则 ] —", classes="stat_group_title")
                yield Static("·【精神洁癖者】: 厌恶单线剧情。", classes="tag_line")
                yield Static("·【未开工电工】: 盯着投影仪插头。", classes="tag_line")

            yield Button("收回视线", id="close_prof_btn")
    def on_button_pressed(self, event: Button.Pressed):
        """修复报错：改成 self.app.pop_screen()"""
        if event.button.id == "close_prof_btn":
            self.app.pop_screen()