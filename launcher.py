from textual.app import App
from view.main_menu import MainMenuScreen
from view.game_menu import GamePlayScreen
from view.intro_screen import IntroScreen
from engine import GameEngine

class IsekaiEngine(App):
    def on_mount(self):
        self.engine = GameEngine()
        self.main_menu_screen = MainMenuScreen()
        if self.engine.settings.get("skip_intro", False):
            self.push_screen(self.main_menu_screen)
        else:
            self.push_screen(IntroScreen())

    def pop_screen(self):
        super().pop_screen()

    def action_start_gameplay(self):
        self.gameplay_screen = GamePlayScreen()
        self.push_screen(self.gameplay_screen)

if __name__ == "__main__":
    app = IsekaiEngine()
    app.run()