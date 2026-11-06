// ui/settings_win.rs — Modern Tabbed Settings window with compact layout and exit button

use crate::settings::{FocusReminderSound, MascotColor, ReminderKind};
use crate::AppState;
use eframe::egui::{self, Color32, Rounding, Stroke, Vec2};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SettingsTab {
    Music,
    Mascot,
    Focus,
    Reminders,
}

impl SettingsTab {
    fn label(&self) -> &'static str {
        match self {
            SettingsTab::Music => "Music",
            SettingsTab::Mascot => "Mascot",
            SettingsTab::Focus => "Focus",
            SettingsTab::Reminders => "Reminders",
        }
    }

    fn all() -> &'static [SettingsTab] {
        &[
            SettingsTab::Music,
            SettingsTab::Mascot,
            SettingsTab::Focus,
            SettingsTab::Reminders,
        ]
    }
}

/// Returns false when the window should close.
pub fn show(ctx: &egui::Context, state: &AppState) -> bool {
    let mut close_requested = false;

    let window_frame = egui::Frame {
        fill: Color32::from_rgb(18, 18, 22),
        stroke: Stroke::new(1.0_f32, Color32::from_white_alpha(35)),
        rounding: Rounding::same(14.0),
        inner_margin: egui::Margin::symmetric(16.0, 14.0),
        shadow: egui::epaint::Shadow {
            offset: Vec2::new(0.0, 8.0),
            blur: 24.0,
            spread: 2.0,
            color: Color32::from_black_alpha(180),
        },
        ..Default::default()
    };

    let mut current_tab = ctx
        .data(|d| d.get_temp::<SettingsTab>(egui::Id::new("settings_tab")))
        .unwrap_or(SettingsTab::Music);

    egui::Window::new("Islander Settings")
        .collapsible(false)
        .title_bar(false)
        .resizable(false)
        .anchor(egui::Align2::CENTER_TOP, [0.0, 36.0])
        .default_width(430.0)
        .max_width(430.0)
        .frame(window_frame)
        .show(ctx, |ui| {
            ui.set_width(398.0);

            let saved_recently = ctx
                .data(|d| d.get_temp::<std::time::Instant>(egui::Id::new("settings_saved_at")))
                .map(|t| t.elapsed().as_secs_f32() < 2.5)
                .unwrap_or(false);

            // Modern Header with Close button
            ui.horizontal(|ui| {
                ui.vertical(|ui| {
                    ui.label(
                        egui::RichText::new("Settings")
                            .size(16.0)
                            .strong()
                            .color(Color32::WHITE),
                    );
                    ui.label(
                        egui::RichText::new("Personalize your Islander overlay")
                            .size(11.0)
                            .color(Color32::from_white_alpha(130)),
                    );
                });

                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    // Close button: standard Latin-1 multiplication sign '×' (U+00D7)
                    let close_btn = ui.add(
                        egui::Button::new(
                            egui::RichText::new("×")
                                .size(18.0)
                                .color(Color32::from_white_alpha(180)),
                        )
                        .fill(Color32::TRANSPARENT)
                        .frame(false)
                        .min_size(Vec2::splat(24.0)),
                    );
                    if close_btn.hovered() {
                        ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
                    }
                    if close_btn.clicked() {
                        close_requested = true;
                    }
                });
            });

            ui.add_space(8.0);

            // ── Section Tabs ───────────────────────────────────────────────────
            ui.horizontal(|ui| {
                for tab in SettingsTab::all() {
                    let is_selected = *tab == current_tab;
                    let tab_btn = ui.add(
                        egui::Button::new(
                            egui::RichText::new(tab.label())
                                .size(11.5)
                                .strong()
                                .color(if is_selected {
                                    Color32::WHITE
                                } else {
                                    Color32::from_white_alpha(150)
                                }),
                        )
                        .fill(if is_selected {
                            Color32::from_rgba_premultiplied(40, 90, 180, 220)
                        } else {
                            Color32::from_white_alpha(10)
                        })
                        .stroke(if is_selected {
                            Stroke::new(1.0_f32, Color32::from_rgb(65, 135, 245))
                        } else {
                            Stroke::new(1.0_f32, Color32::from_white_alpha(16))
                        })
                        .rounding(Rounding::same(6.0))
                        .min_size(Vec2::new(88.0, 24.0)),
                    );
                    if tab_btn.hovered() {
                        ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
                    }
                    if tab_btn.clicked() {
                        current_tab = *tab;
                        ctx.data_mut(|d| d.insert_temp(egui::Id::new("settings_tab"), current_tab));
                    }
                }
            });

            ui.add_space(8.0);

            // ── Tab Content Card (Compact, never too long) ─────────────────────
            egui::ScrollArea::vertical()
                .auto_shrink([false; 2])
                .max_height(190.0)
                .show(ui, |ui| {
                    let mut settings = state.settings.write();
                    match current_tab {
                        SettingsTab::Music => draw_music_tab(ui, &mut settings),
                        SettingsTab::Mascot => draw_mascot_tab(ui, &mut settings),
                        SettingsTab::Focus => draw_focus_tab(ui, &mut settings),
                        SettingsTab::Reminders => draw_reminders_tab(ui, &mut settings),
                    }
                });

            ui.add_space(8.0);
            ui.painter().hline(
                ui.available_rect_before_wrap().x_range(),
                ui.cursor().top(),
                Stroke::new(1.0_f32, Color32::from_white_alpha(20)),
            );
            ui.add_space(8.0);

            // ── Pinned Bottom Action Bar ───────────────────────────────────────
            ui.horizontal(|ui| {
                // Exit Islander Button (Red Accent)
                let exit_btn = ui.add(
                    egui::Button::new(
                        egui::RichText::new("Exit Islander")
                            .size(11.5)
                            .strong()
                            .color(Color32::from_rgb(255, 130, 130)),
                    )
                    .fill(Color32::from_rgba_premultiplied(65, 18, 18, 200))
                    .stroke(Stroke::new(1.0_f32, Color32::from_rgb(175, 50, 50)))
                    .rounding(Rounding::same(7.0))
                    .min_size(Vec2::new(105.0, 28.0)),
                );
                if exit_btn.hovered() {
                    ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
                }
                if exit_btn.clicked() {
                    std::process::exit(0);
                }

                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    // Save Changes Button (Blue Accent)
                    let save_btn = ui.add(
                        egui::Button::new(
                            egui::RichText::new("Save Changes")
                                .size(11.5)
                                .strong()
                                .color(Color32::WHITE),
                        )
                        .fill(Color32::from_rgba_premultiplied(35, 95, 195, 220))
                        .stroke(Stroke::new(1.0_f32, Color32::from_rgb(65, 135, 245)))
                        .rounding(Rounding::same(7.0))
                        .min_size(Vec2::new(115.0, 28.0)),
                    );
                    if save_btn.hovered() {
                        ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
                    }
                    if save_btn.clicked() {
                        state.settings.write().save();
                        ctx.data_mut(|d| {
                            d.insert_temp(
                                egui::Id::new("settings_saved_at"),
                                std::time::Instant::now(),
                            )
                        });
                    }

                    if saved_recently {
                        ui.label(
                            egui::RichText::new("✓ Saved!")
                                .size(11.5)
                                .color(Color32::from_rgb(80, 220, 120)),
                        );
                    }
                });
            });
        });

    !close_requested
}

