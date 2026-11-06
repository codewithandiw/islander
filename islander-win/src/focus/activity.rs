// focus/activity.rs — Tracks active work time using GetLastInputInfo + power events

use chrono::Local;
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;

use crate::settings::cache_dir;
use crate::settings::AppSettings;

const HISTORY_FILE: &str = "activity_history.json";
const KEEP_DAYS: usize = 30;
const TICK_SECS: f64 = 10.0;

#[derive(Debug, Serialize, Deserialize, Default)]
struct HistoryFile {
    history: HashMap<String, f64>,      // "YYYY-MM-DD" → seconds
    first_active: HashMap<String, i64>, // "YYYY-MM-DD" → unix timestamp
}

pub struct ActivityTracker {
    settings: Arc<RwLock<AppSettings>>,
    pub today_active_secs: f64,
    pub since_last_break_secs: f64,
    pub is_active: bool,
    pub first_active_today: Option<std::time::SystemTime>,

    day_key: String,
    last_active_at: std::time::Instant,
    last_save: std::time::Instant,
    history: HashMap<String, f64>,
    first_active_map: HashMap<String, i64>,
}

impl ActivityTracker {
    pub fn new(settings: Arc<RwLock<AppSettings>>) -> Self {
        let day_key = today_key();
        let (history, first_active_map) = load_history();
        let today_active_secs = *history.get(&day_key).unwrap_or(&0.0);
        let first_active_today = first_active_map
            .get(&day_key)
            .map(|&ts| std::time::UNIX_EPOCH + std::time::Duration::from_secs(ts as u64));

        Self {
            settings,
            today_active_secs,
            since_last_break_secs: 0.0,
            is_active: false,
            first_active_today,
            day_key,
            last_active_at: std::time::Instant::now(),
            last_save: std::time::Instant::now(),
            history,
            first_active_map,
        }
    }

    /// Call every TICK_SECS. Returns (active_delta, break_detected).
    pub fn tick(&mut self) -> (f64, bool) {
        let new_key = today_key();
        if new_key != self.day_key {
            self.save();
            self.day_key = new_key.clone();
            self.today_active_secs = 0.0;
            self.first_active_today = None;
        }

        let idle_secs = seconds_since_last_input();
        let idle_threshold = self.settings.read().idle_threshold_minutes as f64 * 60.0;
        let break_reset = self.settings.read().break_reset_minutes as f64 * 60.0;

        let active = !is_screen_locked() && !is_system_asleep() && idle_secs < idle_threshold;

        let away = self.last_active_at.elapsed().as_secs_f64();
        let mut break_detected = false;
        if away >= break_reset && self.since_last_break_secs > 0.0 {
            self.since_last_break_secs = 0.0;
            break_detected = true;
        }

        let mut delta = 0.0;
        if active {
            self.last_active_at = std::time::Instant::now();
            delta = TICK_SECS.min(away);
            self.today_active_secs += delta;
            self.since_last_break_secs += delta;
            if self.first_active_today.is_none() {
                let now = std::time::SystemTime::now();
                self.first_active_today = Some(now);
                if let Ok(dur) = now.duration_since(std::time::UNIX_EPOCH) {
                    self.first_active_map
                        .insert(self.day_key.clone(), dur.as_secs() as i64);
                }
            }
        }
        self.is_active = active;

        if self.last_save.elapsed().as_secs() >= 60 {
            self.save();
        }

        (delta, break_detected)
    }

    pub fn take_break_now(&mut self) {
        self.since_last_break_secs = 0.0;
    }

    /// (date_label, active_seconds) for the last `days` days, oldest first.
    pub fn history(&self, days: usize) -> Vec<(String, f64)> {
        let today = Local::now();
        (0..days)
            .rev()
            .map(|offset| {
                let date = today - chrono::Duration::days(offset as i64);
                let key = date.format("%Y-%m-%d").to_string();
                let secs = if key == self.day_key {
                    self.today_active_secs
                } else {
                    *self.history.get(&key).unwrap_or(&0.0)
                };
                (key, secs)
            })
            .collect()
    }

    fn save(&mut self) {
        self.history
            .insert(self.day_key.clone(), self.today_active_secs);
        // Prune old days.
        let mut keys: Vec<_> = self.history.keys().cloned().collect();
        keys.sort();
        for old in keys.into_iter().rev().skip(KEEP_DAYS) {
            self.history.remove(&old);
        }
        save_history(&self.history, &self.first_active_map);
        self.last_save = std::time::Instant::now();
    }
}

// ── Persistence ───────────────────────────────────────────────────────────────

fn history_path() -> std::path::PathBuf {
    cache_dir().join(HISTORY_FILE)
}

fn load_history() -> (HashMap<String, f64>, HashMap<String, i64>) {
    if let Ok(data) = std::fs::read_to_string(history_path()) {
        if let Ok(h) = serde_json::from_str::<HistoryFile>(&data) {
            return (h.history, h.first_active);
        }
    }
    (HashMap::new(), HashMap::new())
}

fn save_history(history: &HashMap<String, f64>, first_active: &HashMap<String, i64>) {
    let path = history_path();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let file = HistoryFile {
        history: history.clone(),
        first_active: first_active.clone(),
    };
    if let Ok(data) = serde_json::to_string(&file) {
        let _ = std::fs::write(path, data);
    }
}

// ── Platform idle detection ───────────────────────────────────────────────────

fn today_key() -> String {
    Local::now().format("%Y-%m-%d").to_string()
}

#[cfg(windows)]
fn seconds_since_last_input() -> f64 {
    use windows::Win32::System::SystemInformation::GetTickCount;
    use windows::Win32::UI::Input::KeyboardAndMouse::GetLastInputInfo;
    use windows::Win32::UI::Input::KeyboardAndMouse::LASTINPUTINFO;

    let mut info = LASTINPUTINFO {
        cbSize: std::mem::size_of::<LASTINPUTINFO>() as u32,
        dwTime: 0,
    };
    unsafe {
        if GetLastInputInfo(&mut info).as_bool() {
            let now = GetTickCount();
            let diff = now.wrapping_sub(info.dwTime);
            diff as f64 / 1000.0
        } else {
            0.0
        }
    }
}

#[cfg(not(windows))]
fn seconds_since_last_input() -> f64 {
    0.0
}

// Simple flags updated by window message processing.
static SCREEN_LOCKED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static SYSTEM_ASLEEP: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

pub fn set_screen_locked(locked: bool) {
    SCREEN_LOCKED.store(locked, std::sync::atomic::Ordering::Relaxed);
}

pub fn set_system_asleep(asleep: bool) {
    SYSTEM_ASLEEP.store(asleep, std::sync::atomic::Ordering::Relaxed);
}

fn is_screen_locked() -> bool {
    SCREEN_LOCKED.load(std::sync::atomic::Ordering::Relaxed)
}

fn is_system_asleep() -> bool {
    SYSTEM_ASLEEP.load(std::sync::atomic::Ordering::Relaxed)
}
