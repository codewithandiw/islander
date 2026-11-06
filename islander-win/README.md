# Islander for Windows

A Windows port of [Islander](../README.md) — the Dynamic Island-style overlay — written in Rust.

## Features

All features from the macOS version:
- 🎵 **Music** — SMTC (System Media Transport Controls): Spotify, browsers, any Windows player. Play/pause, next, previous, seek, album art, accent color.
- 📝 **Lyrics** — Time-synced via [LRCLIB](https://lrclib.net), cached 30 days.
- 🎧 **Visualizer** — WASAPI loopback FFT bars (no special permission needed).
- 🧘 **Mascot** — Animated blob character, same moods as macOS version.
- ⏱ **Focus** — Active-time tracker using `GetLastInputInfo`, screen-lock & sleep aware.
- 🔔 **Reminders** — Break / stretch / drink after configurable active-time thresholds.
- 📅 **Event reminders** — Custom date reminders with repeat, lead time, and snooze.
- 📥 **Shelf** — Drag files onto the island; they live in a temp folder until you clean or quit.
- ⚙️ **Settings** — Persisted as JSON in `%APPDATA%\Islander\settings.json`.

## Requirements

- Windows 10 (1903+) or Windows 11
- Rust toolchain (stable): `rustup target add x86_64-pc-windows-msvc`
- For cross-compiling from macOS/Linux: use `cross` or a Windows VM

## Build

```powershell
# From the islander-win/ directory on Windows:
cargo build --release

# The binary ends up at:
# target\release\islander.exe
```

For a cross-compile from macOS (needs Docker + `cross`):
```bash
cargo install cross
cross build --target x86_64-pc-windows-msvc --release
```

## Install

1. Copy `target\release\islander.exe` anywhere.
2. Add a shortcut to `shell:startup` for auto-start at login.
3. The settings and cache are stored in `%APPDATA%\Islander\`.

## How the pill is positioned

Windows has no hardware notch, so Islander uses the macOS "no-notch" fallback: a **rounded pill centered at the very top edge** of the primary monitor, overlapping the system title bar area. The window is `WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE`, so it always floats above other windows without appearing in the taskbar or Alt-Tab list.

## Architecture

| Module | Purpose |
|---|---|
| `src/main.rs` | Entry point, tokio runtime, eframe launch |
| `src/now_playing/` | SMTC watcher, `NowPlayingInfo` struct, playback commands |
| `src/lyrics/` | LRCLIB provider, LRC parser, 30-day disk cache |
| `src/visualizer/` | WASAPI loopback + rustfft, 24 log-spaced bands |
| `src/focus/` | `ActivityTracker` + `ReminderScheduler` |
| `src/reminder/` | Event reminder store (JSON persistence) |
| `src/shelf/` | Temp-dir file shelf, OLE clipboard |
| `src/settings/` | `AppSettings` ↔ JSON |
| `src/sound/` | `rodio` MP3 player (sounds embedded at compile time) |
| `src/ui/` | All egui UI: island, tabs, mascot, bars, settings |
| `src/window/` | WTS session-lock + power event registration |