// ── Tab 1: Music & Island ──────────────────────────────────────────────────────

fn draw_music_tab(ui: &mut egui::Ui, settings: &mut crate::settings::AppSettings) {
    settings_card(ui, "LYRICS & AUDIO", |ui| {
        toggle_row(
            ui,
            &mut settings.show_compact_lyrics,
            "Compact lyrics bar",
            "Show live synced lyrics inside the compact top notch",
        );
        ui.add_space(4.0);
        toggle_row(
            ui,
            &mut settings.show_lyrics,
            "Expanded lyrics",
            "Display 2-line synced lyrics when island is opened",
        );
        ui.add_space(4.0);
        toggle_row(
            ui,
            &mut settings.show_visualizer,
            "Audio visualizer",
            "Show real-time audio frequency bars during playback",
        );
        ui.add_space(4.0);
        toggle_row(
            ui,
            &mut settings.expand_on_hover,
            "Expand on hover",
            "Automatically open island when hovering cursor over it",
        );
    });
}

// ── Tab 2: Mascot Companion ────────────────────────────────────────────────────

fn draw_mascot_tab(ui: &mut egui::Ui, settings: &mut crate::settings::AppSettings) {
    settings_card(ui, "MASCOT COMPANION", |ui| {
        toggle_row(
            ui,
            &mut settings.show_mascot,
            "Show mascot",
            "Display cute animated buddy responding to music & focus",
        );

        if settings.show_mascot {
            ui.add_space(8.0);
            ui.horizontal(|ui| {
                ui.label(
                    egui::RichText::new("Mascot Color:")
                        .size(12.0)
                        .color(Color32::from_white_alpha(180)),
                );
                ui.add_space(6.0);

                let current_color = settings.mascot_color.clone();
                for mc in MascotColor::all() {
                    let is_selected = *mc == current_color;
                    let rgb = mc.rgb();
                    let color = Color32::from_rgb(
                        (rgb[0] * 255.0) as u8,
                        (rgb[1] * 255.0) as u8,
                        (rgb[2] * 255.0) as u8,
                    );

                    let (rect, resp) = ui.allocate_exact_size(Vec2::splat(22.0), egui::Sense::click());
                    if resp.hovered() {
                        ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
                    }
                    if resp.clicked() {
                        settings.mascot_color = mc.clone();
                    }

                    if is_selected {
                        ui.painter().circle_stroke(
                            rect.center(),
                            10.0,
                            Stroke::new(2.0_f32, Color32::WHITE),
                        );
                    }
                    ui.painter().circle_filled(rect.center(), if is_selected { 7.0 } else { 8.5 }, color);
                }

                ui.add_space(6.0);
                ui.label(
                    egui::RichText::new(settings.mascot_color.name())
                        .size(11.5)
                        .color(settings.mascot_color.egui_color()),
                );
            });
        }
    });
}

