// ui/shelf_tab.rs — Shelf tab: temporary file tray

use crate::shelf::format_bytes;
use crate::AppState;
use eframe::egui::{self, Color32, Pos2, Rect, Rounding, Sense, Vec2};
use uuid::Uuid;

pub fn draw(ui: &mut egui::Ui, rect: Rect, state: &AppState) {
    let shelf = state.shelf.read();
    let items = shelf.items.clone();
    let total = shelf.total_size();
    let message = shelf.message.as_ref().map(|(m, _)| m.clone());
    drop(shelf);

    // Header.
    let used = format!("{} / 100 MB", format_bytes(total));
    ui.painter().text(
        rect.min,
        egui::Align2::LEFT_TOP,
        "Shelf",
        egui::FontId::new(14.0, egui::FontFamily::Proportional),
        Color32::WHITE,
    );
    ui.painter().text(
        rect.min + Vec2::new(60.0, 0.0),
        egui::Align2::LEFT_TOP,
        &used,
        egui::FontId::proportional(10.0),
        Color32::from_white_alpha(130),
    );

    // Message feedback.
    if let Some(msg) = message {
        ui.painter().text(
            rect.left_top() + Vec2::new(0.0, 20.0),
            egui::Align2::LEFT_TOP,
            &msg,
            egui::FontId::proportional(11.0),
            Color32::from_rgb(255, 220, 100),
        );
    }

    if items.is_empty() {
        ui.painter().text(
            rect.center(),
            egui::Align2::CENTER_CENTER,
            "Drag files here to shelve them temporarily.",
            egui::FontId::proportional(11.0),
            Color32::from_white_alpha(100),
        );
    } else {
        let list_top = rect.min.y + 32.0;
        let mut open_id: Option<Uuid> = None;
        let mut copy_id: Option<Uuid> = None;
        let mut del_id: Option<Uuid> = None;

        for (i, item) in items.iter().enumerate() {
            let y = list_top + i as f32 * 30.0;
            if y + 28.0 > rect.bottom() {
                break;
            }
            let row = Rect::from_min_size(Pos2::new(rect.left(), y), Vec2::new(rect.width(), 26.0));

            // Row interaction (double click to open).
            let row_resp = ui.interact(
                row,
                egui::Id::new(format!("srow_{}", item.id)),
                Sense::click(),
            );
            if row_resp.hovered() {
                ui.painter().rect_filled(
                    row,
                    Rounding::same(4.0),
                    Color32::from_white_alpha(15),
                );
            }
            if row_resp.double_clicked() {
                open_id = Some(item.id);
            }

            // File icon placeholder.
            ui.painter().rect_filled(
                Rect::from_center_size(
                    Pos2::new(row.left() + 12.0, row.center().y),
                    Vec2::splat(20.0),
                ),
                Rounding::same(4.0),
                Color32::from_white_alpha(30),
            );
            ui.painter().text(
                Pos2::new(row.left() + 12.0, row.center().y),
                egui::Align2::CENTER_CENTER,
                "📄",
                egui::FontId::proportional(13.0),
                Color32::WHITE,
            );

            // Name.
            ui.painter().text(
                Pos2::new(row.left() + 28.0, row.center().y - 5.0),
                egui::Align2::LEFT_CENTER,
                &item.name,
                egui::FontId::proportional(11.0),
                Color32::WHITE,
            );
            // Size.
            ui.painter().text(
                Pos2::new(row.left() + 28.0, row.center().y + 5.0),
                egui::Align2::LEFT_CENTER,
                &format_bytes(item.size),
                egui::FontId::proportional(9.0),
                Color32::from_white_alpha(130),
            );

            // Right-side buttons: copy, delete.
            let del_rect = Rect::from_center_size(
                Pos2::new(row.right() - 10.0, row.center().y),
                Vec2::splat(18.0),
            );
            let dr = ui.interact(
                del_rect,
                egui::Id::new(format!("sdel_{}", item.id)),
                Sense::click(),
            );
            if dr.hovered() {
                ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
                ui.painter().rect_filled(del_rect, Rounding::same(4.0), Color32::from_white_alpha(30));
            }
            ui.painter().text(
                del_rect.center(),
                egui::Align2::CENTER_CENTER,
                "✕",
                egui::FontId::proportional(10.0),
                if dr.hovered() { Color32::WHITE } else { Color32::from_white_alpha(100) },
            );
            if dr.clicked() {
                del_id = Some(item.id);
            }

            let copy_rect = Rect::from_center_size(
                Pos2::new(row.right() - 32.0, row.center().y),
                Vec2::splat(18.0),
            );
            let cr = ui.interact(
                copy_rect,
                egui::Id::new(format!("scopy_{}", item.id)),
                Sense::click(),
            );
            if cr.hovered() {
                ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
                ui.painter().rect_filled(copy_rect, Rounding::same(4.0), Color32::from_white_alpha(30));
            }
            ui.painter().text(
                copy_rect.center(),
                egui::Align2::CENTER_CENTER,
                "⎘",
                egui::FontId::proportional(10.0),
                if cr.hovered() { Color32::WHITE } else { Color32::from_white_alpha(100) },
            );
            if cr.clicked() {
                copy_id = Some(item.id);
            }
        }

        if let Some(id) = open_id {
            if let Some(item) = items.iter().find(|i| i.id == id) {
                state.shelf.read().open(item);
            }
        }
        if let Some(id) = copy_id {
            if let Some(item) = items.iter().find(|i| i.id == id) {
                state.shelf.write().copy_to_clipboard(item);
            }
        }
        if let Some(id) = del_id {
            state.shelf.write().remove(id);
        }
    }

    // Clean button.
    let clean_rect = Rect::from_min_size(
        Pos2::new(rect.right() - 60.0, rect.top()),
        Vec2::new(60.0, 18.0),
    );
    let cleanr = ui.interact(clean_rect, egui::Id::new("shelf_clean"), Sense::click());
    if cleanr.hovered() {
        ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
    }
    ui.painter().rect_filled(
        clean_rect,
        Rounding::same(9.0),
        if cleanr.hovered() { Color32::from_white_alpha(55) } else { Color32::from_white_alpha(35) },
    );
    ui.painter().text(
        clean_rect.center(),
        egui::Align2::CENTER_CENTER,
        "Clean",
        egui::FontId::proportional(11.0),
        Color32::WHITE,
    );
    if cleanr.clicked() {
        state.shelf.write().clean();
    }
}
