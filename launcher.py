from textual.app import App
from view.main_menu import MainMenuScreen
from view.game_menu import GamePlayScreen
from engine import GameEngine

class IsekaiEngine(App):
    """定义"""
    
    def on_mount(self):
        # 1. 唯一实例化物理引擎，挂载到全局 app 上 (供所有子 Screen 共享)
        self.engine = GameEngine()
        
        # 2. 动态保存主菜单的引用，方便其他界面调起它的刷新逻辑
        self.main_menu_screen = MainMenuScreen()
        
        # 3. 游戏一开机，立刻把主菜单屏幕“推”到最前端显示
        self.push_screen(self.main_menu_screen)

    def action_start_gameplay(self):
        """当主菜单或者存档选择器触发了‘进入世界’，总发动机立刻推入正式游戏场景"""
        self.push_screen(GamePlayScreen())

if __name__ == "__main__":
    app = IsekaiEngine()
    app.run()