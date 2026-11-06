// ui/music.rs — Music tab: artwork, title, artist, scrubber, controls, lyrics, mascot

use super::mascot::{draw_mascot, MascotMood};
use super::spectrum_bars::draw_bars;
use crate::now_playing::PlaybackCommand;
use crate::AppState;
use eframe::egui::{self, Color32, Pos2, Rect, Rounding, Sense, Vec2};

pub fn draw(
    ui: &mut egui::Ui,
    rect: Rect,
    state: &AppState,
    _ctx: &egui::Context,
    art_tex: Option<egui::TextureHandle>,
) {
    let np = state.now_playing.read();
    let settings = state.settings.read();
    let lyrics = state.lyrics.try_lock();

    if let Some(track) = &np.current {
        // Layout: left=artwork(76), middle=info+controls, right=mascot+bars(76)
        let art_size = 76.0;
        let right_w = 76.0;
        let mid_w = rect.width() - art_size - right_w - 32.0; // 2×16 gap

        // Artwork
        let art_rect = Rect::from_min_size(rect.min, Vec2::splat(art_size));
        draw_artwork(ui.painter(), art_rect, art_tex.as_ref());

        // Middle column.
        let mid_rect = Rect::from_min_size(
            rect.min + Vec2::new(art_size + 16.0, 0.0),
            Vec2::new(mid_w, art_size),
        );
        draw_track_info(ui, mid_rect, track);

        // Right column.
        let right_rect = Rect::from_min_size(
            rect.min + Vec2::new(art_size + 16.0 + mid_w + 16.0, 0.0),
            Vec2::new(right_w, art_size),
        );
        if settings.show_mascot {
            let mood = match lyrics.as_ref().ok().map(|l| &l.state) {
                Some(crate::lyrics::LyricsState::Loading)
                | Some(crate::lyrics::LyricsState::Retrying)
                    if track.is_playing =>
                {
                    MascotMood::Spinning
                }
                _ if track.is_playing => MascotMood::Dancing,
                _ => MascotMood::Idle,
            };
            let level = state.spectrum.read().level;
            let mc = settings.mascot_color.rgb();
            draw_mascot(
                ui.painter(),
                right_rect.center() - Vec2::new(0.0, 8.0),
                54.0,
                mood,
                mc,
                level as f64,
            );
        }
        if settings.show_visualizer {
            let bars_rect = Rect::from_min_size(
                right_rect.min + Vec2::new(0.0, right_w - 22.0),
                Vec2::new(right_w, 22.0),
            );
            let bands = &state.spectrum.read().bands.clone();
            draw_bars(ui.painter(), bars_rect, 10, track.accent_color, bands);
        }

        // Lyrics row below.
        if settings.show_lyrics {
            let ly_rect = Rect::from_min_size(
                rect.min + Vec2::new(0.0, art_size + 14.0),
                Vec2::new(rect.width(), 44.0),
            );
            draw_lyrics(ui, ly_rect, lyrics.as_deref().ok(), track.position_now());
        }
    } else {
        // Nothing playing.
        let mood = match np.status {
            crate::now_playing::ServiceStatus::Unavailable(_) => MascotMood::Confused,
            _ => MascotMood::Sleeping,
        };
        let settings = state.settings.read();
        let mc = settings.mascot_color.rgb();
        if settings.show_mascot {
            draw_mascot(
                ui.painter(),
                rect.left_center() + Vec2::new(35.0, 0.0),
                70.0,
                mood,
                mc,
                0.0,
            );
        }
        let tx =
            rect.left_center() + Vec2::new(if settings.show_mascot { 90.0 } else { 0.0 }, -8.0);
        ui.painter().text(
            tx,
            egui::Align2::LEFT_CENTER,
            "Nothing playing",
            egui::FontId::proportional(15.0),
            Color32::WHITE,
        );
        let subtitle = match &np.status {
            crate::now_playing::ServiceStatus::Unavailable(msg) => msg.as_str(),
            _ => "Play something in Spotify or a browser and it shows up here.",
        };
        let col = match &np.status {
            crate::now_playing::ServiceStatus::Unavailable(_) => Color32::from_rgb(255, 165, 0),
            _ => Color32::from_white_alpha(150),
        };
        ui.painter().text(
            tx + Vec2::new(0.0, 18.0),
            egui::Align2::LEFT_TOP,
            subtitle,
            egui::FontId::proportional(11.0),
            col,
        );
    }
}

