// ui/spectrum_bars.rs — Audio visualizer: N frequency bars

use crate::visualizer::BAND_COUNT;
use eframe::egui::{Color32, Painter, Pos2, Rect, Rounding};

/// Draw N animated spectrum bars inside `rect`.
pub fn draw_bars(
    painter: &Painter,
    rect: Rect,
    n: usize,
    color: Color32,
    bands: &[f32; BAND_COUNT],
) {
    let n = n.min(BAND_COUNT);
    // Pick n evenly-spaced bands.
    let bar_w = (rect.width() / n as f32 - 2.0).max(2.0);
    let gap = (rect.width() - bar_w * n as f32) / (n + 1) as f32;
    let max_h = rect.height();

    for i in 0..n {
        let band_idx = (i * BAND_COUNT / n).min(BAND_COUNT - 1);
        let level = bands[band_idx];
        let bar_h = (level * max_h).max(2.0);

        let x = rect.left() + gap + i as f32 * (bar_w + gap);
        let top = rect.bottom() - bar_h;
        let bar_rect = Rect::from_min_max(Pos2::new(x, top), Pos2::new(x + bar_w, rect.bottom()));
        painter.rect_filled(bar_rect, Rounding::same(bar_w / 2.0), color);
    }
}
