# Bigscreen Jukebox

A fullscreen, TV- and remote-friendly client for a [Music Assistant](https://www.music-assistant.io/)
server — Now Playing, search, karaoke lyrics, an audio visualizer, and a guest QR
mode, all controllable with a D-pad remote. Built with PySide6/QML.

> Unofficial, third-party client. Not affiliated with the Music Assistant project.

## Download

Grab the latest build from the [Releases page](https://github.com/shreyasajj/music-assistant-desktop-tv/releases):

- **AppImage** — `chmod +x Bigscreen_Jukebox-x86_64.AppImage` and run it (works on KDE Plasma and most Linux desktops).
- **Tarball** — extract and run `bigscreen-jukebox/bigscreen-jukebox`.

Builds are produced automatically on every push (full releases from `main`,
pre-releases from `dev`). For the live visualizer / album-art bass pump, install
`libportaudio2` (optional).

First run: open **Settings**, enter your Music Assistant host + long-lived token,
and pick a default player.

## Flatpak / Flathub

Packaging files and submission instructions are in [`flatpak/`](flatpak/README.md).

## Dev setup

    pip install -e ".[dev]"
    pytest
    python -m bigscreen_jukebox        # run from the repo

## License

[GPL-3.0-or-later](LICENSE).
