from textual.app import App
from view.main_menu import MainMenuScreen
from view.game_menu import GamePlayScreen

class IsekaiEngine(App):
    """总发动机：控制整个游戏的生命周期与视窗切换"""
    
    def on_mount(self):
        # 游戏一开机，立刻把主菜单屏幕“推”到最前端显示
        self.push_screen(MainMenuScreen())

    def action_start_game(self):
        """当主菜单点击了开始，总发动机立刻把主菜单卸载，推入游戏剧情视窗"""
        self.pop_screen()  # 移除主菜单
        self.push_screen(GamePlayScreen())  # 推入正式游戏场景

if __name__ == "__main__":
    app = IsekaiEngine()
    app.run()