// ui/mod.rs — egui app root: island window, tabs, layout

pub mod focus_tab;
pub mod mascot;
pub mod music;
pub mod reminder_tab;
pub mod settings_win;
pub mod shelf_tab;
pub mod spectrum_bars;

use crate::AppState;
use eframe::egui::{self, Color32, Pos2, Rect, Rounding, Vec2};

// ── Island layout constants ───────────────────────────────────────────────────

const PILL_WIDTH: f32 = 190.0;
const PILL_HEIGHT: f32 = 32.0;
const COMPACT_SIDE: f32 = 88.0;
const EXPANDED_WIDTH: f32 = 600.0;
const EXPANDED_CONTENT_HEIGHT: f32 = 192.0;

#[derive(Debug, Clone, PartialEq)]
pub enum IslandTab {
    Music,
    Reminder,
    Focus,
    Shelf,
}

#[derive(Debug, Clone, PartialEq)]
pub enum IslandState {
    Pill,
    Compact,
    Expanded,
}

pub struct IslanderApp {
    state: AppState,
    island_state: IslandState,
    tab: IslandTab,
    target_w: f32,
    target_h: f32,
    current_w: f32,
    current_h: f32,
    hovering: bool,
    hover_timer: f32,
    collapse_timer: f32,
    settings_open: bool,
    // Artwork texture cache
    art_texture: Option<(egui::TextureHandle, String)>, // (tex, track_key)
    #[cfg(windows)]
    hwnd: Option<windows::Win32::Foundation::HWND>,
    window_centered: bool,
    mouse_passthrough: bool,
}

impl IslanderApp {
    pub fn new(cc: &eframe::CreationContext, state: AppState) -> Self {
        // Transparent window already set in native options.
        let mut fonts = egui::FontDefinitions::default();
        #[cfg(windows)]
        {
            if let Ok(data) = std::fs::read("C:\\Windows\\Fonts\\segoeui.ttf") {
                fonts.font_data.insert(
                    "segoe_ui".to_owned(),
                    egui::FontData::from_owned(data),
                );
                fonts
                    .families
                    .entry(egui::FontFamily::Proportional)
                    .or_default()
                    .insert(0, "segoe_ui".to_owned());
            }
            if let Ok(data) = std::fs::read("C:\\Windows\\Fonts\\segoeuib.ttf") {
                fonts.font_data.insert(
                    "segoe_ui_bold".to_owned(),
                    egui::FontData::from_owned(data),
                );
                fonts
                    .families
                    .entry(egui::FontFamily::Name("bold".into()))
                    .or_default()
                    .push("segoe_ui_bold".to_owned());
                // Also add to proportional fallback after regular Segoe UI
                fonts
                    .families
                    .entry(egui::FontFamily::Proportional)
                    .or_default()
                    .push("segoe_ui_bold".to_owned());
            }
        }
        cc.egui_ctx.set_fonts(fonts);

        Self {
            state,
            island_state: IslandState::Pill,
            tab: IslandTab::Music,
            target_w: PILL_WIDTH,
            target_h: PILL_HEIGHT,
            current_w: PILL_WIDTH,
            current_h: PILL_HEIGHT,
            hovering: false,
            hover_timer: 0.0,
            collapse_timer: 0.0,
            settings_open: false,
            art_texture: None,
            #[cfg(windows)]
            hwnd: None,
            window_centered: false,
            mouse_passthrough: false,
        }
    }

    fn update_layout(&mut self) {
        let np = self.state.now_playing.read();
        let rem = self.state.reminders.read();
        let evrem = self.state.event_reminders.read();
        let is_playing = np.current.as_ref().map(|c| c.is_playing).unwrap_or(false);
        let has_reminder = rem.current.is_some() || evrem.active_alert.is_some();

        let (tw, th) = match &self.island_state {
            IslandState::Expanded => {
                let reminder_tab = self.tab == IslandTab::Reminder;
                let content_h = if reminder_tab {
                    190.0
                } else {
                    EXPANDED_CONTENT_HEIGHT
                };
                (
                    EXPANDED_WIDTH.max(PILL_WIDTH + 2.0 * 180.0),
                    PILL_HEIGHT + content_h,
                )
            }
            IslandState::Compact => (PILL_WIDTH + 2.0 * COMPACT_SIDE, PILL_HEIGHT),
            IslandState::Pill => (PILL_WIDTH, PILL_HEIGHT),
        };

        // Decide what state we should be in.
        let desired = if self.island_state == IslandState::Expanded {
            IslandState::Expanded
        } else if is_playing || has_reminder {
            IslandState::Compact
        } else {
            IslandState::Pill
        };
        if desired != self.island_state && self.island_state != IslandState::Expanded {
            self.island_state = desired;
        }

        self.target_w = tw;
        self.target_h = th;
    }

