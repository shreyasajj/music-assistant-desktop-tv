"""PyInstaller entry point.

PyInstaller turns whatever script it's given into the bundle's top-level
``__main__`` module, which has no parent package — so pointing it straight at
``src/bigscreen_jukebox/__main__.py`` makes that file's relative imports
(``from .config import ...``) fail at startup with "attempted relative import
with no known parent package".

This launcher imports the package by its absolute name instead, so
``__main__.py`` is loaded as ``bigscreen_jukebox.__main__`` (a submodule with a
real parent package) and its relative imports resolve normally.
"""
from __future__ import annotations
import sys

from bigscreen_jukebox.__main__ import main

if __name__ == "__main__":
    sys.exit(main())
