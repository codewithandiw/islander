// focus/mod.rs — Activity tracker + reminder scheduler

pub mod activity;
pub mod reminders;

pub use activity::ActivityTracker;
pub use reminders::ReminderScheduler;

use parking_lot::RwLock;
use std::sync::Arc;

/// Background loop: ticks the activity tracker every 10 seconds.
pub async fn run_activity_loop(
    activity: Arc<RwLock<ActivityTracker>>,
    reminders: Arc<RwLock<ReminderScheduler>>,
) {
    let mut interval = tokio::time::interval(std::time::Duration::from_secs(10));
    loop {
        interval.tick().await;
        let (delta, break_detected) = {
            let mut act = activity.write();
            act.tick()
        };
        if break_detected {
            reminders.write().reset_all();
        }
        if delta > 0.0 {
            reminders.write().add_active_time(delta);
        }
    }
}