// ── Tab 3: Focus & Activity ────────────────────────────────────────────────────

fn draw_focus_tab(ui: &mut egui::Ui, settings: &mut crate::settings::AppSettings) {
    settings_card(ui, "FOCUS & ACTIVITY", |ui| {
        stepper_row(
            ui,
            "Idle threshold",
            "Minutes of inactivity before pausing work tracking",
            &mut settings.idle_threshold_minutes,
            1,
            60,
            "min",
        );
        ui.add_space(6.0);
        stepper_row(
            ui,
            "Break reset",
            "Minutes away from computer that resets focus session",
            &mut settings.break_reset_minutes,
            1,
            120,
            "min",
        );
        ui.add_space(6.0);
        stepper_row(
            ui,
            "Daily goal",
            "Target active focused work hours per day",
            &mut settings.daily_goal_hours,
            1,
            24,
            "hrs",
        );
    });
}

// ── Tab 4: Health Reminders ────────────────────────────────────────────────────

fn draw_reminders_tab(ui: &mut egui::Ui, settings: &mut crate::settings::AppSettings) {
    settings_card(ui, "HEALTH REMINDERS", |ui| {
        for kind in ReminderKind::all() {
            let key = match kind {
                ReminderKind::WorkBreak => "workBreak",
                ReminderKind::Stretch => "stretch",
                ReminderKind::Drink => "drink",
            };
            let config = settings.reminders.entry(key.into()).or_default();
            ui.horizontal(|ui| {
                ui.checkbox(&mut config.enabled, "");
                ui.label(
                    egui::RichText::new(kind.title())
                        .size(12.5)
                        .color(Color32::WHITE),
                );

                if config.enabled {
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        stepper_u32(ui, &mut config.minutes, 5, 480, "min");
                        ui.label(
                            egui::RichText::new("Every")
                                .size(11.5)
                                .color(Color32::from_white_alpha(140)),
                        );
                    });
                }
            });
            ui.add_space(4.0);
        }

        ui.add_space(6.0);
        toggle_row(
            ui,
            &mut settings.play_reminder_sound,
            "Play sound alert",
            "Trigger audible chime when reminder arrives",
        );

        if settings.play_reminder_sound {
            ui.add_space(6.0);
            ui.horizontal(|ui| {
                ui.label(
                    egui::RichText::new("Sound:")
                        .size(12.0)
                        .color(Color32::from_white_alpha(180)),
                );
                ui.add_space(4.0);

                let current_name = settings.focus_reminder_sound.display_name().to_string();
                egui::ComboBox::new("reminder_sound_sel", "")
                    .selected_text(current_name)
                    .show_ui(ui, |ui| {
                        for snd in FocusReminderSound::all() {
                            let sel = ui.selectable_value(
                                &mut settings.focus_reminder_sound,
                                snd.clone(),
                                snd.display_name(),
                            );
                            if sel.clicked() {
                                snd.play();
                            }
                        }
                    });

                ui.add_space(6.0);
                let test_btn = ui.add(
                    egui::Button::new(egui::RichText::new("▶ Test").size(11.0))
                        .rounding(Rounding::same(6.0))
                        .min_size(Vec2::new(48.0, 22.0)),
                );
                if test_btn.hovered() {
                    ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
                }
                if test_btn.clicked() {
                    settings.focus_reminder_sound.play();
                }
            });
        }
    });
}

