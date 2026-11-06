// ui/mascot.rs — Port of MascotView: procedural mascot blob drawn with egui Painter

use eframe::egui::{self, Color32, Painter, Pos2, Rect, Stroke, Vec2};
use std::f32::consts::PI;

#[derive(Debug, Clone, PartialEq)]
pub enum MascotMood {
    Idle,
    Dancing,
    Confused,
    Spinning,
    Shock,
    Sleeping,
}

struct Pose {
    bounce: f32,
    jitter_x: f32,
    tilt_deg: f32,
    scale_x: f32,
    scale_y: f32,
    look_x: f32,
    eye_bob: f32,
    blink: bool,
    facing_front: bool,
    card_lift: [f32; 3],
    card_tilt: [f32; 3],
}

impl Pose {
    fn new(mood: &MascotMood, t: f64, energy: f64) -> Self {
        let mut p = Pose {
            bounce: 0.0,
            jitter_x: 0.0,
            tilt_deg: 0.0,
            scale_x: 1.0,
            scale_y: 1.0,
            look_x: 0.0,
            eye_bob: 0.0,
            blink: false,
            facing_front: true,
            card_lift: [0.0, 0.0, 0.0],
            card_tilt: [-4.0, 3.0, 0.0],
        };
        let t = t as f32;
        match mood {
            MascotMood::Idle => {
                p.scale_y = 1.0 + (t * 2.0).sin() * 0.015;
                p.scale_x = 1.0 - (t * 2.0).sin() * 0.008;
                p.blink = t.rem_euclid(4.2) < 0.13;
                p.card_lift = [0.01 * (t * 2.0).sin(), 0.01 * (t * 2.0 + 1.0).sin(), 0.0];
            }
            MascotMood::Dancing => {
                let beat = t * 2.0;
                let strength = (0.6 + 0.6 * energy.clamp(0.0, 1.0) as f32).min(1.2);
                p.bounce = (beat * PI).sin().abs() * 0.08 * strength;
                p.tilt_deg = (beat * PI).sin() * 11.0 * strength;
                p.scale_y = 1.0 + (beat * 2.0 * PI).cos() * 0.05 * strength;
                p.scale_x = 1.0 - (beat * 2.0 * PI).cos() * 0.04 * strength;
                p.eye_bob = (beat * 2.0 * PI).sin() * 0.008;
                p.card_lift = [
                    0.03 * strength * ((beat * 2.0 * PI).sin()).max(0.0),
                    0.03 * strength * ((beat * 2.0 * PI - 0.9).sin()).max(0.0),
                    0.03 * strength * ((beat * 2.0 * PI - 1.8).sin()).max(0.0),
                ];
                p.card_tilt = [
                    -6.0 + (beat * PI).sin() * 6.0,
                    4.0 - (beat * PI).sin() * 5.0,
                    (beat * PI).sin() * 3.0,
                ];
            }
            MascotMood::Confused => {
                let sway = (t * 1.6).sin();
                p.tilt_deg = sway * 13.0;
                p.look_x = sway * 0.02;
                p.bounce = (t * 1.6).sin().abs() * 0.01;
                p.card_tilt = [-8.0, 6.0, -2.0];
                p.blink = t.rem_euclid(3.1) < 0.12;
            }
            MascotMood::Spinning => {
                let angle = t * 2.0 * PI / 1.2;
                p.scale_x = angle.cos();
                p.facing_front = angle.cos() > 0.0;
                p.bounce = angle.sin().abs() * 0.05;
                let ab = angle.sin().abs();
                p.card_lift = [0.02 * ab, 0.015 * ab, 0.01 * ab];
            }
            MascotMood::Shock => {
                let phase = t.rem_euclid(1.4) / 1.4;
                if phase < 0.12 {
                    let tv = phase / 0.12;
                    p.scale_y = 1.0 - 0.14 * tv;
                    p.scale_x = 1.0 + 0.08 * tv;
                } else if phase < 0.42 {
                    let tv = (phase - 0.12) / 0.3;
                    p.bounce = (tv * PI).sin() * 0.13;
                    p.scale_y = 1.1 - 0.1 * tv;
                    p.scale_x = 0.94 + 0.06 * tv;
                    let lift_v = (tv * PI).sin();
                    p.card_lift = [0.09 * lift_v, 0.07 * lift_v, 0.05 * lift_v];
                } else if phase < 0.52 {
                    let tv = (phase - 0.42) / 0.1;
                    p.scale_y = 1.0 - 0.08 * (tv * PI).sin();
                    p.scale_x = 1.0 + 0.05 * (tv * PI).sin();
                } else {
                    p.jitter_x = (t * 70.0).sin() * 0.012;
                    p.card_lift = [0.015, 0.01, 0.005];
                }
                p.card_tilt = [-10.0, 8.0, -3.0];
            }
            MascotMood::Sleeping => {
                p.scale_y = 1.0 + (t * 1.3).sin() * 0.03;
                p.card_lift = [-0.02, -0.015, -0.01];
                p.card_tilt = [-2.0, 2.0, 0.0];
            }
        }
        p
    }
}

