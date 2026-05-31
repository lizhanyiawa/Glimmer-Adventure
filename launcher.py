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
        if not self.screen_stack:
            self.push_screen(GamePlayScreen())

    def action_start_gameplay(self):
        self.push_screen(GamePlayScreen())

if __name__ == "__main__":
    app = IsekaiEngine()
    app.run()