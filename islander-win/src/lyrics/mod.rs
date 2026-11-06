// lyrics/mod.rs — Lyrics fetching service (LRCLIB, disk cache, retry)

pub mod disk_cache;
pub mod lrc_parser;
pub mod lrclib;

use disk_cache::LyricsDiskCache;
use lrc_parser::LyricLine;
use lrclib::LRCLibProvider;

use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq)]
pub enum LyricsState {
    Idle,
    Loading,
    Retrying,
    Synced(Vec<LyricLine>),
    Unsynced,
    Instrumental,
    NotFound,
    Failed,
}

impl Default for LyricsState {
    fn default() -> Self {
        LyricsState::Idle
    }
}

#[derive(Debug, Clone)]
pub enum LyricsContent {
    Synced(Vec<LyricLine>),
    Unsynced,
    Instrumental,
}

pub struct LyricsService {
    pub state: LyricsState,
    pub source: Option<String>,
    pub current_key: Option<String>,
    memory_cache: HashMap<String, Option<(LyricsContent, String)>>,
    disk_cache: LyricsDiskCache,
    // Task handle stored externally via a flag.
    cancel_token: Option<tokio::sync::oneshot::Sender<()>>,
}

impl LyricsService {
    pub fn new() -> Self {
        let cache = LyricsDiskCache::new();
        // Prune in background.
        let cache2 = cache.clone();
        tokio::spawn(async move {
            cache2.prune();
        });
        Self {
            state: LyricsState::Idle,
            source: None,
            current_key: None,
            memory_cache: HashMap::new(),
            disk_cache: cache,
            cancel_token: None,
        }
    }

    pub fn update(&mut self, title: Option<&str>, artist: Option<&str>, duration: f64) {
        match title {
            None => {
                self.cancel();
                self.current_key = None;
                self.state = LyricsState::Idle;
                self.source = None;
            }
            Some(title) => {
                let query = LyricsQuery {
                    title: title.to_string(),
                    artist: artist.unwrap_or("").to_string(),
                    duration,
                };
                let key = query.cache_key();
                if Some(&key) == self.current_key.as_ref() {
                    match self.state {
                        LyricsState::Synced(_)
                        | LyricsState::Unsynced
                        | LyricsState::Instrumental
                        | LyricsState::Loading => {
                            return;
                        }
                        _ => {}
                    }
                }
                self.cancel();
                self.current_key = Some(key.clone());

                if let Some(Some(cached)) = self.memory_cache.get(&key) {
                    self.apply(Some(cached.clone()));
                    return;
                }
                self.state = LyricsState::Loading;
                self.source = None;
                self.start_fetch(key, query, 1);
            }
        }
    }

    fn cancel(&mut self) {
        if let Some(tx) = self.cancel_token.take() {
            let _ = tx.send(());
        }
    }

    fn start_fetch(&mut self, key: String, query: LyricsQuery, attempt: u32) {
        let (cancel_tx, cancel_rx) = tokio::sync::oneshot::channel::<()>();
        self.cancel_token = Some(cancel_tx);

        // We need to send results back. Use a channel stored on the service.
        // Since LyricsService is behind a Mutex in AppState, we use a global results channel.
        let (result_tx, result_rx) = tokio::sync::oneshot::channel::<FetchResult>();

        let disk_cache = self.disk_cache.clone();
        let task_key = key.clone();
        let task_query = query.clone();
        tokio::spawn(async move {
            if attempt > 1 {
                tokio::time::sleep(std::time::Duration::from_secs(3)).await;
            }
            let r = tokio::select! {
                _ = cancel_rx => FetchResult::Cancelled,
                outcome = do_lookup(&task_query, &task_key, &disk_cache) => outcome,
            };
            let _ = result_tx.send(r);
        });

        // Poll the result on the next UI tick via a stored receiver.
        PENDING_LYRICS.lock().push(PendingFetch {
            key,
            query,
            attempt,
            rx: result_rx,
        });
    }

