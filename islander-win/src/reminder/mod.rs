// reminder/mod.rs — Event reminders (user-created, date-based)

use chrono::{DateTime, Datelike, Local, Weekday};
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use uuid::Uuid;

use crate::settings::cache_dir;

const REMINDERS_FILE: &str = "event_reminders.json";

// ── Types ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum EventReminderRepeat {
    Never,
    Hourly,
    Daily,
    Weekdays,
    Weekly,
    Monthly,
    Yearly,
}

impl EventReminderRepeat {
    pub fn title(&self) -> &'static str {
        match self {
            EventReminderRepeat::Never => "One-time",
            EventReminderRepeat::Hourly => "Hourly",
            EventReminderRepeat::Daily => "Daily",
            EventReminderRepeat::Weekdays => "Weekdays (Mon–Fri)",
            EventReminderRepeat::Weekly => "Weekly",
            EventReminderRepeat::Monthly => "Monthly",
            EventReminderRepeat::Yearly => "Yearly",
        }
    }

    pub fn all() -> &'static [EventReminderRepeat] {
        &[
            EventReminderRepeat::Never,
            EventReminderRepeat::Hourly,
            EventReminderRepeat::Daily,
            EventReminderRepeat::Weekdays,
            EventReminderRepeat::Weekly,
            EventReminderRepeat::Monthly,
            EventReminderRepeat::Yearly,
        ]
    }

    pub fn next_date(&self, after: DateTime<Local>, original: DateTime<Local>) -> DateTime<Local> {
        let mut candidate = original;
        if candidate > after {
            return candidate;
        }
        match self {
            EventReminderRepeat::Never => candidate,
            EventReminderRepeat::Hourly => {
                while candidate <= after {
                    candidate = candidate + chrono::Duration::hours(1);
                }
                candidate
            }
            EventReminderRepeat::Daily => {
                while candidate <= after {
                    candidate = candidate + chrono::Duration::days(1);
                }
                candidate
            }
            EventReminderRepeat::Weekdays => {
                while candidate <= after
                    || matches!(candidate.weekday(), Weekday::Sat | Weekday::Sun)
                {
                    candidate = candidate + chrono::Duration::days(1);
                }
                candidate
            }
            EventReminderRepeat::Weekly => {
                while candidate <= after {
                    candidate = candidate + chrono::Duration::weeks(1);
                }
                candidate
            }
            EventReminderRepeat::Monthly => {
                while candidate <= after {
                    candidate = candidate + chrono::Duration::days(30);
                }
                candidate
            }
            EventReminderRepeat::Yearly => {
                while candidate <= after {
                    candidate = candidate + chrono::Duration::days(365);
                }
                candidate
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum EventReminderLeadTime {
    AtTime,
    Min2,
    Min5,
    Min10,
    Min15,
    Min30,
    Hour1,
}

impl EventReminderLeadTime {
    pub fn secs(&self) -> i64 {
        match self {
            EventReminderLeadTime::AtTime => 0,
            EventReminderLeadTime::Min2 => 120,
            EventReminderLeadTime::Min5 => 300,
            EventReminderLeadTime::Min10 => 600,
            EventReminderLeadTime::Min15 => 900,
            EventReminderLeadTime::Min30 => 1800,
            EventReminderLeadTime::Hour1 => 3600,
        }
    }

    pub fn title(&self) -> &'static str {
        match self {
            EventReminderLeadTime::AtTime => "At event time",
            EventReminderLeadTime::Min2 => "2 min before",
            EventReminderLeadTime::Min5 => "5 min before",
            EventReminderLeadTime::Min10 => "10 min before",
            EventReminderLeadTime::Min15 => "15 min before",
            EventReminderLeadTime::Min30 => "30 min before",
            EventReminderLeadTime::Hour1 => "1 hour before",
        }
    }

    pub fn all() -> &'static [EventReminderLeadTime] {
        &[
            EventReminderLeadTime::AtTime,
            EventReminderLeadTime::Min2,
            EventReminderLeadTime::Min5,
            EventReminderLeadTime::Min10,
            EventReminderLeadTime::Min15,
            EventReminderLeadTime::Min30,
            EventReminderLeadTime::Hour1,
        ]
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EventReminder {
    pub id: Uuid,
    pub title: String,
    pub notes: String,
    pub due_date: DateTime<Local>,
    pub repeat_schedule: EventReminderRepeat,
    pub sound_name: String,
    pub lead_time: EventReminderLeadTime,
    pub is_completed: bool,
    pub created_at: DateTime<Local>,
    pub snoozed_until: Option<DateTime<Local>>,
    pub approached_notified_at: Option<DateTime<Local>>,
    pub due_notified_at: Option<DateTime<Local>>,
}

impl EventReminder {
    pub fn new(title: impl Into<String>, due_date: DateTime<Local>) -> Self {
        Self {
            id: Uuid::new_v4(),
            title: title.into(),
            notes: String::new(),
            due_date,
            repeat_schedule: EventReminderRepeat::Never,
            sound_name: "among_us".into(),
            lead_time: EventReminderLeadTime::Min5,
            is_completed: false,
            created_at: Local::now(),
            snoozed_until: None,
            approached_notified_at: None,
            due_notified_at: None,
        }
    }

    pub fn effective_target(&self) -> DateTime<Local> {
        self.snoozed_until.unwrap_or(self.due_date)
    }

    pub fn is_approaching(&self, now: DateTime<Local>) -> bool {
        if self.is_completed || self.lead_time == EventReminderLeadTime::AtTime {
            return false;
        }
        let threshold = self.effective_target() - chrono::Duration::seconds(self.lead_time.secs());
        now >= threshold && now < self.effective_target()
    }

    pub fn is_due(&self, now: DateTime<Local>) -> bool {
        !self.is_completed && now >= self.effective_target()
    }
}

#[derive(Debug, Clone)]
pub struct EventReminderAlert {
    pub reminder: EventReminder,
    pub is_approaching_warning: bool,
    pub fired_at: std::time::Instant,
}

// ── Store ─────────────────────────────────────────────────────────────────────

pub struct EventReminderStore {
    pub reminders: Vec<EventReminder>,
    pub active_alert: Option<EventReminderAlert>,
}

impl EventReminderStore {
    pub fn load() -> Self {
        let reminders = load_reminders();
        Self {
            reminders,
            active_alert: None,
        }
    }

    fn save(&self) {
        save_reminders(&self.reminders);
    }

    pub fn add(&mut self, reminder: EventReminder) {
        self.reminders.push(reminder);
        self.save();
    }

    pub fn update(&mut self, reminder: EventReminder) {
        if let Some(r) = self.reminders.iter_mut().find(|r| r.id == reminder.id) {
            *r = reminder;
        }
        self.save();
    }

    pub fn delete(&mut self, id: Uuid) {
        self.reminders.retain(|r| r.id != id);
        if self
            .active_alert
            .as_ref()
            .map(|a| a.reminder.id == id)
            .unwrap_or(false)
        {
            self.active_alert = None;
        }
        self.save();
    }

    pub fn toggle_completed(&mut self, id: Uuid) {
        if let Some(r) = self.reminders.iter_mut().find(|r| r.id == id) {
            r.is_completed = !r.is_completed;
        }
        if self
            .active_alert
            .as_ref()
            .map(|a| a.reminder.id == id)
            .unwrap_or(false)
        {
            self.active_alert = None;
        }
        self.save();
    }

    pub fn snooze(&mut self, id: Uuid, minutes: i64) {
        if let Some(r) = self.reminders.iter_mut().find(|r| r.id == id) {
            r.snoozed_until = Some(Local::now() + chrono::Duration::minutes(minutes));
        }
        if self
            .active_alert
            .as_ref()
            .map(|a| a.reminder.id == id)
            .unwrap_or(false)
        {
            self.active_alert = None;
        }
        self.save();
    }

    pub fn dismiss_alert(&mut self) {
        self.active_alert = None;
    }

    /// Called by the background checker task.
    pub fn check_now(&mut self) {
        let now = Local::now();
        for reminder in self.reminders.iter_mut() {
            if reminder.is_completed {
                continue;
            }

            // Handle repeating reminders: advance due date if past.
            if reminder.due_date < now && reminder.repeat_schedule != EventReminderRepeat::Never {
                let next = reminder.repeat_schedule.next_date(now, reminder.due_date);
                reminder.due_date = next;
                reminder.snoozed_until = None;
                reminder.due_notified_at = None;
                reminder.approached_notified_at = None;
            }

            if reminder.is_due(now) && reminder.due_notified_at.is_none() {
                reminder.due_notified_at = Some(now);
                crate::sound::play(&reminder.sound_name);
                self.active_alert = Some(EventReminderAlert {
                    reminder: reminder.clone(),
                    is_approaching_warning: false,
                    fired_at: std::time::Instant::now(),
                });
                return; // show one at a time
            } else if reminder.is_approaching(now) && reminder.approached_notified_at.is_none() {
                reminder.approached_notified_at = Some(now);
                crate::sound::play(&reminder.sound_name);
                self.active_alert = Some(EventReminderAlert {
                    reminder: reminder.clone(),
                    is_approaching_warning: true,
                    fired_at: std::time::Instant::now(),
                });
                return;
            }
        }
    }
}

pub async fn run_event_reminder_checker(store: Arc<RwLock<EventReminderStore>>) {
    let mut interval = tokio::time::interval(std::time::Duration::from_secs(30));
    loop {
        interval.tick().await;
        store.write().check_now();
    }
}

// ── Persistence ───────────────────────────────────────────────────────────────

fn reminders_path() -> std::path::PathBuf {
    cache_dir().join(REMINDERS_FILE)
}

fn load_reminders() -> Vec<EventReminder> {
    if let Ok(data) = std::fs::read_to_string(reminders_path()) {
        if let Ok(v) = serde_json::from_str::<Vec<EventReminder>>(&data) {
            return v;
        }
    }
    Vec::new()
}

fn save_reminders(reminders: &[EventReminder]) {
    let path = reminders_path();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    if let Ok(data) = serde_json::to_string_pretty(reminders) {
        let _ = std::fs::write(path, data);
    }
}
