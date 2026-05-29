from textual.app import App
from view.main_menu import MainMenuScreen
from view.game_menu import GamePlayScreen
from view.intro_screen import IntroScreen
from engine import GameEngine

class IsekaiEngine(App):
    def __init__(self):
        super().__init__()
        self.main_menu_screen = MainMenuScreen() 
        self.game_play_screen = GamePlayScreen()
        
    def on_mount(self):
        self.engine = GameEngine()
        self.main_menu_screen = MainMenuScreen()
        self.push_screen(IntroScreen())

    def action_start_gameplay(self):
        self.push_screen(GamePlayScreen())

if __name__ == "__main__":
    app = IsekaiEngine()
    app.run()