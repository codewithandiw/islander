// lyrics/lrclib.rs — LRCLIB.net provider with metadata cleaning and search fallback

use super::lrc_parser::parse_lrc;
use super::{LyricsContent, LyricsQuery};
use once_cell::sync::Lazy;
use reqwest::Client;
use serde::Deserialize;

static CLIENT: Lazy<Client> = Lazy::new(|| {
    Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .user_agent("Islander/1.0 (https://github.com/islander)")
        .build()
        .expect("HTTP client")
});

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LRCLibRecord {
    #[allow(dead_code)]
    id: Option<i64>,
    #[allow(dead_code)]
    track_name: Option<String>,
    artist_name: Option<String>,
    duration: Option<f64>,
    instrumental: Option<bool>,
    plain_lyrics: Option<String>,
    synced_lyrics: Option<String>,
}

impl LRCLibRecord {
    fn into_lyrics_content(self) -> Option<LyricsContent> {
        if self.instrumental.unwrap_or(false) {
            return Some(LyricsContent::Instrumental);
        }
        if let Some(synced) = self.synced_lyrics {
            if !synced.trim().is_empty() {
                let lines = parse_lrc(&synced);
                if !lines.is_empty() {
                    return Some(LyricsContent::Synced(lines));
                }
            }
        }
        if let Some(plain) = self.plain_lyrics {
            if !plain.trim().is_empty() {
                return Some(LyricsContent::Unsynced);
            }
        }
        None
    }
}

pub struct LRCLibProvider;

impl LRCLibProvider {
    pub async fn lookup(query: &LyricsQuery) -> Result<Option<LyricsContent>, reqwest::Error> {
        let (clean_title, clean_artist) = parse_title_and_artist(&query.title, &query.artist);

        // Build candidate artist names to try
        let mut artist_candidates = Vec::new();
        if !clean_artist.is_empty() {
            artist_candidates.push(clean_artist.clone());
        }
        let norm_artist = clean_artist_str(&query.normalize_artist());
        if !norm_artist.is_empty() && !artist_candidates.contains(&norm_artist) {
            artist_candidates.push(norm_artist);
        }
        let raw_artist_clean = clean_artist_str(&query.artist);
        if !raw_artist_clean.is_empty() && !artist_candidates.contains(&raw_artist_clean) {
            artist_candidates.push(raw_artist_clean);
        }

        // 1. Try exact /api/get if duration is valid and artist is available
        if query.duration >= 1.0 && query.duration <= 3600.0 {
            for artist in &artist_candidates {
                let url = format!(
                    "https://lrclib.net/api/get?track_name={}&artist_name={}&duration={}",
                    urlenc(&clean_title),
                    urlenc(artist),
                    query.duration.round() as u32,
                );

                if let Ok(resp) = CLIENT.get(&url).send().await {
                    if resp.status().is_success() {
                        if let Ok(record) = resp.json::<LRCLibRecord>().await {
                            if let Some(content) = record.into_lyrics_content() {
                                return Ok(Some(content));
                            }
                        }
                    }
                }
            }
        }

        // 2. Try /api/search?track_name=...&artist_name=...
        for artist in &artist_candidates {
            let url = format!(
                "https://lrclib.net/api/search?track_name={}&artist_name={}",
                urlenc(&clean_title),
                urlenc(artist),
            );

            if let Ok(resp) = CLIENT.get(&url).send().await {
                if resp.status().is_success() {
                    if let Ok(records) = resp.json::<Vec<LRCLibRecord>>().await {
                        if let Some(content) = pick_best_record(records, query.duration) {
                            return Ok(Some(content));
                        }
                    }
                }
            }
        }

        // 3. Try /api/search?q={artist} {title}
        let q_string = if !clean_artist.is_empty() {
            format!("{} {}", clean_artist, clean_title)
        } else {
            clean_title.clone()
        };
        let url = format!("https://lrclib.net/api/search?q={}", urlenc(&q_string));
        if let Ok(resp) = CLIENT.get(&url).send().await {
            if resp.status().is_success() {
                if let Ok(records) = resp.json::<Vec<LRCLibRecord>>().await {
                    if let Some(content) = pick_best_record(records, query.duration) {
                        return Ok(Some(content));
                    }
                }
            }
        }

        // 4. Try /api/search?track_name={title}
        let url = format!("https://lrclib.net/api/search?track_name={}", urlenc(&clean_title));
        if let Ok(resp) = CLIENT.get(&url).send().await {
            if resp.status().is_success() {
                if let Ok(records) = resp.json::<Vec<LRCLibRecord>>().await {
                    let filtered: Vec<LRCLibRecord> = if !clean_artist.is_empty() {
                        let ca_lower = clean_artist.to_lowercase();
                        records
                            .into_iter()
                            .filter(|r| {
                                r.artist_name
                                    .as_ref()
                                    .map(|a| a.to_lowercase().contains(&ca_lower) || ca_lower.contains(&a.to_lowercase()))
                                    .unwrap_or(false)
                            })
                            .collect()
                    } else {
                        records
                    };
                    if let Some(content) = pick_best_record(filtered, query.duration) {
                        return Ok(Some(content));
                    }
                }
            }
        }

        Ok(None)
    }
}

