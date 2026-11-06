// ui/reminder_tab.rs — Reminder tab: event reminders CRUD + alert cards

use crate::reminder::EventReminder;
use crate::AppState;
use chrono::Local;
use eframe::egui::{self, Color32, Pos2, Rect, Rounding, Sense, Vec2};
use uuid::Uuid;

pub fn draw(ui: &mut egui::Ui, rect: Rect, state: &AppState) {
    let evrem = state.event_reminders.read();
    let reminders: Vec<_> = evrem.reminders.clone();
    drop(evrem);

    ui.painter().text(
        rect.min,
        egui::Align2::LEFT_TOP,
        "Reminders",
        egui::FontId::new(14.0, egui::FontFamily::Proportional),
        Color32::WHITE,
    );

    let list_rect = Rect::from_min_size(
        rect.min + Vec2::new(0.0, 24.0),
        Vec2::new(rect.width(), rect.height() - 50.0),
    );

    // List of reminders.
    let mut delete_id: Option<Uuid> = None;
    let mut toggle_id: Option<Uuid> = None;

    for (i, rem) in reminders.iter().enumerate() {
        let y = list_rect.min.y + i as f32 * 32.0;
        if y > list_rect.max.y {
            break;
        }
        let row = Rect::from_min_size(
            Pos2::new(list_rect.left(), y),
            Vec2::new(list_rect.width(), 28.0),
        );

        let col = if rem.is_completed {
            Color32::from_white_alpha(80)
        } else {
            Color32::WHITE
        };

        // Checkbox.
        let check = Rect::from_center_size(
            Pos2::new(row.left() + 10.0, row.center().y),
            Vec2::splat(14.0),
        );
        let cr = ui.interact(
            check.expand2(Vec2::splat(4.0)),
            egui::Id::new(format!("chk_{}", rem.id)),
            Sense::click(),
        );
        if cr.hovered() {
            ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
        }
        if cr.clicked() {
            toggle_id = Some(rem.id);
        }

        ui.painter().rect_stroke(
            check,
            Rounding::same(3.0),
            (1.0, if cr.hovered() { Color32::WHITE } else { Color32::from_white_alpha(150) }),
        );
        if rem.is_completed {
            ui.painter().text(
                check.center(),
                egui::Align2::CENTER_CENTER,
                "✓",
                egui::FontId::proportional(10.0),
                Color32::from_white_alpha(150),
            );
        }

        // Title + due date.
        ui.painter().text(
            Pos2::new(row.left() + 26.0, row.center().y - 6.0),
            egui::Align2::LEFT_CENTER,
            &rem.title,
            egui::FontId::proportional(12.0),
            col,
        );
        let due_str = rem.due_date.format("%b %d, %H:%M").to_string();
        ui.painter().text(
            Pos2::new(row.left() + 26.0, row.center().y + 6.0),
            egui::Align2::LEFT_CENTER,
            &due_str,
            egui::FontId::proportional(10.0),
            Color32::from_white_alpha(130),
        );

        // Delete button.
        let del = Rect::from_center_size(
            Pos2::new(row.right() - 12.0, row.center().y),
            Vec2::splat(14.0),
        );
        let dr = ui.interact(
            del.expand2(Vec2::splat(4.0)),
            egui::Id::new(format!("del_{}", rem.id)),
            Sense::click(),
        );
        if dr.hovered() {
            ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
        }
        if dr.clicked() {
            delete_id = Some(rem.id);
        }

        ui.painter().text(
            del.center(),
            egui::Align2::CENTER_CENTER,
            "✕",
            egui::FontId::proportional(10.0),
            if dr.hovered() { Color32::WHITE } else { Color32::from_white_alpha(100) },
        );
    }

    if let Some(id) = delete_id {
        state.event_reminders.write().delete(id);
    }
    if let Some(id) = toggle_id {
        state.event_reminders.write().toggle_completed(id);
    }

    // "Add reminder" button.
    let add_rect = Rect::from_min_size(
        Pos2::new(rect.left(), rect.bottom() - 22.0),
        Vec2::new(130.0, 20.0),
    );
    let ar = ui.interact(add_rect, egui::Id::new("add_rem"), Sense::click());
    if ar.hovered() {
        ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
    }
    ui.painter().rect_filled(
        add_rect,
        Rounding::same(10.0),
        if ar.hovered() { Color32::from_white_alpha(55) } else { Color32::from_white_alpha(35) },
    );
    ui.painter().text(
        add_rect.center(),
        egui::Align2::CENTER_CENTER,
        "+ Add reminder",
        egui::FontId::proportional(11.0),
        Color32::WHITE,
    );
    if ar.clicked() {
        let new_rem = EventReminder::new("New Reminder", Local::now() + chrono::Duration::hours(1));
        state.event_reminders.write().add(new_rem);
    }
}

