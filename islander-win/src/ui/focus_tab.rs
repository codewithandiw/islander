// ui/focus_tab.rs — Focus tab: active time today, 7-day chart, break reminders

use crate::settings::ReminderKind;
use crate::AppState;
use eframe::egui::{self, Color32, Pos2, Rect, Rounding, Sense, Vec2};

pub fn draw(ui: &mut egui::Ui, rect: Rect, state: &AppState) {
    let activity = state.activity.read();
    let reminders = state.reminders.read();
    let settings = state.settings.read();

    // Header: today's active time + daily goal bar.
    let today_secs = activity.today_active_secs;
    let goal_secs = settings.daily_goal_hours as f64 * 3600.0;
    let progress = (today_secs / goal_secs).min(1.0) as f32;

    let header = format!(
        "{} / {}h today",
        format_duration(today_secs),
        settings.daily_goal_hours
    );
    ui.painter().text(
        rect.min,
        egui::Align2::LEFT_TOP,
        &header,
        egui::FontId::new(14.0, egui::FontFamily::Proportional),
        Color32::WHITE,
    );

    // Progress bar.
    let bar = Rect::from_min_size(
        rect.min + Vec2::new(0.0, 20.0),
        Vec2::new(rect.width(), 6.0),
    );
    ui.painter()
        .rect_filled(bar, Rounding::same(3.0), Color32::from_white_alpha(40));
    if progress > 0.0 {
        let filled = Rect::from_min_size(bar.min, Vec2::new(bar.width() * progress, 6.0));
        ui.painter()
            .rect_filled(filled, Rounding::same(3.0), Color32::from_rgb(0, 220, 150));
    }

    // 7-day history bars.
    let hist = activity.history(7);
    let hist_rect = Rect::from_min_size(
        rect.min + Vec2::new(0.0, 36.0),
        Vec2::new(rect.width(), 50.0),
    );
    draw_history(ui.painter(), hist_rect, &hist, goal_secs);

    // Reminder timers.
    let timer_top = rect.min.y + 96.0;
    for (i, kind) in ReminderKind::all().iter().enumerate() {
        let y = timer_top + i as f32 * 22.0;
        let Some(remaining) = reminders.remaining_secs(kind) else {
            continue;
        };
        let config = settings.reminder_config(kind);
        let total = config.minutes as f64 * 60.0;
        let frac = 1.0 - (remaining / total).min(1.0) as f32;

        // Icon + label.
        ui.painter().text(
            Pos2::new(rect.left(), y),
            egui::Align2::LEFT_CENTER,
            kind.icon(),
            egui::FontId::proportional(12.0),
            Color32::WHITE,
        );
        ui.painter().text(
            Pos2::new(rect.left() + 20.0, y),
            egui::Align2::LEFT_CENTER,
            kind.title(),
            egui::FontId::proportional(11.0),
            Color32::from_white_alpha(200),
        );

        // Countdown.
        let rem_str = format_duration(remaining);
        ui.painter().text(
            Pos2::new(rect.right(), y),
            egui::Align2::RIGHT_CENTER,
            &rem_str,
            egui::FontId::monospace(10.0),
            Color32::from_white_alpha(150),
        );

        // Mini bar.
        let mini = Rect::from_min_size(
            Pos2::new(rect.left() + 110.0, y - 3.0),
            Vec2::new(rect.right() - rect.left() - 150.0, 5.0),
        );
        ui.painter()
            .rect_filled(mini, Rounding::same(2.5), Color32::from_white_alpha(30));
        if frac > 0.0 {
            let f = Rect::from_min_size(mini.min, Vec2::new(mini.width() * frac, 5.0));
            let col = if frac > 0.9 {
                Color32::from_rgb(0, 220, 220)
            } else {
                Color32::from_white_alpha(100)
            };
            ui.painter().rect_filled(f, Rounding::same(2.5), col);
        }
    }

    // "I took a break" button.
    let btn_rect = Rect::from_min_size(
        Pos2::new(rect.left(), rect.bottom() - 22.0),
        Vec2::new(130.0, 20.0),
    );
    let resp = ui.interact(btn_rect, egui::Id::new("break_btn"), Sense::click());
    if resp.hovered() {
        ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
    }
    ui.painter().rect_filled(
        btn_rect,
        Rounding::same(10.0),
        if resp.hovered() { Color32::from_white_alpha(55) } else { Color32::from_white_alpha(35) },
    );
    ui.painter().text(
        btn_rect.center(),
        egui::Align2::CENTER_CENTER,
        "I took a break",
        egui::FontId::proportional(11.0),
        Color32::WHITE,
    );
    if resp.clicked() {
        drop(activity);
        drop(reminders);
        drop(settings);
        state.activity.write().take_break_now();
        state.reminders.write().reset_all();
    }
}

fn draw_history(painter: &egui::Painter, rect: Rect, history: &[(String, f64)], goal_secs: f64) {
    let n = history.len();
    if n == 0 {
        return;
    }
    let bar_w = (rect.width() / n as f32 - 3.0).max(4.0);
    let gap = (rect.width() - bar_w * n as f32) / (n + 1) as f32;
    let max_h = rect.height() - 12.0;

    for (i, (_date, secs)) in history.iter().enumerate() {
        let frac = (*secs / goal_secs.max(1.0)).min(1.0) as f32;
        let bh = (frac * max_h).max(2.0);
        let x = rect.left() + gap + i as f32 * (bar_w + gap);
        let bar = Rect::from_min_max(
            Pos2::new(x, rect.bottom() - 12.0 - bh),
            Pos2::new(x + bar_w, rect.bottom() - 12.0),
        );
        let col = if i == n - 1 {
            Color32::from_rgb(0, 220, 150)
        } else {
            Color32::from_white_alpha(60)
        };
        painter.rect_filled(bar, Rounding::same(bar_w / 2.0), col);

        // Day label.
        let day = _date.split('-').nth(2).unwrap_or("?");
        painter.text(
            Pos2::new(x + bar_w / 2.0, rect.bottom()),
            egui::Align2::CENTER_BOTTOM,
            day,
            egui::FontId::proportional(8.0),
            Color32::from_white_alpha(100),
        );
    }
}

fn format_duration(secs: f64) -> String {
    let total = secs as u64;
    let h = total / 3600;
    let m = (total % 3600) / 60;
    let s = total % 60;
    if h > 0 {
        format!("{}h {:02}m", h, m)
    } else {
        format!("{}m {:02}s", m, s)
    }
}
