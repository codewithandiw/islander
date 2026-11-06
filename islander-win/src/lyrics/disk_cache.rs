// lyrics/disk_cache.rs — 30-day on-disk cache for lyrics

use super::{
    lrc_parser::{parse_lrc, LyricLine},
    LyricsContent,
};
use crate::settings::cache_dir;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

const CACHE_DAYS: u64 = 30;

#[derive(Debug, Serialize, Deserialize)]
struct CacheEntry {
    source: String,
    created: u64, // unix seconds
    kind: CacheKind,
    lyrics: Option<String>, // raw LRC text for Synced; None for others
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
enum CacheKind {
    Synced,
    Unsynced,
    Instrumental,
}

#[derive(Clone)]
pub struct LyricsDiskCache {
    dir: PathBuf,
}

impl LyricsDiskCache {
    pub fn new() -> Self {
        let dir = cache_dir().join("Lyrics");
        let _ = std::fs::create_dir_all(&dir);
        Self { dir }
    }

    fn path(&self, key: &str) -> PathBuf {
        // Sanitize key for use as filename.
        let name: String = key
            .chars()
            .map(|c| if c.is_alphanumeric() { c } else { '_' })
            .collect();
        self.dir.join(format!("{}.json", name))
    }

    pub fn load(&self, key: &str) -> Option<LyricsContent> {
        let data = std::fs::read_to_string(self.path(key)).ok()?;
        let entry: CacheEntry = serde_json::from_str(&data).ok()?;

        // Check expiry.
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        if now > entry.created + CACHE_DAYS * 86400 {
            return None;
        }

        Some(match entry.kind {
            CacheKind::Synced => {
                let lrc = entry.lyrics?;
                let lines = parse_lrc(&lrc);
                if lines.is_empty() {
                    return None;
                }
                LyricsContent::Synced(lines)
            }
            CacheKind::Unsynced => LyricsContent::Unsynced,
            CacheKind::Instrumental => LyricsContent::Instrumental,
        })
    }

    pub fn save(&self, content: &LyricsContent, source: &str, key: &str) {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        let entry = match content {
            LyricsContent::Synced(lines) => {
                let lrc = lines_to_lrc(lines);
                CacheEntry {
                    source: source.into(),
                    created: now,
                    kind: CacheKind::Synced,
                    lyrics: Some(lrc),
                }
            }
            LyricsContent::Unsynced => CacheEntry {
                source: source.into(),
                created: now,
                kind: CacheKind::Unsynced,
                lyrics: None,
            },
            LyricsContent::Instrumental => CacheEntry {
                source: source.into(),
                created: now,
                kind: CacheKind::Instrumental,
                lyrics: None,
            },
        };
        if let Ok(data) = serde_json::to_string(&entry) {
            let _ = std::fs::write(self.path(key), data);
        }
    }

    pub fn prune(&self) {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        let cutoff = now.saturating_sub(CACHE_DAYS * 86400);
        if let Ok(entries) = std::fs::read_dir(&self.dir) {
            for entry in entries.flatten() {
                if let Ok(data) = std::fs::read_to_string(entry.path()) {
                    if let Ok(ce) = serde_json::from_str::<CacheEntry>(&data) {
                        if ce.created < cutoff {
                            let _ = std::fs::remove_file(entry.path());
                        }
                    }
                }
            }
        }
    }
}

fn lines_to_lrc(lines: &[LyricLine]) -> String {
    lines
        .iter()
        .map(|l| {
            let mins = (l.time / 60.0) as u32;
            let secs = l.time % 60.0;
            format!("[{:02}:{:05.2}]{}", mins, secs, l.text)
        })
        .collect::<Vec<_>>()
        .join("\n")
}