    fn animate_size(&mut self, dt: f32) {
        let speed = 8.0;
        self.current_w += (self.target_w - self.current_w) * (1.0 - (-speed * dt).exp());
        self.current_h += (self.target_h - self.current_h) * (1.0 - (-speed * dt).exp());
    }

    fn expand(&mut self) {
        self.island_state = IslandState::Expanded;
    }

    fn collapse(&mut self) {
        let np = self.state.now_playing.read();
        let rem = self.state.reminders.read();
        let evrem = self.state.event_reminders.read();
        let is_playing = np.current.as_ref().map(|c| c.is_playing).unwrap_or(false);
        let has_reminder = rem.current.is_some() || evrem.active_alert.is_some();
        self.island_state = if is_playing || has_reminder {
            IslandState::Compact
        } else {
            IslandState::Pill
        };
    }

    // ── Artwork texture ───────────────────────────────────────────────────────

    fn get_artwork_texture(&mut self, ctx: &egui::Context) -> Option<egui::TextureHandle> {
        let (track_key, art) = {
            let np = self.state.now_playing.read();
            let key = np
                .current
                .as_ref()
                .map(|c| c.track_key())
                .unwrap_or_default();
            let art = np.current.as_ref().and_then(|c| c.artwork.clone());
            (key, art)
        };

        if let Some((tex, cached_key)) = &self.art_texture {
            if *cached_key == track_key && !track_key.is_empty() {
                return Some(tex.clone());
            }
        }

        let img = art?;
        let rgba = img.to_rgba8();
        let (w, h) = rgba.dimensions();
        let color_image = egui::ColorImage::from_rgba_unmultiplied([w as usize, h as usize], &rgba);
        let handle = ctx.load_texture("artwork", color_image, egui::TextureOptions::LINEAR);
        self.art_texture = Some((handle.clone(), track_key));
        Some(handle)
    }
}

impl eframe::App for IslanderApp {
    fn clear_color(&self, _visuals: &egui::Visuals) -> [f32; 4] {
        [0.0, 0.0, 0.0, 0.0] // transparent
    }

    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Fetch HWND and center window at top of primary monitor on startup
        #[cfg(windows)]
        {
            if self.hwnd.is_none() {
                self.hwnd = crate::window::get_islander_hwnd();
                if let Some(hwnd) = self.hwnd {
                    crate::window::register_session_notifications(hwnd);
                }
            }
            if !self.window_centered {
                if let Some(hwnd) = self.hwnd {
                    self.window_centered = crate::window::center_window_top(hwnd);
                }
            }
        }

        // Poll lyrics results.
        self.state
            .lyrics
            .try_lock()
            .map(|mut l| l.poll_results())
            .ok();

        let dt = ctx.input(|i| i.unstable_dt).min(0.1);
        self.update_layout();
        self.animate_size(dt);

        let screen_rect = ctx.screen_rect();
        let island_rect = centered_island_rect(screen_rect, self.current_w, self.current_h);

        // Global cursor detection for reliable hover & mouse passthrough
        let ppp = ctx.pixels_per_point();
        #[cfg(windows)]
        let cursor_screen = crate::window::get_cursor_screen_pos();
        #[cfg(not(windows))]
        let cursor_screen: Option<(i32, i32)> = None;

        #[cfg(windows)]
        let win_rect = self.hwnd.and_then(|h| crate::window::get_window_rect(h));
        #[cfg(not(windows))]
        let win_rect: Option<windows::Win32::Foundation::RECT> = None;

        let cursor = if let (Some(wr), Some((cx, cy))) = (win_rect, cursor_screen) {
            let rel_x = (cx - wr.left) as f32 / ppp;
            let rel_y = (cy - wr.top) as f32 / ppp;
            Some(Pos2::new(rel_x, rel_y))
        } else {
            ctx.input(|i| i.pointer.latest_pos())
        };

        let hovering = cursor.map(|p| island_rect.expand(6.0).contains(p)).unwrap_or(false);