// ── UI Helpers ─────────────────────────────────────────────────────────────────

fn settings_card<R>(
    ui: &mut egui::Ui,
    title: &str,
    add_contents: impl FnOnce(&mut egui::Ui) -> R,
) {
    let card_frame = egui::Frame {
        fill: Color32::from_white_alpha(8),
        stroke: Stroke::new(1.0_f32, Color32::from_white_alpha(18)),
        rounding: Rounding::same(10.0),
        inner_margin: egui::Margin::symmetric(13.0, 11.0),
        ..Default::default()
    };
    card_frame.show(ui, |ui| {
        ui.label(
            egui::RichText::new(title)
                .size(10.5)
                .strong()
                .color(Color32::from_white_alpha(150)),
        );
        ui.add_space(5.0);
        add_contents(ui);
    });
}

fn toggle_row(ui: &mut egui::Ui, value: &mut bool, label: &str, subtitle: &str) {
    ui.horizontal(|ui| {
        ui.vertical(|ui| {
            ui.label(egui::RichText::new(label).size(12.5).color(Color32::WHITE));
            if !subtitle.is_empty() {
                ui.label(
                    egui::RichText::new(subtitle)
                        .size(10.5)
                        .color(Color32::from_white_alpha(120)),
                );
            }
        });
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.checkbox(value, "");
        });
    });
}

fn stepper_row(
    ui: &mut egui::Ui,
    label: &str,
    subtitle: &str,
    value: &mut u32,
    min: u32,
    max: u32,
    suffix: &str,
) {
    ui.horizontal(|ui| {
        ui.vertical(|ui| {
            ui.label(egui::RichText::new(label).size(12.5).color(Color32::WHITE));
            if !subtitle.is_empty() {
                ui.label(
                    egui::RichText::new(subtitle)
                        .size(10.5)
                        .color(Color32::from_white_alpha(120)),
                );
            }
        });
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            stepper_u32(ui, value, min, max, suffix);
        });
    });
}

fn stepper_u32(ui: &mut egui::Ui, value: &mut u32, min: u32, max: u32, suffix: &str) {
    ui.horizontal(|ui| {
        let plus = ui.add(
            egui::Button::new("+")
                .rounding(Rounding::same(4.0))
                .min_size(Vec2::new(22.0, 20.0)),
        );
        if plus.clicked() && *value < max {
            *value = value.saturating_add(1).min(max);
        }

        ui.label(
            egui::RichText::new(format!("{} {}", *value, suffix))
                .size(11.5)
                .strong()
                .color(Color32::WHITE),
        );

        let minus = ui.add(
            egui::Button::new("-")
                .rounding(Rounding::same(4.0))
                .min_size(Vec2::new(22.0, 20.0)),
        );
        if minus.clicked() && *value > min {
            *value = value.saturating_sub(1).max(min);
        }
    });
}
