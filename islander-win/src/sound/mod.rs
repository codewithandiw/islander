// sound/mod.rs — MP3 sound playback using rodio with embedded assets

use once_cell::sync::Lazy;
use parking_lot::Mutex;
use rodio::{Decoder, OutputStream, OutputStreamHandle, Sink};
use std::io::Cursor;

// Embed all sounds at compile time so the EXE is self-contained.
static AMONG_US: &[u8] = include_bytes!("../../assets/sounds/among_us.mp3");
static BRUH: &[u8] = include_bytes!("../../assets/sounds/bruh.mp3");
static HUH: &[u8] = include_bytes!("../../assets/sounds/huh.mp3");
static METAL_GEAR: &[u8] = include_bytes!("../../assets/sounds/metal_gear.mp3");
static SAD_VIOLIN: &[u8] = include_bytes!("../../assets/sounds/sad_violin.mp3");
static SHOCKED: &[u8] = include_bytes!("../../assets/sounds/shocked.mp3");

struct Player {
    _stream: OutputStream,
    handle: OutputStreamHandle,
}

unsafe impl Send for Player {}
unsafe impl Sync for Player {}

static PLAYER: Lazy<Mutex<Option<Player>>> = Lazy::new(|| {
    let result = OutputStream::try_default()
        .ok()
        .map(|(stream, handle)| Player {
            _stream: stream,
            handle,
        });
    Mutex::new(result)
});

/// Play a sound by its file basename (without extension).
/// Returns false if the sound name is unknown or playback fails.
pub fn play(name: &str) -> bool {
    let bytes: &[u8] = match name {
        "among_us" => AMONG_US,
        "bruh" => BRUH,
        "huh" => HUH,
        "metal_gear" => METAL_GEAR,
        "sad_violin" => SAD_VIOLIN,
        "shocked" => SHOCKED,
        _ => return false,
    };

    let guard = PLAYER.lock();
    let Some(player) = guard.as_ref() else {
        return false;
    };

    let cursor = Cursor::new(bytes);
    let source = match Decoder::new(cursor) {
        Ok(s) => s,
        Err(_) => return false,
    };
    let sink = match Sink::try_new(&player.handle) {
        Ok(s) => s,
        Err(_) => return false,
    };
    sink.append(source);
    sink.detach();
    true
}

pub use crate::settings::FocusReminderSound;

impl FocusReminderSound {
    pub fn play(&self) -> bool {
        play(self.file_name())
    }
}

/// Zero-size marker so AppState can hold a "SoundPlayer" token.
pub struct SoundPlayer;