        // Handle hover timing.
        if hovering != self.hovering {
            self.hovering = hovering;
            if hovering {
                self.hover_timer = 0.0;
                self.collapse_timer = 0.0;
                if self.state.settings.read().expand_on_hover
                    && self.island_state != IslandState::Expanded
                {
                    self.hover_timer = 0.15; // expand after 150 ms
                }
            } else if self.island_state == IslandState::Expanded {
                self.collapse_timer = 0.35;
            }
        }

        if self.hover_timer > 0.0 {
            self.hover_timer -= dt;
            if self.hover_timer <= 0.0 {
                let has_alert = self.state.reminders.read().current.is_some()
                    || self.state.event_reminders.read().active_alert.is_some();
                if !has_alert && self.state.now_playing.read().current.is_some() {
                    self.tab = IslandTab::Music;
                }
                self.expand();
            }
        }
        if self.collapse_timer > 0.0 {
            // Keep timer alive while mouse button is held (e.g. scrubbing or dragging)
            if ctx.input(|i| i.pointer.any_down()) {
                self.collapse_timer = 0.35;
            } else {
                self.collapse_timer -= dt;
                if self.collapse_timer <= 0.0 && !self.hovering {
                    self.collapse();
                }
            }
        }

        // Mouse passthrough: pass through clicks outside the island unless settings is open
        let interactive = self.settings_open
            || hovering
            || (self.island_state == IslandState::Expanded && self.collapse_timer > 0.0);

        let should_passthrough = !interactive;
        if should_passthrough != self.mouse_passthrough {
            self.mouse_passthrough = should_passthrough;
            ctx.send_viewport_cmd(egui::ViewportCommand::MousePassthrough(should_passthrough));
        }

        // Adaptive repaint: render at 60 FPS only while resizing/animating.
        // During music playback or settings interaction, render at 30 FPS.
        // When completely idle in pill mode, drop to 150ms to minimize GPU/CPU usage.
        let is_animating = (self.target_w - self.current_w).abs() > 0.5
            || (self.target_h - self.current_h).abs() > 0.5
            || self.hover_timer > 0.0
            || self.collapse_timer > 0.0;

        let is_playing = self
            .state
            .now_playing
            .read()
            .current
            .as_ref()
            .map(|c| c.is_playing)
            .unwrap_or(false);

        let delay_ms = if is_animating {
            16
        } else if self.settings_open {
            33
        } else if is_playing && self.island_state != IslandState::Pill {
            33
        } else if hovering {
            33
        } else {
            150
        };

        ctx.request_repaint_after(std::time::Duration::from_millis(delay_ms));

        // Check for reminder auto-expand.
        {
            let evrem = self.state.event_reminders.read();
            let rem = self.state.reminders.read();
            if evrem.active_alert.is_some() || rem.current.is_some() {
                if self.island_state != IslandState::Expanded {
                    drop(evrem);
                    drop(rem);
                    self.expand();
                    self.tab = IslandTab::Reminder;
                }
            }
        }

        // Drop file handling.
        ctx.input(|i| {
            if !i.raw.dropped_files.is_empty() {
                let paths: Vec<_> = i
                    .raw
                    .dropped_files
                    .iter()
                    .filter_map(|f| f.path.clone())
                    .collect();
                for p in paths {
                    self.state.shelf.write().add_file(&p);
                }
                self.tab = IslandTab::Shelf;
                self.expand();
            }
            if !i.raw.hovered_files.is_empty() {
                self.tab = IslandTab::Shelf;
                self.expand();
            }
        });

        // Load / update artwork texture.
        let art_tex = self.get_artwork_texture(ctx);

        // Draw the island.
        egui::Area::new(egui::Id::new("island"))
            .fixed_pos(island_rect.min)
            .order(egui::Order::Foreground)
            .interactable(true)
            .show(ctx, |ui| {
                ui.set_clip_rect(island_rect);
                self.draw_island(ui, island_rect, ctx, art_tex.as_ref());
            });

        // Settings window.
        if self.settings_open {
            self.settings_open = settings_win::show(ctx, &self.state);
        }

        // Shelf message tick.
        self.state.shelf.write().tick_message();
    }
}

