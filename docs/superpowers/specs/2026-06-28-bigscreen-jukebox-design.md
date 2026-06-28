# Bigscreen Jukebox — Music Assistant TV App

**Date:** 2026-06-28
**Status:** Design — pending review
**Target:** Plasma Bigscreen (TV running Music Assistant for Home Assistant)

## Summary

A native Plasma Bigscreen application that turns the TV into a music
front-end for a [Music Assistant](https://www.music-assistant.io/) server.
It lets a person at the TV search for songs with the keyboard/remote, see
what is currently playing, follow karaoke-style synced lyrics, and watch a
fullscreen beat-reactive visualizer. A toggleable **guest mode** lets people
on the same network add songs to the queue from their phones via a QR code.

The app is built for a 10-foot ("across the room") experience: big fonts,
big artwork, fullscreen visuals, and navigation that works with both a remote
and a keyboard.

## Goals

- See the current track (art, title, artist, progress) at a glance from the couch.
- Search the music library and play / queue results using the on-screen keyboard.
- Show **synced (karaoke) lyrics**, sourced exactly the way Music Assistant
  itself does.
- A fullscreen visualizer that reacts to the actual beat of the playing audio.
- Full playback transport control (play/pause, next, previous, seek, volume).
- A guest mode that, when enabled, shows a join prompt (QR + URL) in the
  top-right and lets guests add songs to the queue from their phones; when
  disabled, the prompt and guest access disappear entirely.

## Non-Goals

- Not a replacement for the Music Assistant web UI or the Home Assistant app.
- No account system or cloud component — everything runs on the local network.
- No music-library management (editing metadata, playlists curation, etc.).
- No host approval workflow for guest songs in v1 (additions go straight to
  the queue).

## Key Decisions (from brainstorming)

| Decision | Choice |
|---|---|
| Packaging | Native Plasma Bigscreen app (Kirigami / QML) |
| Backend language | Python (PySide6) — reuses the official Music Assistant client library |
| Data source | Direct to the Music Assistant **server WebSocket API** (`ws://<host>:8095/ws`) — no Home Assistant dependency |
| Visualizer audio | Capture TV system audio via **PipeWire** loopback + FFT for true beat reactivity |
| Lyrics | Read from Music Assistant's own track metadata (synced LRC when available) — same source/behaviour as MA |
| Guest mode | QR code → phone web page, served by an embedded web server in the app |
| Guest additions | Straight to the active player's queue (no approval step) |
| Layout | Separate tabbed full screens, switched by remote/keyboard |
| Player targeting | Configured default player, switchable on screen via a player picker |
| Playback controls | Full transport (play/pause, next, prev, seek, volume) |

## Architecture

Single Python (PySide6) process hosting a Kirigami/QML UI. The Python side
owns all I/O and state; QML binds reactively to that state.

```
                  ┌─────────────────────────────────────────┐
                  │            QML / Kirigami UI              │
                  │  NowPlaying · Search · Lyrics · Visualizer│
                  │           Guest QR overlay                │
                  └───────────────▲───────────────▲──────────┘
                                  │ bindings      │ live audio bands
        ┌─────────────────────────┴──────┐ ┌──────┴───────────────┐
        │      App State (QObjects)        │ │  Audio Analysis svc  │
        │  player, now-playing, queue,     │ │  PipeWire capture →  │
        │  search results, lyrics          │ │  FFT → beat/energy   │
        └───────▲──────────────────▲───────┘ └──────────────────────┘
                │ events/actions    │ add-to-queue
        ┌───────┴───────────┐ ┌─────┴──────────────┐
        │   MA Client svc    │ │  Guest web server  │
        │  WebSocket to MA   │ │  (aiohttp, toggle) │
        └───────▲───────────┘ └─────▲──────────────┘
                │ ws://host:8095/ws        │ http (phones)
        ┌───────┴───────────┐       ┌──────┴──────────┐
        │ Music Assistant    │       │  Guest phones    │
        │ server             │       │  (same network)  │
        └────────────────────┘       └──────────────────┘
```

## Components

Each component has one purpose, a defined interface, and is testable on its own.

### 1. MA Client service
- **Does:** Maintains the WebSocket connection to the Music Assistant server,
  subscribes to events, and exposes state + actions to the rest of the app.
- **Interface (state):** player list, active player's now-playing
  (art / title / artist / position / duration), current queue, search results,
  lyrics (synced LRC lines when available, else plain text, else none).
- **Interface (actions):** `search(query)`, `play_now(item)`,
  `add_to_queue(item)`, `play_pause()`, `next()`, `previous()`, `seek(pos)`,
  `set_volume(level)`, `select_player(id)`.
- **Depends on:** `music-assistant-client`, MA server host/port/token from
  settings.
- **Notes:** Reconnects automatically; surfaces a connection state to the UI.

### 2. Audio analysis service
- **Does:** Captures the TV's system audio output via a PipeWire loopback,
  runs an FFT, and produces beat/energy and frequency-band values.
- **Interface:** live properties — overall energy, low/mid/high band levels,
  beat pulse — read by the visualizer at frame rate.
- **Depends on:** PipeWire (monitor/loopback source), numpy.
- **Notes:** Runs on its own thread; degrades to a calm idle animation when no
  audio is present or capture is unavailable.

### 3. Guest web server
- **Does:** When guest mode is enabled, serves a mobile-friendly page so people
  on the same network can search and add songs to the active queue.
- **Interface:** HTTP endpoints for search and add-to-queue; the add path goes
  through the MA Client service. Generates the join URL and a QR code.
- **Depends on:** aiohttp, the MA Client service.
- **Notes:** Off by default. Enabling starts the server and reveals the QR
  overlay; disabling stops the server and hides it. Additions go straight to
  the queue (no approval in v1).

### 4. QML / Kirigami UI
- **Does:** Renders the four tabbed screens and the guest overlay; handles
  remote + keyboard focus navigation; styled for 10-foot viewing.
- **Depends on:** App state objects and the audio analysis service.

### 5. Settings
- **Does:** Stores MA host/port/token, default player, and guest-mode options;
  provides a settings screen.
- **Depends on:** local config storage.

## Screens

All screens use large fonts, large artwork, and high-contrast 10-foot styling.
Tabs are switched with the remote/keyboard. The guest QR is a global overlay
shown on every tab when guest mode is on.

- **Now Playing** — large album art, big title/artist, progress bar, transport
  controls (play/pause, next, previous, seek, volume), and a player picker to
  switch which player is being viewed/controlled.
- **Search** — a text field that works with the on-screen keyboard/remote, with
  large result rows; selecting a result offers play-now or add-to-queue.
- **Lyrics** — karaoke view: the current line shown large and centered and
  highlighted in sync with playback position; scrolls automatically. Falls back
  to plain scrollable lyrics, then to a "no lyrics found" state.
- **Visualizer** — fullscreen, beat-reactive, driven by the audio analysis
  service.

## Data Flow

1. MA server emits WebSocket events → MA Client service updates app state
   objects → QML bindings update the UI reactively.
2. The audio analysis service continuously publishes band/beat values → the
   visualizer reads them per frame.
3. A guest opens the QR URL → guest web server handles search/add → calls the
   MA Client service → song is added to the active player's queue → the queue
   update flows back through normal MA events.

## Testing Strategy

- **MA Client service:** unit tests against a mocked/stubbed MA WebSocket —
  verify state parsing (now-playing, queue, lyrics) and that actions send the
  right messages.
- **Lyrics parsing:** unit tests for LRC timing parse and current-line
  selection at given playback positions, including the no-lyrics and
  plain-lyrics fallbacks.
- **Audio analysis:** feed known audio buffers and assert expected band/beat
  output; verify graceful behaviour when no capture device is available.
- **Guest web server:** integration tests hitting the HTTP endpoints with the
  MA Client mocked — verify search and add-to-queue, and that the server only
  runs when enabled.
- **UI:** manual verification on the TV (or a Bigscreen environment) for focus
  navigation, readability, and the guest overlay toggle.

## Open Questions / Risks

- **Lyrics over the API:** confirm the exact field/shape Music Assistant exposes
  lyrics through on the WebSocket API (synced LRC vs plain), and pin a minimum
  MA version (lyrics landed in MA 2.6).
- **PipeWire capture:** confirm the right monitor/loopback source on the TV's
  Plasma Bigscreen image and that capturing it does not interfere with playback.
- **MA WS auth:** confirm whether the local MA server requires a token; make it
  configurable either way.
- **Bigscreen + PySide6:** confirm the target Bigscreen image ships (or can
  install) PySide6/Qt and PipeWire dev bits for packaging.

## Milestones (suggested build order)

1. MA Client service + Settings — connect, show now-playing, transport controls.
2. Search screen — search and play/queue.
3. Lyrics screen — read MA lyrics, synced karaoke rendering.
4. Visualizer + audio analysis service.
5. Guest mode — embedded server, QR overlay, add-to-queue.
6. 10-foot polish + remote/keyboard navigation + packaging for Bigscreen.
