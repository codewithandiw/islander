// now_playing/mod.rs — Windows SMTC watcher

use eframe::egui;
use image::DynamicImage;
use parking_lot::RwLock;
use std::sync::Arc;
use tokio::sync::Mutex;

#[cfg(windows)]
use windows::{
    Foundation::TypedEventHandler,
    Media::Control::{
        GlobalSystemMediaTransportControlsSession as SmtcSession,
        GlobalSystemMediaTransportControlsSessionManager as SessionManager,
        GlobalSystemMediaTransportControlsSessionPlaybackStatus as PlaybackStatus,
    },
    Storage::Streams::{DataReader, IRandomAccessStreamReference},
};

use crate::lyrics::LyricsService;

// ── Data types ────────────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct NowPlayingInfo {
    pub title: String,
    pub artist: String,
    pub album: String,
    pub is_playing: bool,
    pub duration_secs: f64,
    pub position_secs: f64,
    pub position_updated_at: std::time::Instant,
    pub playback_rate: f64,
    pub artwork: Option<Arc<DynamicImage>>,
    pub accent_color: egui::Color32,
    pub source_app: String,
}

impl Default for NowPlayingInfo {
    fn default() -> Self {
        Self {
            title: String::new(),
            artist: String::new(),
            album: String::new(),
            is_playing: false,
            duration_secs: 0.0,
            position_secs: 0.0,
            position_updated_at: std::time::Instant::now(),
            playback_rate: 0.0,
            artwork: None,
            accent_color: egui::Color32::WHITE,
            source_app: String::new(),
        }
    }
}

impl NowPlayingInfo {
    pub fn position_now(&self) -> f64 {
        if self.is_playing {
            let elapsed = self.position_updated_at.elapsed().as_secs_f64();
            let pos = self.position_secs + elapsed * self.playback_rate.max(0.0);
            if self.duration_secs > 0.0 {
                pos.min(self.duration_secs)
            } else {
                pos
            }
        } else {
            self.position_secs
        }
    }

    pub fn track_key(&self) -> String {
        format!("{}\x1f{}", self.artist, self.title)
    }
}

#[derive(Debug, Default)]
pub struct NowPlayingState {
    pub current: Option<NowPlayingInfo>,
    pub status: ServiceStatus,
}

#[derive(Debug, Default, PartialEq, Clone)]
pub enum ServiceStatus {
    #[default]
    Starting,
    Running,
    Unavailable(String),
}

// ── SMTC watcher ─────────────────────────────────────────────────────────────

pub async fn run_smtc_watcher(
    state: Arc<RwLock<NowPlayingState>>,
    lyrics: Arc<Mutex<LyricsService>>,
) {
    #[cfg(windows)]
    {
        if let Err(e) = smtc_loop(state.clone(), lyrics).await {
            let mut s = state.write();
            s.status = ServiceStatus::Unavailable(format!("SMTC error: {e}"));
        }
    }
    #[cfg(not(windows))]
    {
        // On non-Windows builds (CI, dev on Mac), just sit idle.
        let _ = lyrics;
        loop {
            tokio::time::sleep(std::time::Duration::from_secs(60)).await;
        }
    }
}

#[cfg(windows)]
async fn smtc_loop(
    state: Arc<RwLock<NowPlayingState>>,
    lyrics: Arc<Mutex<LyricsService>>,
) -> windows::core::Result<()> {
    // Request the session manager synchronously via .get().
    let manager = SessionManager::RequestAsync()?.get()?;

    // We use an unbounded channel to route WinRT callbacks → async task.
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<()>();

    // Helper: clone sender for closures.
    macro_rules! notify {
        ($tx:expr) => {{
            let tx = $tx.clone();
            TypedEventHandler::new(move |_, _| {
                let _ = tx.send(());
                Ok(())
            })
        }};
    }

    // Subscribe to session-level changes.
    manager.CurrentSessionChanged(&notify!(tx))?;
    manager.SessionsChanged(&notify!(tx))?;

    // Initial read.
    tx.send(()).ok();

    while rx.recv().await.is_some() {
        let session_opt = manager.GetCurrentSession().ok();
        let info = match session_opt {
            None => None,
            Some(ref session) => read_session(session).ok(),
        };

        let prev_key = state.read().current.as_ref().map(|i| i.track_key());
        {
            let mut s = state.write();
            s.current = info.clone();
            s.status = ServiceStatus::Running;
        }

        // Trigger lyrics update when track changes or when lyrics need loading.
        if let Some(info) = &info {
            let new_key = info.track_key();
            let key_changed = prev_key.as_deref() != Some(&new_key);
            let mut lyr = lyrics.lock().await;
            let needs_update = key_changed
                || lyr.current_key.is_none()
                || matches!(
                    lyr.state,
                    crate::lyrics::LyricsState::Idle | crate::lyrics::LyricsState::Failed
                );
            if needs_update && !info.title.is_empty() {
                lyr.update(Some(&info.title), Some(&info.artist), info.duration_secs);
            }
        } else if prev_key.is_some() {
            let mut lyr = lyrics.lock().await;
            lyr.update(None, None, 0.0);
        }

        // Also subscribe to per-session property changes so we get real-time position & status.
        if let Some(session) = session_opt {
            let tx2 = tx.clone();
            let _ = session.PlaybackInfoChanged(&TypedEventHandler::new(move |_, _| {
                let _ = tx2.send(());
                Ok(())
            }));
            let tx3 = tx.clone();
            let _ = session.MediaPropertiesChanged(&TypedEventHandler::new(move |_, _| {
                let _ = tx3.send(());
                Ok(())
            }));
            let tx4 = tx.clone();
            let _ = session.TimelinePropertiesChanged(&TypedEventHandler::new(move |_, _| {
                let _ = tx4.send(());
                Ok(())
            }));
        }
    }
    Ok(())
}

