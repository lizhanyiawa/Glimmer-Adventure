import os

_PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def data_path(filename: str) -> str:
    return os.path.join(_PROJECT_ROOT, "data", filename)


def save_path(filename: str) -> str:
    return os.path.join(_PROJECT_ROOT, "saves", filename)


def config_path(filename: str = "engine_config.json") -> str:
    return os.path.join(_PROJECT_ROOT, filename)