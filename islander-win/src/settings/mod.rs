// settings/mod.rs — App preferences persisted as JSON in %APPDATA%\Islander\settings.json

use eframe::egui;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

fn appdata_dir() -> PathBuf {
    directories::ProjectDirs::from("dev", "islander", "Islander")
        .map(|d| d.data_dir().to_path_buf())
        .unwrap_or_else(|| std::env::temp_dir().join("Islander"))
}

pub fn settings_path() -> PathBuf {
    appdata_dir().join("settings.json")
}

pub fn cache_dir() -> PathBuf {
    directories::ProjectDirs::from("dev", "islander", "Islander")
        .map(|d| d.cache_dir().to_path_buf())
        .unwrap_or_else(|| std::env::temp_dir().join("IslanderCache"))
}

// ── Mascot color ──────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MascotColor {
    Sunny,
    Bubblegum,
    Mint,
    Sky,
    Grape,
}

impl Default for MascotColor {
    fn default() -> Self {
        MascotColor::Sunny
    }
}

impl MascotColor {
    pub fn name(&self) -> &'static str {
        match self {
            MascotColor::Sunny => "Sunny",
            MascotColor::Bubblegum => "Bubblegum",
            MascotColor::Mint => "Mint",
            MascotColor::Sky => "Sky",
            MascotColor::Grape => "Grape",
        }
    }

    /// Returns [r, g, b] in 0.0..=1.0
    pub fn rgb(&self) -> [f32; 3] {
        match self {
            MascotColor::Sunny => [1.00, 0.80, 0.25],
            MascotColor::Bubblegum => [1.00, 0.56, 0.72],
            MascotColor::Mint => [0.45, 0.90, 0.70],
            MascotColor::Sky => [0.45, 0.75, 1.00],
            MascotColor::Grape => [0.72, 0.58, 1.00],
        }
    }

    pub fn egui_color(&self) -> egui::Color32 {
        let [r, g, b] = self.rgb();
        egui::Color32::from_rgb((r * 255.0) as u8, (g * 255.0) as u8, (b * 255.0) as u8)
    }

    pub fn all() -> &'static [MascotColor] {
        &[
            MascotColor::Sunny,
            MascotColor::Bubblegum,
            MascotColor::Mint,
            MascotColor::Sky,
            MascotColor::Grape,
        ]
    }
}

// ── Reminder config ───────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ReminderConfig {
    pub enabled: bool,
    pub minutes: u32,
}

impl Default for ReminderConfig {
    fn default() -> Self {
        ReminderConfig {
            enabled: true,
            minutes: 180,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ReminderKind {
    WorkBreak,
    Stretch,
    Drink,
}

impl ReminderKind {
    pub fn all() -> &'static [ReminderKind] {
        &[
            ReminderKind::WorkBreak,
            ReminderKind::Stretch,
            ReminderKind::Drink,
        ]
    }

    pub fn title(&self) -> &'static str {
        match self {
            ReminderKind::WorkBreak => "Take a break",
            ReminderKind::Stretch => "Stretch",
            ReminderKind::Drink => "Drink water",
        }
    }

    pub fn message(&self) -> &'static str {
        match self {
            ReminderKind::WorkBreak => "Step away from the screen for a few minutes.",
            ReminderKind::Stretch => "Stand up, roll your shoulders and stretch your back.",
            ReminderKind::Drink => "Have a glass of water.",
        }
    }

    pub fn icon(&self) -> &'static str {
        match self {
            ReminderKind::WorkBreak => "🚶",
            ReminderKind::Stretch => "🤸",
            ReminderKind::Drink => "💧",
        }
    }
}

// ── Sound selection ───────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FocusReminderSound {
    AmongUs,
    Bruh,
    MetalGear,
    SadViolin,
    Shocked,
    Huh,
}

impl Default for FocusReminderSound {
    fn default() -> Self {
        FocusReminderSound::AmongUs
    }
}

