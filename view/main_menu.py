import os
from textual.app import App
from textual.screen import Screen
from textual.widgets import Static, Button, ListItem, ListView
from textual.containers import Vertical, Horizontal, Container
from textual import on

# 导入底层写好的引擎控制核心
from engine import GameEngine, GameState

class MenuButton(Button):
    """主菜单通用的样式按钮组件"""
    pass

# ==========================================
# 1. 核心：主菜单视窗 (MainMenuScreen)
# ==========================================
class MainMenuScreen(Screen):
    CSS = """
    MainMenuScreen { 
        align: center middle; 
        background: #0b0c10; 
    }
    #menu_box { 
        width: 65; 
        height: auto; 
        border: double #45f3ff; 
        background: #1f2833; 
        padding: 1 3; 
    }
    .title { 
        text-align: center; 
        text-style: bold; 
        color: #66fcf1; 
        margin-bottom: 0;
    }
    .subtitle { 
        text-align: center; 
        text-style: italic; 
        color: #ffaa00; 
        margin-bottom: 2; 
    }
    MenuButton { 
        width: 100%; 
        margin: 1 0; 
        background: #11141e; 
        color: #66fcf1; 
        border: none; 
    }
    MenuButton:hover { 
        background: #45f3ff; 
        color: #0b0c10; 
        text-style: bold; 
    }
    MenuButton:disabled {
        background: #1a222d;
        color: #555555;
    }
    """

    def compose(self):
        with Vertical(id="menu_box"):
            yield Static("★ THE CHOSEN OUTSIDER ★", classes="title")
            yield Static("—— 异界因果律解构引擎 ——", classes="subtitle")
            yield MenuButton("[1] 构筑新的因果世界线 (Start Game)", id="btn_new_game")
            yield MenuButton("[2] 激活旧的世界线断点 (Load Game)", id="btn_load_game")
            yield MenuButton("[3] 调整真理规则参数 (Settings)", id="btn_settings")
            yield MenuButton("[4] 强行断开魔力连接 (Exit)", id="btn_exit")

    def on_mount(self):
        """每次主菜单显示时，动态扫描是否存在存档文件"""
        self.update_load_button_state()

    def update_load_button_state(self):
        """如果没有任何物理存档，则将'读取游戏'置灰"""
        engine = self.app.engine
        slots = engine.get_save_slots()
        has_any_save = any(slot["exists"] for slot in slots)
        
        load_btn = self.query_one("#btn_load_game", MenuButton)
        if not has_any_save:
            load_btn.disabled = True
            load_btn.label = "[2] 激活旧的世界线断点 (无存档)"
        else:
            load_btn.disabled = False
            load_btn.label = "[2] 激活旧的世界线断点 (Load Game)"

    def on_button_pressed(self, event: Button.Pressed):
        button_id = event.button.id
        if button_id == "btn_new_game":
            # 初始化一个新的 GameState，并进入游戏画面
            self.app.engine.state = GameState()
            self.notify("因果逻辑链已重置，正在进入世界...", title="⏳ 系统初始化")
            # 预留给未来 GamePlayScreen 接入的接口
            self.app.action_start_gameplay()
            
        elif button_id == "btn_load_game":
            self.app.push_screen(SaveSelectorScreen())
            
        elif button_id == "btn_settings":
            self.app.push_screen(SettingsScreen())
            
        elif button_id == "btn_exit":
            self.app.push_screen(QuitConfirmScreen())