fn draw_artwork(painter: &egui::Painter, rect: Rect, tex: Option<&egui::TextureHandle>) {
    let round = Rounding::same(14.0);
    if let Some(t) = tex {
        painter.image(
            t.id(),
            rect,
            egui::Rect::from_min_max(Pos2::ZERO, Pos2::new(1.0, 1.0)),
            Color32::WHITE,
        );
    } else {
        painter.rect_filled(rect, round, Color32::from_rgb(80, 40, 120));
        painter.text(
            rect.center(),
            egui::Align2::CENTER_CENTER,
            "♪",
            egui::FontId::proportional(32.0),
            Color32::from_white_alpha(220),
        );
    }
}

fn draw_track_info(
    ui: &mut egui::Ui,
    rect: Rect,
    track: &crate::now_playing::NowPlayingInfo,
) {
    // Title.
    ui.painter().text(
        rect.min + Vec2::new(0.0, 0.0),
        egui::Align2::LEFT_TOP,
        truncate(&track.title, 30),
        egui::FontId::new(14.0, egui::FontFamily::Proportional),
        Color32::WHITE,
    );

    // Artist / album.
    let sub = if !track.artist.is_empty() {
        &track.artist
    } else {
        &track.album
    };
    ui.painter().text(
        rect.min + Vec2::new(0.0, 18.0),
        egui::Align2::LEFT_TOP,
        truncate(sub, 30),
        egui::FontId::proportional(12.0),
        Color32::from_white_alpha(150),
    );

    // Scrubber.
    let scrub_rect = Rect::from_min_size(
        rect.min + Vec2::new(0.0, 36.0),
        Vec2::new(rect.width(), 20.0),
    );
    draw_scrubber(ui, scrub_rect, track);

    // Playback controls.
    let ctrl_rect = Rect::from_min_size(
        rect.min + Vec2::new(0.0, 60.0),
        Vec2::new(rect.width(), 26.0),
    );
    draw_controls(ui, ctrl_rect, track.is_playing);
}

fn draw_scrubber(
    ui: &mut egui::Ui,
    rect: Rect,
    track: &crate::now_playing::NowPlayingInfo,
) {
    let position = track.position_now();
    let fraction = if track.duration_secs > 0.0 {
        (position / track.duration_secs).clamp(0.0, 1.0) as f32
    } else {
        0.0
    };

    let bar_rect =
        Rect::from_min_size(rect.min + Vec2::new(0.0, 6.0), Vec2::new(rect.width(), 5.0));
    ui.painter()
        .rect_filled(bar_rect, Rounding::same(2.5), Color32::from_white_alpha(45));
    let filled_w = (bar_rect.width() * fraction).max(5.0);
    let filled = Rect::from_min_size(bar_rect.min, Vec2::new(filled_w, 5.0));
    ui.painter()
        .rect_filled(filled, Rounding::same(2.5), track.accent_color);

    // Time labels.
    let pos_str = format_time(position);
    let rem_str = format!(
        "-{}",
        format_time((track.duration_secs - position).max(0.0))
    );
    ui.painter().text(
        rect.min + Vec2::new(0.0, 14.0),
        egui::Align2::LEFT_TOP,
        &pos_str,
        egui::FontId::monospace(9.0),
        Color32::from_white_alpha(130),
    );
    ui.painter().text(
        rect.right_top() + Vec2::new(0.0, 14.0),
        egui::Align2::RIGHT_TOP,
        &rem_str,
        egui::FontId::monospace(9.0),
        Color32::from_white_alpha(130),
    );

    // Click & drag to seek.
    let resp = ui.interact(
        bar_rect.expand(6.0),
        egui::Id::new("scrubber"),
        Sense::click_and_drag(),
    );
    if resp.hovered() || resp.dragged() {
        ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
    }
    if resp.dragged() || resp.clicked() || resp.drag_stopped() {
        if let Some(pos) = ui.input(|i| i.pointer.latest_pos()) {
            let ratio = ((pos.x - bar_rect.left()) / bar_rect.width()).clamp(0.0, 1.0);
            let seek = ratio as f64 * track.duration_secs;
            crate::now_playing::send_command(crate::now_playing::PlaybackCommand::Seek(seek));
        }
    }
}

