# Flatpak / Flathub packaging

App ID: **`io.github.shreyasajj.MusicAssistantDesktopTv`**

> If you rename the GitHub repo, the app ID must stay `io.github.<user>.<repo>`
> (in CamelCase, no hyphens) for Flathub's GitHub verification. Rename the files
> in this folder, the `id:` in the manifest, the `<id>`/`launchable` in the
> metainfo, the `Icon=` in the `.desktop`, and the URLs throughout to match.

Files here:

| File | Purpose |
|------|---------|
| `io.github.shreyasajj.MusicAssistantDesktopTv.yaml` | Flatpak build manifest |
| `io.github.shreyasajj.MusicAssistantDesktopTv.metainfo.xml` | AppStream metadata (name, screenshots, license…) |
| `io.github.shreyasajj.MusicAssistantDesktopTv.desktop` | Desktop entry |
| `io.github.shreyasajj.MusicAssistantDesktopTv.svg` | App icon |
| `requirements.txt` | Input for `flatpak-pip-generator` |
| `python3-requirements.json` | **Generated** (pinned deps) — see below |

## 1. Build & test locally (Linux + flatpak)

```bash
# one-time
flatpak install flathub org.freedesktop.Platform//24.08 org.freedesktop.Sdk//24.08
pip install requests   # for flatpak-pip-generator

# pin the Python deps (offline Flatpak builds need hashes)
curl -fLO https://raw.githubusercontent.com/flatpak/flatpak-builder-tools/master/pip/flatpak-pip-generator
python flatpak-pip-generator --runtime=org.freedesktop.Sdk//24.08 \
        --requirements-file=flatpak/requirements.txt \
        --output flatpak/python3-requirements
# -> writes flatpak/python3-requirements.json

# build + run
flatpak-builder --user --install --force-clean build-dir \
        flatpak/io.github.shreyasajj.MusicAssistantDesktopTv.yaml
flatpak run io.github.shreyasajj.MusicAssistantDesktopTv
```

Validate the metadata before submitting:

```bash
flatpak run org.freedesktop.appstream-glib validate \
        flatpak/io.github.shreyasajj.MusicAssistantDesktopTv.metainfo.xml
desktop-file-validate flatpak/io.github.shreyasajj.MusicAssistantDesktopTv.desktop
```

## 2. Submit to Flathub

1. Tag a release in this repo (e.g. `v0.1.0`) and in the manifest swap the app
   module's `dir` source for the pinned `git` source (uncomment the block, fill
   in the tag + commit SHA).
2. Fork <https://github.com/flathub/flathub>.
3. On a **new branch named exactly `io.github.shreyasajj.MusicAssistantDesktopTv`**,
   add the manifest + `python3-requirements.json` + the metainfo/desktop/icon if
   the manifest references them by path.
4. Open a PR against the **`new-pr`** branch of `flathub/flathub`.
5. A reviewer runs the build and gives feedback; once merged, Flathub creates a
   dedicated repo and publishes the app. Future updates come from PRs to that repo
   (typically bumping the git tag).

Docs: <https://docs.flathub.org/docs/for-app-authors/submission>

## Notes / known iteration points

- The manifest uses the **freedesktop** runtime with the self-contained PySide6
  wheel (same as the AppImage), which is the most reliable first build. Flathub
  reviewers may prefer the **KDE** runtime (`org.kde.Platform`) to avoid bundling
  Qt twice — that's a reasonable follow-up but needs PySide6 wired to the runtime
  Qt.
- `--no-build-isolation` requires `setuptools`/`wheel` at build time. If the build
  can't find them, add `setuptools` and `wheel` to `requirements.txt` before
  generating the pinned JSON.
- Live visualizer/art-pump capture needs PortAudio (built here) plus PipeWire's
  pulse socket (`--socket=pulseaudio`); without a capture source the app still
  runs and falls back to the simulated visualizer.