# ==========================================
# 2. 真实的物理存档选择器 (SaveSelectorScreen)
# ==========================================
class SaveSelectorScreen(Screen):
    CSS = """
    SaveSelectorScreen { 
        align: center middle; 
        background: rgba(0, 0, 0, 0.7); 
    }
    #selector_box { 
        width: 60; 
        height: 20; 
        border: solid #ffaa00; 
        background: #161923; 
        padding: 1 2; 
    }
    .sel_title { 
        text-align: center; 
        text-style: bold; 
        color: #ffaa00; 
        margin-bottom: 1; 
    }
    #save_list {
        background: #11141e;
        border: solid #333333;
        margin-bottom: 1;
        height: 12;
    }
    .save_item_label {
        color: #d5d5d5;
        padding: 0 1;
    }
    #btn_cancel { 
        width: 100%; 
        background: #23283b; 
        color: white; 
        border: none; 
    }
    #btn_cancel:hover { 
        background: #ffaa00; 
        color: #0b0c10;
        text-style: bold; 
    }
    """

    def compose(self):
        with Vertical(id="selector_box"):
            yield Static("💾 物理因果世界线槽位", classes="sel_title")
            yield ListView(id="save_list")
            yield Button("关闭视窗", id="btn_cancel")

    def on_mount(self):
        """动态渲染真实存在的存档"""
        self.refresh_save_list()

    def refresh_save_list(self):
        list_view = self.query_one("#save_list", ListView)
        list_view.clear()
        
        slots = self.app.engine.get_save_slots()
        for s in slots:
            slot_id = s["slot"]
            if s["exists"]:
                desc = f" 槽位 [{slot_id}] · {s['room_id']} · 阶位:{s['level']} ({s['last_saved']})"
                item = ListItem(Static(desc, classes="save_item_label"), id=f"slot_{slot_id}")
            else:
                item = ListItem(Static(f" 槽位 [{slot_id}] · ( 空白世界线数据 )", classes="save_item_label"), id=f"slot_{slot_id}")
                # 空档置灰，防止选择
                item.disabled = True
            list_view.append(item)

    @on(ListView.Selected)
    def on_save_selected(self, event: ListView.Selected):
        slot_id_str = event.item.id  # 例如 "slot_1"
        slot_idx = int(slot_id_str.split("_")[1])
        
        # 引擎物理读取
        success = self.app.engine.load_game(slot_idx)
        if success:
            self.notify(f"世界线断点 [{slot_idx}] 读取成功！", title="💾 加载完成")
            self.app.pop_screen()
            # 恢复后直接引导玩家进入游戏界面
            self.app.action_start_gameplay()
        else:
            self.notify(f"糟了！断点数据读取失败。", severity="error", title="错误")

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "btn_cancel":
            self.app.pop_screen()


# ==========================================
# 3. 真实的底层配置界面 (SettingsScreen)
# ==========================================
class SettingsScreen(Screen):
    CSS = """
    SettingsScreen { 
        align: center middle; 
        background: rgba(0,0,0,0.8); 
    }
    #settings_box { 
        width: 58; 
        height: auto; 
        border: solid #00ff66; 
        background: #11141e; 
        padding: 1 3; 
    }
    .settings_title { 
        text-align: center; 
        text-style: bold; 
        color: #00ff66; 
        margin-bottom: 2; 
    }
    /* 开关属性行 */
    .setting_row {
        height: 3;
        margin-bottom: 1;
        content-align: left middle;
    }
    .setting_desc {
        width: 32;
        color: #b2b2b2;
        content-align: left middle;
    }
    .toggle_btn {
        width: 18;
        border: none;
    }
    #btn_close_settings { 
        width: 100%; 
        background: #23283b; 
        color: white; 
        border: none; 
        margin-top: 1; 
    }
    #btn_close_settings:hover { 
        background: #00ff66; 
        color: #0b0c10;
        text-style: bold; 
    }
    """

    def compose(self):
        engine = self.app.engine
        with Vertical(id="settings_box"):
            yield Static("⚙️ 真理规则参数调谐", classes="settings_title")
            
            # 1. Debug 模式 (真理视界)
            with Horizontal(classes="setting_row"):
                yield Static("· 真理视界 (显示逻辑参数)", classes="setting_desc")
                yield Button(
                    "已开启" if engine.settings["debug_mode"] else "已关闭", 
                    id="toggle_debug", 
                    classes="toggle_btn"
                )
                
            # 2. 黄油侵蚀倍率 (黄油浓度)
            with Horizontal(classes="setting_row"):
                yield Static("· 异质常识侵蚀倍率", classes="setting_desc")
                yield Button(
                    f"{engine.settings['corruption_rate']}x", 
                    id="toggle_corruption", 
                    classes="toggle_btn"
                )
                
            # 3. 局外人音能解构
            with Horizontal(classes="setting_row"):
                yield Static("· 局外人音能解构 (音频开关)", classes="setting_desc")
                yield Button(
                    "ON" if engine.settings["sound_enabled"] else "OFF", 
                    id="toggle_sound", 
                    classes="toggle_btn"
                )
                
            yield Button("写入设定并封闭视窗", id="btn_close_settings")

    def on_button_pressed(self, event: Button.Pressed):
        btn_id = event.button.id
        engine = self.app.engine
        
        if btn_id == "toggle_debug":
            engine.settings["debug_mode"] = not engine.settings["debug_mode"]
            event.button.label = "已开启" if engine.settings["debug_mode"] else "已关闭"
            self.notify(f"真理视界变更为: {engine.settings['debug_mode']}")
            
        elif btn_id == "toggle_corruption":
            # 在 1.0 -> 1.5 -> 2.0 -> 0.0 -> 0.5 循环循环
            rates = [0.0, 0.5, 1.0, 1.5, 2.0]
            curr_rate = engine.settings["corruption_rate"]
            next_idx = (rates.index(curr_rate) + 1) % len(rates) if curr_rate in rates else 2
            engine.settings["corruption_rate"] = rates[next_idx]
            event.button.label = f"{engine.settings['corruption_rate']}x"
            self.notify(f"黄油侵蚀权重调整为: {engine.settings['corruption_rate']}x")
            
        elif btn_id == "toggle_sound":
            engine.settings["sound_enabled"] = not engine.settings["sound_enabled"]
            event.button.label = "ON" if engine.settings["sound_enabled"] else "OFF"
            self.notify(f"音轨捕获状态已修改。")
            
        elif btn_id == "btn_close_settings":
            # 保存到本地物理硬盘 config
            engine.save_settings()
            self.app.pop_screen()
            # 通知主菜单刷新状态
            if hasattr(self.app.main_menu_screen, "update_load_button_state"):
                self.app.main_menu_screen.update_load_button_state()