fn draw_controls(ui: &mut egui::Ui, rect: Rect, is_playing: bool) {
    let cx = rect.center().x;
    let cy = rect.center().y;
    let buttons = [
        (cx - 60.0, "⏮", 15.0, PlaybackCommand::PreviousTrack),
        (
            cx,
            if is_playing { "⏸" } else { "▶" },
            20.0,
            PlaybackCommand::TogglePlayPause,
        ),
        (cx + 60.0, "⏭", 15.0, PlaybackCommand::NextTrack),
    ];
    for (x, icon, sz, cmd) in buttons {
        let btn_rect = Rect::from_center_size(Pos2::new(x, cy), Vec2::new(32.0, 26.0));
        let resp = ui.interact(
            btn_rect,
            egui::Id::new(format!("ctrl_{icon}")),
            Sense::click(),
        );
        if resp.hovered() {
            ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
            ui.painter().rect_filled(btn_rect, Rounding::same(6.0), Color32::from_white_alpha(35));
        }
        ui.painter().text(
            btn_rect.center(),
            egui::Align2::CENTER_CENTER,
            icon,
            egui::FontId::proportional(sz),
            if resp.hovered() { Color32::WHITE } else { Color32::from_white_alpha(220) },
        );
        if resp.clicked() {
            crate::now_playing::send_command(cmd);
        }
    }
}

fn draw_lyrics(
    ui: &mut egui::Ui,
    rect: Rect,
    lyrics: Option<&crate::lyrics::LyricsService>,
    position: f64,
) {
    let Some(lyrics) = lyrics else {
        return;
    };
    let text = match &lyrics.state {
        crate::lyrics::LyricsState::Synced(lines) => {
            let time = position + 0.25;
            let idx = crate::lyrics::LyricsService::line_index(lines, time);
            let (current, next) = match idx {
                Some(i) => {
                    let cur = lines[i].text.trim();
                    let nxt = lines.get(i + 1).map(|l| l.text.trim()).unwrap_or("");
                    (if cur.is_empty() { "♪" } else { cur }, nxt)
                }
                None => {
                    let nxt = lines.first().map(|l| l.text.trim()).unwrap_or("");
                    ("♪", nxt)
                }
            };
            ui.painter().text(
                rect.center_top(),
                egui::Align2::CENTER_TOP,
                truncate(current, 48),
                egui::FontId::new(14.0, egui::FontFamily::Proportional),
                Color32::WHITE,
            );
            if !next.is_empty() {
                ui.painter().text(
                    rect.center_top() + Vec2::new(0.0, 18.0),
                    egui::Align2::CENTER_TOP,
                    truncate(next, 52),
                    egui::FontId::proportional(12.0),
                    Color32::from_white_alpha(115),
                );
            }
            return;
        }
        crate::lyrics::LyricsState::Loading => "Looking for lyrics…",
        crate::lyrics::LyricsState::Retrying => "Lyrics services are busy, retrying…",
        crate::lyrics::LyricsState::Unsynced => "Lyrics found, but they are not time-synced",
        crate::lyrics::LyricsState::Instrumental => "Instrumental ♪",
        crate::lyrics::LyricsState::NotFound => "No lyrics found",
        crate::lyrics::LyricsState::Failed => "Lyrics unavailable (offline?)",
        crate::lyrics::LyricsState::Idle => return,
    };
    ui.painter().text(
        rect.center(),
        egui::Align2::CENTER_CENTER,
        text,
        egui::FontId::proportional(12.0),
        Color32::from_white_alpha(115),
    );
}

fn format_time(secs: f64) -> String {
    let s = secs as u64;
    format!("{}:{:02}", s / 60, s % 60)
}

fn truncate(s: &str, max_chars: usize) -> &str {
    let mut end = s.len();
    for (i, _) in s.char_indices().skip(max_chars) {
        end = i;
        break;
    }
    &s[..end]
}