impl IslanderApp {
    fn draw_island(
        &mut self,
        ui: &mut egui::Ui,
        rect: Rect,
        ctx: &egui::Context,
        art_tex: Option<&egui::TextureHandle>,
    ) {
        let painter = ui.painter();

        // Black notch shape.
        let rounding = if self.island_state == IslandState::Expanded {
            Rounding {
                nw: 12.0,
                ne: 12.0,
                sw: 28.0,
                se: 28.0,
            }
        } else {
            Rounding {
                nw: 6.0,
                ne: 6.0,
                sw: 12.0,
                se: 12.0,
            }
        };
        painter.rect_filled(rect, rounding, Color32::BLACK);

        let expanded = self.island_state == IslandState::Expanded;
        let compact = self.island_state == IslandState::Compact;

        // Background interaction: registered BEFORE children so tabs & child widgets have priority
        let bg_resp = ui.interact(rect, egui::Id::new("island_bg"), egui::Sense::click());
        bg_resp.context_menu(|ui| {
            if ui.button("Settings…").clicked() {
                self.settings_open = true;
                ui.close_menu();
            }
            ui.separator();
            if ui.button("Quit Islander").clicked() {
                std::process::exit(0);
            }
        });

        // Left-click on pill or compact expands the island.
        if bg_resp.clicked() && !expanded {
            let has_alert = self.state.reminders.read().current.is_some()
                || self.state.event_reminders.read().active_alert.is_some();
            if !has_alert && self.state.now_playing.read().current.is_some() {
                self.tab = IslandTab::Music;
            }
            self.expand();
        }

        // Draw children on top of background
        let inner = rect.shrink2(Vec2::new(0.0, 0.0));
        if expanded {
            self.draw_expanded(ui, inner, ctx, art_tex);
        } else if compact {
            self.draw_compact(ui, inner, art_tex);
        }
    }

    fn draw_compact(
        &mut self,
        ui: &mut egui::Ui,
        rect: Rect,
        art_tex: Option<&egui::TextureHandle>,
    ) {
        let np = self.state.now_playing.read();
        let rem = self.state.reminders.read();
        let evrem = self.state.event_reminders.read();
        let settings = self.state.settings.read();
        let is_playing = np.current.as_ref().map(|c| c.is_playing).unwrap_or(false);
        let has_alert = rem.current.is_some() || evrem.active_alert.is_some();

        // Left side: artwork or alert icon (compact & neat)
        let left_rect = Rect::from_center_size(
            Pos2::new(rect.min.x + 22.0, rect.center().y),
            Vec2::splat(22.0),
        );
        // Right side: mascot or visualizer
        let right_rect = Rect::from_center_size(
            Pos2::new(rect.max.x - 22.0, rect.center().y),
            Vec2::new(26.0, 24.0),
        );

        // Left content.
        if evrem.active_alert.is_some() {
            ui.painter().text(
                left_rect.center(),
                egui::Align2::CENTER_CENTER,
                "🔔",
                egui::FontId::proportional(14.0),
                Color32::from_rgb(255, 165, 0),
            );
        } else if rem.current.is_some() {
            ui.painter().text(
                left_rect.center(),
                egui::Align2::CENTER_CENTER,
                "⏰",
                egui::FontId::proportional(14.0),
                Color32::from_rgb(0, 220, 220),
            );
        } else if let Some(art) = art_tex {
            let art_rect = egui::Rect::from_center_size(left_rect.center(), Vec2::splat(22.0));
            ui.painter().image(
                art.id(),
                art_rect,
                egui::Rect::from_min_max(Pos2::ZERO, Pos2::new(1.0, 1.0)),
                Color32::WHITE,
            );
        }

        // Right content: mascot.
        if settings.show_mascot {
            let mood = if has_alert {
                mascot::MascotMood::Shock
            } else if is_playing {
                mascot::MascotMood::Dancing
            } else {
                mascot::MascotMood::Idle
            };
            let level = self.state.spectrum.read().level;
            mascot::draw_mascot(
                ui.painter(),
                right_rect.center(),
                24.0,
                mood,
                settings.mascot_color.rgb(),
                level as f64,
            );
        } else if settings.show_visualizer && is_playing {
            spectrum_bars::draw_bars(
                ui.painter(),
                right_rect,
                4,
                np.current
                    .as_ref()
                    .map(|c| c.accent_color)
                    .unwrap_or(Color32::WHITE),
                &self.state.spectrum.read().bands,
            );
        }

        // Center content: compact lyrics or track title (large & bold)
        if settings.show_compact_lyrics && !has_alert {
            if let Some(track) = &np.current {
                let center_rect = Rect::from_min_max(
                    Pos2::new(left_rect.max.x + 8.0, rect.min.y),
                    Pos2::new(right_rect.min.x - 8.0, rect.bottom()),
                );

                let mut lyric_found = false;
                if let Ok(lyrics) = self.state.lyrics.try_lock() {
                    match &lyrics.state {
                        crate::lyrics::LyricsState::Synced(lines) => {
                            let pos = track.position_now() + 0.25;
                            if let Some(idx) = crate::lyrics::LyricsService::line_index(lines, pos) {
                                let line = lines[idx].text.trim();
                                if !line.is_empty() {
                                    let truncated = truncate_str(line, 34);
                                    draw_centered_bold_text(
                                        ui,
                                        center_rect,
                                        &truncated,
                                        15.5,
                                        Color32::WHITE,
                                    );
                                    lyric_found = true;
                                }
                            }
                        }
                        crate::lyrics::LyricsState::Loading => {
                            draw_centered_bold_text(
                                ui,
                                center_rect,
                                "Looking for lyrics…",
                                13.0,
                                Color32::from_white_alpha(150),
                            );
                            lyric_found = true;
                        }
                        crate::lyrics::LyricsState::Instrumental => {
                            draw_centered_bold_text(
                                ui,
                                center_rect,
                                "Instrumental ♪",
                                14.5,
                                Color32::from_white_alpha(220),
                            );
                            lyric_found = true;
                        }
                        _ => {}
                    }
                }

                if !lyric_found {
                    let title_text = if !track.artist.is_empty() {
                        format!("{} • {}", track.title, track.artist)
                    } else {
                        track.title.clone()
                    };
                    if !title_text.is_empty() {
                        let truncated = truncate_str(&title_text, 32);
                        draw_centered_bold_text(
                            ui,
                            center_rect,
                            &truncated,
                            14.5,
                            Color32::from_white_alpha(230),
                        );
                    }
                }
            }
        }
    }