# ==========================================
# 4. 完美退出弹窗 (QuitConfirmScreen)
# ==========================================
class QuitConfirmScreen(Screen):
    CSS = """
    QuitConfirmScreen { 
        align: center middle; 
        background: rgba(0,0,0,0.65); 
    }
    #confirm_box { 
        width: 50; 
        height: auto; 
        border: heavy red; 
        background: #1a1010; 
        padding: 1 4; 
    }
    .confirm_title { 
        text-align: center; 
        text-style: bold; 
        color: red; 
        margin-bottom: 1; 
    }
    .confirm_text { 
        text-align: center; 
        margin-bottom: 2; 
        color: #e5e5e5; 
    }
    #btn_box { 
        content-align: center middle; 
        height: auto; 
        width: 100%; 
    }
    .choice_btn { 
        width: 18; 
        margin: 0 1; 
    }
    #btn_yes { 
        background: #880000; 
        color: white; 
        border: none; 
    }
    #btn_yes:hover { 
        background: red; 
        text-style: bold; 
    }
    #btn_no { 
        background: #222222; 
        color: white; 
        border: none; 
    }
    #btn_no:hover { 
        background: #555555; 
        text-style: bold; 
    }
    """

    def compose(self):
        with Vertical(id="confirm_box"):
            yield Static("⚠️ 警告", classes="confirm_title")
            yield Static("你确定要切断魔力电线并逃离吗？\n当前未保存的因果标记将会蒸发！", classes="confirm_text")
            with Horizontal(id="btn_box"):
                yield Button("强行跑路", id="btn_yes", classes="choice_btn")
                yield Button("容我想想", id="btn_no", classes="choice_btn")

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "btn_yes":
            self.app.exit()
        elif event.button.id == "btn_no":
            self.app.pop_screen()


# ==========================================
# 🚀 5. App 协调调度器主类 (Bootstrapper)
# ==========================================
class MUDApp(App):
    """协调前端多屏幕切换与全局引擎生命周期"""
    def on_mount(self):
        # 1. 唯一实例化物理引擎，保证所有屏幕读取的是同一个全局实例 (Singleton Engine Pattern)
        self.engine = GameEngine()
        
        # 2. 挂接主菜单，作为第一顺位渲染视图
        self.main_menu_screen = MainMenuScreen()
        self.push_screen(self.main_menu_screen)

    def action_start_gameplay(self):
        """在这里挂接你未来的 GamePlayScreen (游戏局内大视窗)"""
        # 我们目前可以用一个轻量的通知占位，直到你将 game_menu 里面的 GamePlayScreen 也重写并导入进来。
        # 预留跳转接口：
        # from game_menu import GamePlayScreen
        # self.push_screen(GamePlayScreen())
        self.notify(f"成功将当前世界线载入：房间=[{self.engine.state.room_id}]", title="⚡ 引擎启动中")

if __name__ == "__main__":
    app = MUDApp()
    app.run()