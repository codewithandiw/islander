# Islander

A Dynamic Island for the Mac notch, written in Swift and SwiftUI.

- **Music**: shows what plays in Spotify, Apple Music, or a browser tab (YouTube Music, SoundCloud, …) with play/pause, next, previous and seeking. Includes an audio visualizer and time-synced lyrics.
- **Mascot**: a small blob character that dances while music plays, sleeps when nothing plays, and waves at you for reminders.
- **Focus**: counts your active work time today, with a 7-day history. Reminds you to take a break, stretch and drink water (every 3 hours of active time by default).
- **Shelf**: drag screenshots or files onto the island to keep a temporary copy (max 10 MB per file, 100 MB total). Drag them back out to any app, double-click to open, right-click to copy. **Clean** deletes the copies; the shelf also empties when Islander quits. Originals are never changed.
- **Lighting**: a light sweep runs along the island edge when it opens or a reminder arrives; the island glows and grows a little while you drag a file over it.
- **Settings**: gear button in the expanded island, or right-click the island.

## Requirements

- macOS 15 or later (built and tested on macOS 26 with a notched MacBook; screens without a notch get a pill at the top center)
- Swift 6 toolchain (Command Line Tools are enough; Xcode is optional)
- CMake (`brew install cmake`) to build the media adapter

## Build and run

### macOS Version

#### Requirements:
- macOS 15 or later (tested on macOS with notch; non-notch screens get a top-center pill)
- Swift 6 toolchain (Command Line Tools are enough; Xcode is optional)
- CMake (`brew install cmake`) to build the media adapter

#### Build:
```bash
scripts/build-app.sh
open build/Islander.app
```

The script fetches and builds [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) into `vendor/`, builds the Swift app, and bundles it into `build/Islander.app`.

> **Tip for sharing with another Mac:** If macOS shows *"The application cannot be opened"* or *"is damaged"*, remove the Gatekeeper quarantine flag:
> ```bash
> xattr -cr /Applications/Islander.app && chmod +x /Applications/Islander.app/Contents/MacOS/Islander
> ```

---

### Windows Version (Rust)

A full recreation of Islander for Windows is available in the [`islander-win`](./islander-win) folder.

#### Requirements:
- Windows 10 (1903+) or Windows 11
- Rust toolchain (`stable`) with `x86_64-pc-windows-msvc` or `x86_64-pc-windows-gnu` target

#### Build on Windows (Native):
```powershell
cd islander-win
cargo build --release
```
The executable will be located at:
```
islander-win\target\release\islander.exe
```

#### Cross-Compile from macOS (via MinGW):
```bash
# 1. Install MinGW & target
brew install mingw-w64
rustup target add x86_64-pc-windows-gnu

# 2. Build release .exe
cd islander-win
cargo build --release --target x86_64-pc-windows-gnu
```
The resulting executable is generated at:
```
islander-win/target/x86_64-pc-windows-gnu/release/islander.exe
```

#### Running & Installing on Windows:
1. Double-click `islander.exe` or copy it to your preferred location (e.g. `C:\Program Files\Islander` or `%LOCALAPPDATA%\Programs\Islander`).
2. To launch automatically at startup, create a shortcut to `islander.exe` and place it in the Windows Startup folder (press `Win + R`, type `shell:startup`, and press Enter).
3. Configuration and cache files are saved in `%APPDATA%\Islander\`.

### App icon and metadata

The black & white icon is drawn in code. Edit `scripts/make-icon.swift`, then run `swift scripts/make-icon.swift` to regenerate `Resources/AppIcon.icns` (and a 1024 px `AppIcon.png` preview).
Bundle ID, version, copyright and category live in `Resources/Info.plist`. Bump `CFBundleShortVersionString` and `CFBundleVersion` for each release.

### Checking the layout without the notch

Debug builds can render every island state to PNG files. The renderer cannot draw drag-and-drop or scroll views, so those are left out in snapshot mode:

```bash
swift build && .build/debug/Islander --snapshot /tmp/islander-snapshots
```

## Permissions

| Feature | Permission | When |
| --- | --- | --- |
| Visualizer | System Audio Recording | Asked the first time music plays. If denied, the bars use a fake animation. |
| Now playing, focus time, reminders | None | — |

The app is ad-hoc signed, so macOS may ask for audio permission again after each rebuild.

## How it works

| Part | File | Notes |
| --- | --- | --- |
| Island window | `Island/IslandWindowController.swift` | Transparent panel above the menu bar. Clicks pass through except over the island. |
| Now playing | `Music/NowPlayingService.swift` | Since macOS 15.4 only Apple-signed apps may read Now Playing, so the adapter runs inside `/usr/bin/perl` and streams JSON. This uses a private API: fine for personal use, not allowed on the App Store. |
| Lyrics | `Music/LyricsService.swift`, `Music/Lyrics/` | [LRCLIB](https://lrclib.net), free, no API key. The song title and artist are sent to look up lyrics. Multi-artist names ("A, B, dan C", "A feat. B") are split, and remixes/live versions are not mixed up with the original. Found lyrics are cached for 30 days in `~/Library/Caches/dev.andiw.islander/Lyrics`. |
| Visualizer | `Visualizer/SystemAudioTap.swift` | Core Audio process tap + FFT (Accelerate). Audio is analyzed in memory only. |
| Focus time | `Focus/ActivityTracker.swift` | Active = unlocked, awake, and keyboard/mouse input within the idle threshold (default 5 min). History is kept for 30 days in UserDefaults. |
| Shelf | `Shelf/ShelfStore.swift` | Copies live in `$TMPDIR/IslanderShelf`, one folder per file, deleted on Clean and on quit. |
| Reminders | `Focus/ReminderScheduler.swift` | Count active time only. Being away 15+ min counts as a break and resets them. |

## Known limits

- If a future macOS update breaks the media adapter, the island shows "Nothing playing" with a warning. Update `ADAPTER_COMMIT` in `scripts/build-app.sh` to a newer adapter release.
- Lyrics depend on LRCLIB having the song and being online. During an LRCLIB outage only songs already in the 30-day cache show lyrics; the island shows "Lyrics services are busy, retrying…" and tries 3 times, 15 seconds apart.
- Test a lookup from the terminal: `swift build && .build/debug/Islander --lyrics "Artist" "Title" <seconds>`.