#[cfg(windows)]
fn read_session(session: &SmtcSession) -> windows::core::Result<NowPlayingInfo> {
    let props = session.TryGetMediaPropertiesAsync()?.get()?;
    let playback = session.GetPlaybackInfo()?;
    let timeline = session.GetTimelineProperties()?;

    let title = props.Title()?.to_string();
    let artist = props.Artist()?.to_string();
    let album = props.AlbumTitle()?.to_string();
    let source_app = session
        .SourceAppUserModelId()
        .map(|s| s.to_string())
        .unwrap_or_default();

    let is_playing = playback.PlaybackStatus()? == PlaybackStatus::Playing;
    let playback_rate = playback
        .PlaybackRate()
        .ok()
        .and_then(|r| r.Value().ok())
        .unwrap_or(if is_playing { 1.0 } else { 0.0 });

    let duration_secs = timeline
        .EndTime()
        .map(|t| t.Duration as f64 / 10_000_000.0)
        .unwrap_or(0.0);
    let position_secs = timeline
        .Position()
        .map(|t| t.Duration as f64 / 10_000_000.0)
        .unwrap_or(0.0);

    // Artwork
    let artwork = decode_artwork(props.Thumbnail().ok());
    let accent_color = artwork
        .as_ref()
        .and_then(|img| dominant_color(img))
        .unwrap_or(egui::Color32::WHITE);

    Ok(NowPlayingInfo {
        title,
        artist,
        album,
        is_playing,
        duration_secs,
        position_secs,
        position_updated_at: std::time::Instant::now(),
        playback_rate,
        artwork: artwork.map(Arc::new),
        accent_color,
        source_app,
    })
}

#[cfg(windows)]
fn decode_artwork(thumb: Option<IRandomAccessStreamReference>) -> Option<DynamicImage> {
    let thumb = thumb?;
    let stream = thumb.OpenReadAsync().ok()?.get().ok()?;
    let size = stream.Size().ok()? as u32;
    if size == 0 {
        return None;
    }
    let reader = DataReader::CreateDataReader(&stream).ok()?;
    let _ = reader.LoadAsync(size).ok()?.get().ok()?;
    let mut bytes = vec![0u8; size as usize];
    reader.ReadBytes(&mut bytes).ok()?;
    image::load_from_memory(&bytes).ok()
}

#[cfg(not(windows))]
fn decode_artwork(_: Option<()>) -> Option<DynamicImage> {
    None
}

fn dominant_color(img: &DynamicImage) -> Option<egui::Color32> {
    let rgba = img.to_rgba8();
    let pixels: Vec<u8> = rgba
        .pixels()
        .filter(|p| p.0[3] > 10)
        .flat_map(|p| [p.0[0], p.0[1], p.0[2], p.0[3]])
        .collect();
    if pixels.is_empty() {
        return None;
    }
    let palette = color_thief::get_palette(&pixels, color_thief::ColorFormat::Rgba, 10, 5).ok()?;
    let c = palette.into_iter().max_by_key(|c| {
        // Prefer vivid, reasonably bright colors — like the macOS accent extraction.
        let r = c.r as i32;
        let g = c.g as i32;
        let b = c.b as i32;
        let brightness = r + g + b;
        let saturation = (r - g).abs() + (g - b).abs() + (b - r).abs();
        // Skip near-black and near-white.
        if brightness < 60 || brightness > 700 {
            0
        } else {
            saturation
        }
    })?;
    Some(egui::Color32::from_rgb(c.r, c.g, c.b))
}

// ── Playback commands ─────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy)]
pub enum PlaybackCommand {
    #[allow(dead_code)]
    Play,
    #[allow(dead_code)]
    Pause,
    TogglePlayPause,
    NextTrack,
    PreviousTrack,
    Seek(f64), // seconds
}

#[cfg(windows)]
pub fn send_command(cmd: PlaybackCommand) {
    if let Ok(manager) = SessionManager::RequestAsync().and_then(|a| a.get()) {
        if let Ok(session) = manager.GetCurrentSession() {
            match cmd {
                PlaybackCommand::Play => {
                    let _ = session.TryPlayAsync();
                }
                PlaybackCommand::Pause => {
                    let _ = session.TryPauseAsync();
                }
                PlaybackCommand::TogglePlayPause => {
                    let _ = session.TryTogglePlayPauseAsync();
                }
                PlaybackCommand::NextTrack => {
                    let _ = session.TrySkipNextAsync();
                }
                PlaybackCommand::PreviousTrack => {
                    let _ = session.TrySkipPreviousAsync();
                }
                PlaybackCommand::Seek(secs) => {
                    let ticks = windows::Foundation::TimeSpan {
                        Duration: (secs * 10_000_000.0) as i64,
                    };
                    let _ = session.TryChangePlaybackPositionAsync(ticks.Duration);
                }
            }
        }
    }
}

#[cfg(not(windows))]
pub fn send_command(_cmd: PlaybackCommand) {}
