// main.rs — Islander for Windows entry point

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod focus;
mod lyrics;
mod now_playing;
mod reminder;
mod settings;
mod shelf;
mod sound;
mod ui;
mod visualizer;
mod window;

use eframe::egui;
use parking_lot::RwLock;
use std::sync::Arc;

pub use focus::{ActivityTracker, ReminderScheduler};
pub use lyrics::LyricsService;
pub use now_playing::NowPlayingState;
pub use reminder::EventReminderStore;
pub use settings::AppSettings;
pub use shelf::ShelfStore;
pub use sound::SoundPlayer;
pub use visualizer::AudioSpectrum;

fn main() {
    env_logger::init();

    let rt = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .expect("tokio runtime");

    rt.block_on(async_main());
}

async fn async_main() {
    let settings = Arc::new(RwLock::new(AppSettings::load()));
    let now_playing = Arc::new(RwLock::new(NowPlayingState::default()));
    let lyrics = Arc::new(tokio::sync::Mutex::new(LyricsService::new()));
    let spectrum = Arc::new(RwLock::new(AudioSpectrum::default()));
    let shelf = Arc::new(RwLock::new(ShelfStore::new()));
    let event_reminders = Arc::new(RwLock::new(EventReminderStore::load()));
    let activity = Arc::new(RwLock::new(ActivityTracker::new(Arc::clone(&settings))));
    let reminders = Arc::new(RwLock::new(ReminderScheduler::new(Arc::clone(&settings))));

    let app_state = AppState {
        settings: Arc::clone(&settings),
        now_playing: Arc::clone(&now_playing),
        lyrics: Arc::clone(&lyrics),
        spectrum: Arc::clone(&spectrum),
        shelf: Arc::clone(&shelf),
        event_reminders: Arc::clone(&event_reminders),
        activity: Arc::clone(&activity),
        reminders: Arc::clone(&reminders),
    };

    // Start background services
    {
        let np = Arc::clone(&now_playing);
        let lyr = Arc::clone(&lyrics);
        let spec = Arc::clone(&spectrum);
        let set = Arc::clone(&settings);
        let rem = Arc::clone(&reminders);
        let act = Arc::clone(&activity);
        let evrem = Arc::clone(&event_reminders);

        tokio::spawn(now_playing::run_smtc_watcher(np.clone(), lyr.clone()));
        tokio::spawn(visualizer::run_wasapi_loopback(
            spec.clone(),
            set.clone(),
            np.clone(),
        ));
        tokio::spawn(focus::run_activity_loop(act.clone(), rem.clone()));
        tokio::spawn(reminder::run_event_reminder_checker(evrem.clone()));
    }

    let initial_pos = window::get_initial_top_center_pos(760.0);

    // Run egui on the main thread
    let native_options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([760.0, 560.0])
            .with_position(initial_pos)
            .with_decorations(false)
            .with_transparent(true)
            .with_always_on_top()
            .with_taskbar(false)
            .with_mouse_passthrough(false)
            .with_title("Islander"),
        ..Default::default()
    };

    eframe::run_native(
        "Islander",
        native_options,
        Box::new(|cc| Ok(Box::new(ui::IslanderApp::new(cc, app_state)))),
    )
    .expect("eframe run");
}

/// All shared mutable state threaded through the app.
#[derive(Clone)]
pub struct AppState {
    pub settings: Arc<RwLock<AppSettings>>,
    pub now_playing: Arc<RwLock<NowPlayingState>>,
    pub lyrics: Arc<tokio::sync::Mutex<LyricsService>>,
    pub spectrum: Arc<RwLock<AudioSpectrum>>,
    pub shelf: Arc<RwLock<ShelfStore>>,
    pub event_reminders: Arc<RwLock<EventReminderStore>>,
    pub activity: Arc<RwLock<ActivityTracker>>,
    pub reminders: Arc<RwLock<ReminderScheduler>>,
}