    fn draw_expanded(
        &mut self,
        ui: &mut egui::Ui,
        rect: Rect,
        ctx: &egui::Context,
        art_tex: Option<&egui::TextureHandle>,
    ) {
        // Header: tab bar.
        let header_rect = Rect::from_min_size(rect.min, Vec2::new(rect.width(), PILL_HEIGHT));
        let content_rect = Rect::from_min_size(
            rect.min + Vec2::new(0.0, PILL_HEIGHT),
            Vec2::new(rect.width(), rect.height() - PILL_HEIGHT),
        );

        self.draw_tab_bar(ui, header_rect);
        self.draw_tab_content(ui, content_rect, ctx, art_tex);
    }

    fn draw_tab_bar(&mut self, ui: &mut egui::Ui, rect: Rect) {
        let tabs = [
            (IslandTab::Music, "♪"),
            (IslandTab::Reminder, "🔔"),
            (IslandTab::Focus, "⏱"),
            (IslandTab::Shelf, "📥"),
        ];
        let tab_w = 32.0;
        let tab_h = 24.0;
        let start_x = rect.left() + 28.0;
        let cy = rect.center().y;

        let evrem = self.state.event_reminders.read();
        let shelf = self.state.shelf.read();
        let pending_reminders = evrem.reminders.iter().filter(|r| !r.is_completed).count();
        let shelf_count = shelf.items.len();
        drop(evrem);
        drop(shelf);

        for (i, (tab, icon)) in tabs.iter().enumerate() {
            let x = start_x + i as f32 * (tab_w + 6.0);
            let tab_rect =
                Rect::from_center_size(Pos2::new(x + tab_w / 2.0, cy), Vec2::new(tab_w, tab_h));
            let active = *tab == self.tab;

            let resp = ui.interact(
                tab_rect.expand2(Vec2::new(4.0, 4.0)),
                egui::Id::new(format!("tab_{i}")),
                egui::Sense::click(),
            );

            if resp.hovered() {
                ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
            }

            if active {
                ui.painter().rect_filled(
                    tab_rect,
                    Rounding::same(12.0),
                    Color32::from_white_alpha(45),
                );
            } else if resp.hovered() {
                ui.painter().rect_filled(
                    tab_rect,
                    Rounding::same(12.0),
                    Color32::from_white_alpha(20),
                );
            }

            let col = if active {
                Color32::WHITE
            } else if resp.hovered() {
                Color32::from_white_alpha(210)
            } else {
                Color32::from_white_alpha(140)
            };

            ui.painter().text(
                tab_rect.center(),
                egui::Align2::CENTER_CENTER,
                *icon,
                egui::FontId::proportional(13.0),
                col,
            );

            // Badges.
            if *tab == IslandTab::Shelf && shelf_count > 0 {
                draw_badge(
                    ui.painter(),
                    tab_rect.right_top() + Vec2::new(2.0, -2.0),
                    &shelf_count.to_string(),
                    Color32::from_rgb(0, 220, 220),
                );
            }
            if *tab == IslandTab::Reminder && pending_reminders > 0 {
                draw_badge(
                    ui.painter(),
                    tab_rect.right_top() + Vec2::new(2.0, -2.0),
                    &pending_reminders.to_string(),
                    Color32::from_rgb(255, 165, 0),
                );
            }

            // Click tab.
            if resp.clicked() {
                self.tab = tab.clone();
                self.state.reminders.write().dismiss_for_now();
                self.state.event_reminders.write().dismiss_alert();
            }
        }

        // Settings gear (right side).
        let gear_rect =
            Rect::from_center_size(Pos2::new(rect.right() - 28.0, cy), Vec2::new(28.0, 24.0));
        let gr = ui.interact(
            gear_rect.expand2(Vec2::new(4.0, 4.0)),
            egui::Id::new("gear"),
            egui::Sense::click(),
        );

        if gr.hovered() {
            ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
            ui.painter().rect_filled(
                gear_rect,
                Rounding::same(12.0),
                Color32::from_white_alpha(20),
            );
        }

        ui.painter().text(
            gear_rect.center(),
            egui::Align2::CENTER_CENTER,
            "⚙",
            egui::FontId::proportional(13.0),
            if gr.hovered() {
                Color32::WHITE
            } else {
                Color32::from_white_alpha(180)
            },
        );

        if gr.clicked() {
            self.settings_open = true;
        }
    }