impl FocusReminderSound {
    pub fn file_name(&self) -> &'static str {
        match self {
            FocusReminderSound::AmongUs => "among_us",
            FocusReminderSound::Bruh => "bruh",
            FocusReminderSound::MetalGear => "metal_gear",
            FocusReminderSound::SadViolin => "sad_violin",
            FocusReminderSound::Shocked => "shocked",
            FocusReminderSound::Huh => "huh",
        }
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            FocusReminderSound::AmongUs => "Among Us",
            FocusReminderSound::Bruh => "Bruh",
            FocusReminderSound::MetalGear => "Metal Gear Alert",
            FocusReminderSound::SadViolin => "Sad Violin",
            FocusReminderSound::Shocked => "Shocked",
            FocusReminderSound::Huh => "Huh?",
        }
    }

    pub fn all() -> &'static [FocusReminderSound] {
        &[
            FocusReminderSound::AmongUs,
            FocusReminderSound::Bruh,
            FocusReminderSound::MetalGear,
            FocusReminderSound::SadViolin,
            FocusReminderSound::Shocked,
            FocusReminderSound::Huh,
        ]
    }
}

// ── Main settings struct ──────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSettings {
    #[serde(default = "default_true")]
    pub expand_on_hover: bool,
    #[serde(default = "default_true")]
    pub show_mascot: bool,
    #[serde(default)]
    pub mascot_color: MascotColor,
    #[serde(default = "default_true")]
    pub show_visualizer: bool,
    #[serde(default = "default_true")]
    pub show_lyrics: bool,
    #[serde(default = "default_true")]
    pub show_compact_lyrics: bool,
    #[serde(default = "default_true")]
    pub play_reminder_sound: bool,
    #[serde(default)]
    pub focus_reminder_sound: FocusReminderSound,
    #[serde(default = "default_idle_threshold")]
    pub idle_threshold_minutes: u32,
    #[serde(default = "default_break_reset")]
    pub break_reset_minutes: u32,
    #[serde(default = "default_daily_goal")]
    pub daily_goal_hours: u32,
    #[serde(default = "default_reminders")]
    pub reminders: HashMap<String, ReminderConfig>,
}

fn default_true() -> bool {
    true
}
fn default_idle_threshold() -> u32 {
    5
}
fn default_break_reset() -> u32 {
    15
}
fn default_daily_goal() -> u32 {
    8
}
fn default_reminders() -> HashMap<String, ReminderConfig> {
    let mut m = HashMap::new();
    m.insert("workBreak".into(), ReminderConfig::default());
    m.insert("stretch".into(), ReminderConfig::default());
    m.insert("drink".into(), ReminderConfig::default());
    m
}

impl Default for AppSettings {
    fn default() -> Self {
        AppSettings {
            expand_on_hover: true,
            show_mascot: true,
            mascot_color: MascotColor::default(),
            show_visualizer: true,
            show_lyrics: true,
            show_compact_lyrics: true,
            play_reminder_sound: true,
            focus_reminder_sound: FocusReminderSound::default(),
            idle_threshold_minutes: 5,
            break_reset_minutes: 15,
            daily_goal_hours: 8,
            reminders: default_reminders(),
        }
    }
}

impl AppSettings {
    pub fn load() -> Self {
        let path = settings_path();
        if let Ok(data) = std::fs::read_to_string(&path) {
            if let Ok(s) = serde_json::from_str::<AppSettings>(&data) {
                return s;
            }
        }
        AppSettings::default()
    }

    pub fn save(&self) {
        let path = settings_path();
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Ok(data) = serde_json::to_string_pretty(self) {
            let _ = std::fs::write(path, data);
        }
    }

    pub fn reminder_config(&self, kind: &ReminderKind) -> ReminderConfig {
        let key = match kind {
            ReminderKind::WorkBreak => "workBreak",
            ReminderKind::Stretch => "stretch",
            ReminderKind::Drink => "drink",
        };
        self.reminders.get(key).cloned().unwrap_or_default()
    }

    pub fn set_reminder_config(&mut self, kind: &ReminderKind, config: ReminderConfig) {
        let key = match kind {
            ReminderKind::WorkBreak => "workBreak",
            ReminderKind::Stretch => "stretch",
            ReminderKind::Drink => "drink",
        };
        self.reminders.insert(key.into(), config);
        self.save();
    }
}