/// Shows when an event reminder fires: due / approaching.
pub fn draw_event_alert(ui: &mut egui::Ui, rect: Rect, state: &AppState) {
    let evrem = state.event_reminders.read();
    let Some(alert) = &evrem.active_alert else {
        return;
    };
    let alert = alert.clone();
    drop(evrem);

    let title_col = if alert.is_approaching_warning {
        Color32::from_rgb(255, 165, 0)
    } else {
        Color32::from_rgb(255, 80, 80)
    };

    let icon = if alert.is_approaching_warning {
        "🔔"
    } else {
        "⏰"
    };
    ui.painter().text(
        rect.left_center() - Vec2::new(0.0, 20.0),
        egui::Align2::LEFT_CENTER,
        icon,
        egui::FontId::proportional(28.0),
        title_col,
    );

    let label = if alert.is_approaching_warning {
        "Coming up"
    } else {
        "Due now"
    };
    ui.painter().text(
        rect.left_center() + Vec2::new(40.0, -16.0),
        egui::Align2::LEFT_CENTER,
        label,
        egui::FontId::proportional(11.0),
        title_col,
    );
    ui.painter().text(
        rect.left_center() + Vec2::new(40.0, 0.0),
        egui::Align2::LEFT_CENTER,
        &alert.reminder.title,
        egui::FontId::new(14.0, egui::FontFamily::Proportional),
        Color32::WHITE,
    );
    if !alert.reminder.notes.is_empty() {
        ui.painter().text(
            rect.left_center() + Vec2::new(40.0, 16.0),
            egui::Align2::LEFT_CENTER,
            &alert.reminder.notes,
            egui::FontId::proportional(11.0),
            Color32::from_white_alpha(150),
        );
    }

    // Buttons: Done, Snooze 5 min, Dismiss.
    let bw = 90.0;
    let by = rect.bottom() - 24.0;
    let buttons = [
        ("Done", rect.left(), Color32::from_white_alpha(220)),
        (
            "5 min",
            rect.left() + bw + 8.0,
            Color32::from_white_alpha(60),
        ),
        (
            "Dismiss",
            rect.left() + 2.0 * (bw + 8.0),
            Color32::from_white_alpha(60),
        ),
    ];
    for (label, x, fill) in buttons {
        let br = Rect::from_min_size(Pos2::new(x, by), Vec2::new(bw, 20.0));
        let r = ui.interact(br, egui::Id::new(format!("ea_{label}")), Sense::click());
        if r.hovered() {
            ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
        }
        let current_fill = if r.hovered() {
            if label == "Done" { Color32::from_white_alpha(255) } else { Color32::from_white_alpha(90) }
        } else {
            fill
        };
        ui.painter().rect_filled(br, Rounding::same(10.0), current_fill);
        ui.painter().text(
            br.center(),
            egui::Align2::CENTER_CENTER,
            label,
            egui::FontId::proportional(11.0),
            if label == "Done" {
                Color32::BLACK
            } else {
                Color32::WHITE
            },
        );
        if r.clicked() {
            match label {
                "Done" => state
                    .event_reminders
                    .write()
                    .toggle_completed(alert.reminder.id),
                "5 min" => state.event_reminders.write().snooze(alert.reminder.id, 5),
                "Dismiss" => state.event_reminders.write().dismiss_alert(),
                _ => {}
            }
        }
    }
}

/// Shows when a focus reminder fires: break / stretch / drink.
pub fn draw_focus_alert(ui: &mut egui::Ui, rect: Rect, state: &AppState) {
    let rem = state.reminders.read();
    let Some(alert) = &rem.current else {
        return;
    };
    let alert = alert.clone();
    drop(rem);

    let first_kind = alert.kinds.first().cloned();
    let icons: String = alert
        .kinds
        .iter()
        .map(|k| k.icon())
        .collect::<Vec<_>>()
        .join(" ");
    let title: String = alert
        .kinds
        .iter()
        .map(|k| k.title())
        .collect::<Vec<_>>()
        .join(" · ");
    let msg = first_kind.as_ref().map(|k| k.message()).unwrap_or("");

    ui.painter().text(
        rect.center_top() - Vec2::new(0.0, 0.0),
        egui::Align2::CENTER_TOP,
        &icons,
        egui::FontId::proportional(24.0),
        Color32::from_rgb(0, 220, 220),
    );
    ui.painter().text(
        rect.center() - Vec2::new(0.0, 10.0),
        egui::Align2::CENTER_CENTER,
        &title,
        egui::FontId::new(14.0, egui::FontFamily::Proportional),
        Color32::WHITE,
    );
    ui.painter().text(
        rect.center() + Vec2::new(0.0, 10.0),
        egui::Align2::CENTER_CENTER,
        msg,
        egui::FontId::proportional(11.0),
        Color32::from_white_alpha(150),
    );

    let bw = 90.0;
    let by = rect.bottom() - 24.0;
    let buttons = [
        (
            "Done",
            rect.center().x - bw - 4.0,
            Color32::from_white_alpha(220),
        ),
        (
            "Snooze",
            rect.center().x + 4.0,
            Color32::from_white_alpha(60),
        ),
    ];
    for (label, x, fill) in buttons {
        let br = Rect::from_min_size(Pos2::new(x, by), Vec2::new(bw, 20.0));
        let r = ui.interact(br, egui::Id::new(format!("fa_{label}")), Sense::click());
        if r.hovered() {
            ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
        }
        let current_fill = if r.hovered() {
            if label == "Done" { Color32::from_white_alpha(255) } else { Color32::from_white_alpha(90) }
        } else {
            fill
        };
        ui.painter().rect_filled(br, Rounding::same(10.0), current_fill);
        ui.painter().text(
            br.center(),
            egui::Align2::CENTER_CENTER,
            label,
            egui::FontId::proportional(11.0),
            if label == "Done" {
                Color32::BLACK
            } else {
                Color32::WHITE
            },
        );
        if r.clicked() {
            match label {
                "Done" => state.reminders.write().complete(),
                "Snooze" => state.reminders.write().snooze(),
                _ => {}
            }
        }
    }
}