fn pick_best_record(records: Vec<LRCLibRecord>, target_duration: f64) -> Option<LyricsContent> {
    if records.is_empty() {
        return None;
    }

    let mut with_synced = Vec::new();
    let mut others = Vec::new();

    for r in records {
        if r.synced_lyrics.as_ref().map(|s| !s.trim().is_empty()).unwrap_or(false) {
            with_synced.push(r);
        } else {
            others.push(r);
        }
    }

    if !with_synced.is_empty() {
        if target_duration > 0.0 {
            with_synced.sort_by(|a, b| {
                let diff_a = (a.duration.unwrap_or(0.0) - target_duration).abs();
                let diff_b = (b.duration.unwrap_or(0.0) - target_duration).abs();
                diff_a.partial_cmp(&diff_b).unwrap_or(std::cmp::Ordering::Equal)
            });
        }
        for r in with_synced {
            if let Some(content) = r.into_lyrics_content() {
                return Some(content);
            }
        }
    }

    for r in others {
        if let Some(content) = r.into_lyrics_content() {
            return Some(content);
        }
    }

    None
}

pub fn clean_title_str(title: &str) -> String {
    let mut t = title.trim().to_string();

    let noise = [
        "official music video",
        "official video",
        "music video",
        "official lyric video",
        "lyric video",
        "official visualizer",
        "visualizer",
        "official audio",
        "audio video",
        "official",
        "audio",
        "lyrics",
        "video clip",
        "clip officiel",
        "video",
        "4k",
        "hd",
        "remastered",
        "live",
    ];

    loop {
        let mut replaced = false;
        let lower = t.to_lowercase();
        for &pat in &noise {
            for (open, close) in [('(', ')'), ('[', ']'), ('{', '}')] {
                let target = format!("{}{}{}", open, pat, close);
                if let Some(pos) = lower.find(&target) {
                    t.replace_range(pos..pos + target.len(), "");
                    t = t.trim().to_string();
                    replaced = true;
                    break;
                }
            }
            if replaced {
                break;
            }
        }
        if !replaced {
            break;
        }
    }

    if let Some(pos) = t.find('|') {
        t = t[..pos].trim().to_string();
    }
    if let Some(pos) = t.find("//") {
        t = t[..pos].trim().to_string();
    }

    t = t.trim().to_string();
    if (t.starts_with('"') && t.ends_with('"')) || (t.starts_with('\'') && t.ends_with('\'')) {
        if t.len() >= 2 {
            t = t[1..t.len() - 1].trim().to_string();
        }
    }

    t.trim().to_string()
}

pub fn clean_artist_str(artist: &str) -> String {
    let mut a = artist.trim().to_string();

    let suffixes = [
        " - topic",
        "- topic",
        " topic",
        " - official",
        " official",
        " - vevo",
        " vevo",
    ];

    for s in &suffixes {
        let lower = a.to_lowercase();
        if let Some(stripped) = lower.strip_suffix(s) {
            a = a[..stripped.len()].trim().to_string();
            break;
        }
    }

    a.trim().to_string()
}

pub fn parse_title_and_artist(raw_title: &str, raw_artist: &str) -> (String, String) {
    let mut title = clean_title_str(raw_title);
    let mut artist = clean_artist_str(raw_artist);

    let is_generic_artist = artist.is_empty()
        || artist.eq_ignore_ascii_case("youtube")
        || artist.eq_ignore_ascii_case("youtube music")
        || artist.eq_ignore_ascii_case("google chrome")
        || artist.eq_ignore_ascii_case("chrome")
        || artist.eq_ignore_ascii_case("unknown")
        || artist.eq_ignore_ascii_case("unknown artist");

    if is_generic_artist && title.contains(" - ") {
        let parts: Vec<&str> = title.splitn(2, " - ").collect();
        if parts.len() == 2 && !parts[0].trim().is_empty() && !parts[1].trim().is_empty() {
            artist = clean_artist_str(parts[0]);
            title = clean_title_str(parts[1]);
        }
    }

    (title, artist)
}

fn urlenc(s: &str) -> String {
    let mut out = String::new();
    for byte in s.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(byte as char);
            }
            b' ' => out.push('+'),
            other => out.push_str(&format!("%{:02X}", other)),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cleaning() {
        let (t, a) = parse_title_and_artist("Penyangkalan", "for Revenge - Topic");
        assert_eq!(t, "Penyangkalan");
        assert_eq!(a, "for Revenge");

        let (t, a) = parse_title_and_artist(
            "for Revenge - Penyangkalan (Official Music Video)",
            "YouTube Music",
        );
        assert_eq!(t, "Penyangkalan");
        assert_eq!(a, "for Revenge");

        let (t, a) = parse_title_and_artist("\"Penyangkalan\" [Official Audio]", "for Revenge");
        assert_eq!(t, "Penyangkalan");
        assert_eq!(a, "for Revenge");
    }
}
