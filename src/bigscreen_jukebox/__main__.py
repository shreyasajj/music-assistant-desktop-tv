from __future__ import annotations
import sys
from pathlib import Path
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from .config import load_settings, default_config_path
from .ma_client import MaClient

QML_DIR = Path(__file__).resolve().parent.parent.parent / "qml"

def main() -> int:
    app = QGuiApplication(sys.argv)
    engine = QQmlApplicationEngine()
    engine.addImportPath(str(QML_DIR))

    settings = load_settings(default_config_path())
    ma = MaClient(settings)
    engine.rootContext().setContextProperty("maClient", ma)

    engine.load(QML_DIR / "main.qml")
    if not engine.rootObjects():
        return 1
    return app.exec()

if __name__ == "__main__":
    raise SystemExit(main())