    fn apply(&mut self, content: Option<(LyricsContent, String)>) {
        match content {
            None => {
                self.state = LyricsState::NotFound;
                self.source = None;
            }
            Some((LyricsContent::Synced(lines), src)) => {
                self.state = LyricsState::Synced(lines);
                self.source = Some(src);
            }
            Some((LyricsContent::Unsynced, src)) => {
                self.state = LyricsState::Unsynced;
                self.source = Some(src);
            }
            Some((LyricsContent::Instrumental, src)) => {
                self.state = LyricsState::Instrumental;
                self.source = Some(src);
            }
        }
    }

    /// Call this every frame to drain completed fetch results.
    pub fn poll_results(&mut self) {
        let mut pending = PENDING_LYRICS.lock();
        let mut keep = Vec::new();
        for mut pf in pending.drain(..) {
            if Some(&pf.key) != self.current_key.as_ref() {
                // Stale.
                continue;
            }
            match pf.rx.try_recv() {
                Ok(FetchResult::Found(content, src)) => {
                    let entry = Some((content.clone(), src.clone()));
                    self.memory_cache.insert(pf.key, entry.clone());
                    self.apply(entry);
                }
                Ok(FetchResult::NotFound) => {
                    self.apply(None);
                }
                Ok(FetchResult::Failed) if pf.attempt < 3 => {
                    self.state = LyricsState::Retrying;
                    self.start_fetch(pf.key, pf.query, pf.attempt + 1);
                }
                Ok(FetchResult::Failed) => {
                    self.state = LyricsState::Failed;
                }
                Ok(FetchResult::Cancelled) => {}
                Err(tokio::sync::oneshot::error::TryRecvError::Empty) => {
                    keep.push(pf);
                }
                Err(_) => {}
            }
        }
        *pending = keep;
    }

    /// Binary search for the lyric line at `time` seconds.
    pub fn line_index(lines: &[LyricLine], time: f64) -> Option<usize> {
        let mut low = 0i32;
        let mut high = lines.len() as i32 - 1;
        let mut result = None;
        while low <= high {
            let mid = (low + high) / 2;
            if lines[mid as usize].time <= time {
                result = Some(mid as usize);
                low = mid + 1;
            } else {
                high = mid - 1;
            }
        }
        result
    }
}

// Global pending fetch queue (accessed from async tasks + UI poll).
use once_cell::sync::Lazy;
use parking_lot::Mutex;

struct PendingFetch {
    key: String,
    query: LyricsQuery,
    attempt: u32,
    rx: tokio::sync::oneshot::Receiver<FetchResult>,
}

enum FetchResult {
    Found(LyricsContent, String),
    NotFound,
    Failed,
    Cancelled,
}

static PENDING_LYRICS: Lazy<Mutex<Vec<PendingFetch>>> = Lazy::new(|| Mutex::new(Vec::new()));

// ── LyricsQuery ───────────────────────────────────────────────────────────────

#[derive(Clone, Debug)]
pub struct LyricsQuery {
    pub title: String,
    pub artist: String,
    pub duration: f64,
}

impl LyricsQuery {
    pub fn cache_key(&self) -> String {
        // Clean and normalize title and artist to avoid cache misses for minor variations.
        let (clean_title, clean_artist) = lrclib::parse_title_and_artist(&self.title, &self.artist);
        format!(
            "{}\x1f{}",
            clean_artist.to_lowercase(),
            clean_title.to_lowercase()
        )
    }

    pub fn normalize_artist(&self) -> String {
        // Split "A feat. B", "A & B", "A, B, dan C" to primary artist.
        let separators = [" feat.", " ft.", " featuring", " &", ", ", " dan "];
        let mut a = self.artist.clone();
        for sep in separators {
            if let Some(idx) = a.to_lowercase().find(sep) {
                a = a[..idx].to_string();
                break;
            }
        }
        a.trim().to_string()
    }
}

async fn do_lookup(query: &LyricsQuery, key: &str, disk_cache: &LyricsDiskCache) -> FetchResult {
    // Disk cache first.
    if let Some(content) = disk_cache.load(key) {
        return FetchResult::Found(content, "cache".into());
    }
    // Try LRCLIB.
    match LRCLibProvider::lookup(query).await {
        Ok(Some(content)) => {
            disk_cache.save(&content, "LRCLIB", key);
            FetchResult::Found(content, "LRCLIB".into())
        }
        Ok(None) => FetchResult::NotFound,
        Err(_) => FetchResult::Failed,
    }
}