/// Draw the mascot centered at `center` with given `size`.
/// `color_rgb`: mascot card color [r, g, b] in 0..=1.
pub fn draw_mascot(
    painter: &Painter,
    center: Pos2,
    size: f32,
    mood: MascotMood,
    color_rgb: [f32; 3],
    energy: f64,
) {
    let t = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64();

    let pose = Pose::new(&mood, t, energy);
    let s = size;
    let card_color = Color32::from_rgb(
        (color_rgb[0] * 255.0) as u8,
        (color_rgb[1] * 255.0) as u8,
        (color_rgb[2] * 255.0) as u8,
    );
    let ink = Color32::from_rgb(18, 18, 23);
    let edge = Color32::from_rgba_premultiplied(0, 0, 0, 36);
    let pouch_top = Color32::from_rgb(255, 255, 255);

    // Apply transforms manually: pivot, bounce, jitter, tilt, scale.
    // egui Painter doesn't support push/pop transforms natively,
    // so we transform all points with a helper.
    let pivot = center + Vec2::new(0.0, s * 0.42); // 0.5 * s, 0.92 * s from top-left of bounding box
    let transform = |px: f32, py: f32| -> Pos2 {
        // px, py are in [0..1] relative to bounding box top-left
        let lx = px * s;
        let ly = py * s;
        // Scale around pivot (which is at 0.5*s, 0.92*s in local coords).
        let lx = pivot.x - center.x + (lx - (0.5 * s)) * pose.scale_x + pose.jitter_x * s;
        let ly = pivot.y - center.y + (ly - (0.92 * s)) * pose.scale_y - pose.bounce * s;
        // Rotate around pivot.
        let rad = pose.tilt_deg.to_radians();
        let rx = lx * rad.cos() - ly * rad.sin();
        let ry = lx * rad.sin() + ly * rad.cos();
        center + Vec2::new(rx, ry)
    };

    // Cards peeking out of the pouch.
    let lightens = [0.55f32, 0.3, 0.0];
    for (i, &lighten) in lightens.iter().enumerate() {
        let lift = pose.card_lift[i];
        let tilt = pose.card_tilt[i];
        let x0 = 0.22 + i as f32 * 0.015;
        let y0 = 0.12 + i as f32 * 0.045 - lift;
        let cw = 0.56 - i as f32 * 0.03;
        let ch = 0.24;
        // Build a tilted rounded rect for the card — approximate with 4 corner points.
        let card_color_mix = blend(card_color, Color32::WHITE, lighten);
        draw_tilted_rect(
            painter,
            &transform,
            x0,
            y0,
            cw,
            ch,
            tilt,
            s,
            card_color_mix,
            edge,
        );
    }

    // Back panel.
    let back_tl = transform(0.1, 0.27);
    let back_br = transform(0.9, 0.44);
    painter.rect_filled(
        Rect::from_two_pos(back_tl, back_br),
        egui::Rounding::same(s * 0.085 * 0.5),
        Color32::from_rgb(237, 237, 237),
    );

    // Front flap (approximate triangle with rounded rect).
    let flap_tl = transform(0.08, 0.33);
    let flap_br = transform(0.92, 0.96);
    painter.rect_filled(
        Rect::from_two_pos(flap_tl, flap_br),
        egui::Rounding {
            nw: s * 0.06,
            ne: s * 0.06,
            sw: s * 0.09,
            se: s * 0.09,
        },
        pouch_top,
    );

    if !pose.facing_front {
        return;
    }

    // Strap.
    let strap_tl = transform(0.66, 0.50);
    let strap_br = transform(0.93, 0.65);
    painter.rect_filled(
        Rect::from_two_pos(strap_tl, strap_br),
        egui::Rounding::same(s * 0.075 * 0.5),
        Color32::from_rgb(248, 248, 248),
    );

    // Eyes.
    draw_eyes(painter, &transform, s, &mood, &pose, ink);

    // Mood extras.
    draw_extras(painter, &transform, s, &mood, t as f32);
}

