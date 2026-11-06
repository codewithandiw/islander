// focus/reminders.rs — Fires work-break / stretch / drink reminders after active time thresholds

use parking_lot::RwLock;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;

use crate::settings::{AppSettings, ReminderConfig, ReminderKind};

#[derive(Debug, Clone)]
pub struct ReminderAlert {
    pub kinds: Vec<ReminderKind>,
    pub fired_at: Instant,
}

pub struct ReminderScheduler {
    settings: Arc<RwLock<AppSettings>>,
    pub active_since: HashMap<ReminderKind, f64>, // seconds of active time since last completion
    pub current: Option<ReminderAlert>,
    snooze_seconds: f64,
}

impl ReminderScheduler {
    pub fn new(settings: Arc<RwLock<AppSettings>>) -> Self {
        Self {
            settings,
            active_since: HashMap::new(),
            current: None,
            snooze_seconds: 10.0 * 60.0,
        }
    }

    pub fn add_active_time(&mut self, delta: f64) {
        let mut due: Vec<ReminderKind> = Vec::new();

        for kind in ReminderKind::all() {
            let config = self.settings.read().reminder_config(kind);
            if !config.enabled {
                continue;
            }
            let accum = self.active_since.entry(kind.clone()).or_insert(0.0);
            *accum += delta;
            if *accum >= interval_secs(&config) {
                due.push(kind.clone());
            }
        }

        if due.is_empty() {
            return;
        }

        if let Some(ref mut alert) = self.current {
            let added: Vec<_> = due
                .into_iter()
                .filter(|k| !alert.kinds.contains(k))
                .collect();
            if !added.is_empty() {
                alert.kinds.extend(added);
            }
        } else {
            self.play_sound();
            self.current = Some(ReminderAlert {
                kinds: due,
                fired_at: Instant::now(),
            });
        }
    }

    pub fn remaining_secs(&self, kind: &ReminderKind) -> Option<f64> {
        let config = self.settings.read().reminder_config(kind);
        if !config.enabled {
            return None;
        }
        let accum = self.active_since.get(kind).copied().unwrap_or(0.0);
        Some((interval_secs(&config) - accum).max(0.0))
    }

    pub fn complete(&mut self) {
        if let Some(ref alert) = self.current {
            for kind in &alert.kinds {
                self.active_since.insert(kind.clone(), 0.0);
            }
        }
        self.current = None;
    }

    pub fn snooze(&mut self) {
        if let Some(ref alert) = self.current {
            for kind in &alert.kinds {
                let config = self.settings.read().reminder_config(kind);
                let new_val = (interval_secs(&config) - self.snooze_seconds).max(0.0);
                self.active_since.insert(kind.clone(), new_val);
            }
        }
        self.current = None;
    }

    pub fn dismiss_for_now(&mut self) {
        self.snooze();
    }

    pub fn reset_all(&mut self) {
        self.active_since.clear();
        self.current = None;
    }

    pub fn preview(&mut self, kind: &ReminderKind) {
        self.play_sound();
        self.current = Some(ReminderAlert {
            kinds: vec![kind.clone()],
            fired_at: Instant::now(),
        });
    }

    fn play_sound(&self) {
        let s = self.settings.read();
        if s.play_reminder_sound {
            s.focus_reminder_sound.play();
        }
    }
}

fn interval_secs(config: &ReminderConfig) -> f64 {
    (config.minutes.max(1) as f64) * 60.0
}