    fn draw_tab_content(
        &mut self,
        ui: &mut egui::Ui,
        rect: Rect,
        ctx: &egui::Context,
        art_tex: Option<&egui::TextureHandle>,
    ) {
        let padded = rect.shrink2(Vec2::new(30.0, 10.0));

        // Check for active alerts — they override the current tab.
        let has_event_alert = self.state.event_reminders.read().active_alert.is_some();
        let has_focus_alert = self.state.reminders.read().current.is_some();

        if has_event_alert {
            reminder_tab::draw_event_alert(ui, padded, &self.state);
        } else if has_focus_alert {
            reminder_tab::draw_focus_alert(ui, padded, &self.state);
        } else {
            match self.tab {
                IslandTab::Music => music::draw(
                    ui,
                    padded,
                    &self.state,
                    ctx,
                    art_tex.cloned(),
                ),
                IslandTab::Reminder => reminder_tab::draw(ui, padded, &self.state),
                IslandTab::Focus => focus_tab::draw(ui, padded, &self.state),
                IslandTab::Shelf => shelf_tab::draw(ui, padded, &self.state),
            }
        }
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn centered_island_rect(screen: Rect, w: f32, h: f32) -> Rect {
    let cx = screen.center().x;
    Rect::from_min_size(Pos2::new(cx - w / 2.0, screen.top()), Vec2::new(w, h))
}

fn draw_centered_bold_text(
    ui: &egui::Ui,
    rect: Rect,
    text: &str,
    size: f32,
    color: Color32,
) {
    let font_bold = egui::FontId::new(size, egui::FontFamily::Name("bold".into()));
    let galley = ui.painter().layout_no_wrap(
        text.to_string(),
        font_bold,
        color,
    );
    let pos = rect.center() - galley.size() / 2.0;
    // Draw with slight 0.5px subpixel horizontal offset to guarantee thick, bold letterforms
    ui.painter().galley(pos + Vec2::new(0.5, 0.0), galley.clone(), color);
    ui.painter().galley(pos, galley, color);
}

fn draw_badge(painter: &egui::Painter, pos: Pos2, text: &str, color: Color32) {
    let r = 6.0;
    painter.circle_filled(pos, r, color);
    painter.text(
        pos,
        egui::Align2::CENTER_CENTER,
        text,
        egui::FontId::proportional(7.0),
        Color32::BLACK,
    );
}

fn truncate_str(s: &str, max_chars: usize) -> String {
    let count = s.chars().count();
    if count <= max_chars {
        s.to_string()
    } else {
        let mut out: String = s.chars().take(max_chars).collect();
        out.push('…');
        out
    }
}