fn draw_eyes(
    painter: &Painter,
    transform: &impl Fn(f32, f32) -> Pos2,
    s: f32,
    mood: &MascotMood,
    pose: &Pose,
    ink: Color32,
) {
    let center_x = 0.44 + pose.look_x;
    let eye_y = 0.55f32;
    let spacing = 0.09f32;

    for &side in &[-1.0f32, 1.0] {
        let x = center_x + side * spacing;
        let y = eye_y + pose.eye_bob;
        let ep = transform(x, y);

        match mood {
            MascotMood::Dancing => {
                // Happy "^" arc eyes.
                let left = transform(x - 0.052, y + 0.026 + pose.eye_bob);
                let right = transform(x + 0.052, y + 0.026 + pose.eye_bob);
                let ctrl = transform(x, y - 0.065 + pose.eye_bob);
                painter.line_segment([left, ctrl], Stroke::new(0.032 * s, ink));
                painter.line_segment([ctrl, right], Stroke::new(0.032 * s, ink));
            }
            MascotMood::Sleeping => {
                let left = transform(x - 0.04, y);
                let right = transform(x + 0.04, y);
                painter.line_segment([left, right], Stroke::new(0.026 * s, ink));
            }
            MascotMood::Shock => {
                let d = 0.14 * s;
                painter.circle_filled(ep, d / 2.0, ink);
                painter.circle_filled(
                    ep - Vec2::new(d * 0.1, d * 0.1) + Vec2::new(d * 0.18, d * 0.14),
                    d * 0.18,
                    Color32::WHITE,
                );
            }
            _ => {
                let mut w = 0.078 * s;
                let mut h = 0.175 * s;
                let mut off_y = 0.0;
                if *mood == MascotMood::Confused && side > 0.0 {
                    // Different right eye.
                    w *= 0.8;
                    h = h * 0.62;
                    off_y = -0.03 * s;
                }
                if pose.blink {
                    h = 0.018 * s;
                }
                let eye_rect = Rect::from_center_size(ep + Vec2::new(0.0, off_y), Vec2::new(w, h));
                painter.rect_filled(eye_rect, egui::Rounding::same(w / 2.0), ink);
                if !pose.blink {
                    let glint = Rect::from_min_size(
                        eye_rect.min + Vec2::new(w * 0.22, h * 0.1),
                        Vec2::new(w * 0.36, h * 0.28),
                    );
                    painter.rect_filled(
                        glint,
                        egui::Rounding::same(w * 0.18),
                        Color32::from_white_alpha(217),
                    );
                }
            }
        }
    }
}

fn draw_extras(
    painter: &Painter,
    transform: &impl Fn(f32, f32) -> Pos2,
    s: f32,
    mood: &MascotMood,
    t: f32,
) {
    if s < 40.0 {
        return;
    }
    match mood {
        MascotMood::Dancing => {
            for i in 0..2 {
                let progress = (t * 0.6 + i as f32 * 0.5).rem_euclid(1.0);
                let side: f32 = if i == 0 { 1.0 } else { -1.0 };
                let x = 0.5 + side * 0.44 + (progress * 6.0).sin() * 0.04;
                let y = 0.32 - progress * 0.28;
                let pos = transform(x, y);
                painter.text(
                    pos,
                    egui::Align2::CENTER_CENTER,
                    "♪",
                    egui::FontId::proportional(s * 0.2),
                    Color32::from_white_alpha(((1.0 - progress) * 255.0) as u8),
                );
            }
        }
        MascotMood::Confused => {
            let wobble = (t * 3.0).sin() * 0.02;
            let pos = transform(0.84 + wobble, 0.14);
            painter.text(
                pos,
                egui::Align2::CENTER_CENTER,
                "?",
                egui::FontId::proportional(s * 0.24),
                Color32::from_white_alpha(242),
            );
        }
        MascotMood::Shock => {
            let pulse = 0.85 + 0.15 * (t * 14.0).sin();
            let pos = transform(0.86, 0.13);
            painter.text(
                pos,
                egui::Align2::CENTER_CENTER,
                "!",
                egui::FontId::proportional(s * 0.26 * pulse),
                Color32::WHITE,
            );
        }
        MascotMood::Sleeping => {
            let progress = (t * 0.4).rem_euclid(1.0);
            let pos = transform(0.82 + progress * 0.08, 0.3 - progress * 0.22);
            painter.text(
                pos,
                egui::Align2::CENTER_CENTER,
                "z",
                egui::FontId::proportional(s * (0.13 + 0.08 * progress)),
                Color32::from_white_alpha(((1.0 - progress) * 255.0) as u8),
            );
        }
        _ => {}
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn blend(a: Color32, b: Color32, t: f32) -> Color32 {
    let lerp = |ca: u8, cb: u8| -> u8 { (ca as f32 * (1.0 - t) + cb as f32 * t) as u8 };
    Color32::from_rgb(lerp(a.r(), b.r()), lerp(a.g(), b.g()), lerp(a.b(), b.b()))
}

fn draw_tilted_rect(
    painter: &Painter,
    transform: &impl Fn(f32, f32) -> Pos2,
    x0: f32,
    y0: f32,
    w: f32,
    h: f32,
    tilt_deg: f32,
    s: f32,
    fill: Color32,
    stroke: Color32,
) {
    // Build corners and apply tilt around card center.
    let cx = x0 + w / 2.0;
    let cy = y0 + h / 2.0;
    let rad = tilt_deg.to_radians();
    let rotate = |dx: f32, dy: f32| -> (f32, f32) {
        (
            dx * rad.cos() - dy * rad.sin(),
            dx * rad.sin() + dy * rad.cos(),
        )
    };

    let corners = [
        (-w / 2.0, -h / 2.0),
        (w / 2.0, -h / 2.0),
        (w / 2.0, h / 2.0),
        (-w / 2.0, h / 2.0),
    ];
    let pts: Vec<Pos2> = corners
        .iter()
        .map(|&(dx, dy)| {
            let (rx, ry) = rotate(dx, dy);
            transform(cx + rx, cy + ry)
        })
        .collect();

    // Draw as a filled convex polygon approximation.
    painter.add(egui::Shape::convex_polygon(
        pts.clone(),
        fill,
        Stroke::new(0.008 * s, stroke),
    ));
}
