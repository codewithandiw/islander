// lyrics/lrc_parser.rs — Parse LRC (time-synced lyrics) format

#[derive(Debug, Clone, PartialEq)]
pub struct LyricLine {
    pub time: f64, // seconds
    pub text: String,
}

pub fn parse_lrc(lrc: &str) -> Vec<LyricLine> {
    let mut lines = Vec::new();
    for raw in lrc.lines() {
        let raw = raw.trim();
        // Match [mm:ss.xx] tags.
        if !raw.starts_with('[') {
            continue;
        }
        let close = match raw.find(']') {
            Some(i) => i,
            None => continue,
        };
        let tag = &raw[1..close];
        let text = raw[close + 1..].trim().to_string();

        if let Some(time) = parse_time_tag(tag) {
            lines.push(LyricLine { time, text });
        }
    }
    lines.sort_by(|a, b| {
        a.time
            .partial_cmp(&b.time)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    // Filter out blank lines at time 0 (often just empty opening tags).
    lines
        .into_iter()
        .filter(|l| !l.text.is_empty() || l.time > 0.5)
        .collect()
}

fn parse_time_tag(tag: &str) -> Option<f64> {
    // Expected: "mm:ss.xx" or "mm:ss"
    let parts: Vec<&str> = tag.splitn(2, ':').collect();
    if parts.len() != 2 {
        return None;
    }
    let minutes: f64 = parts[0].parse().ok()?;
    let seconds: f64 = parts[1].parse().ok()?;
    Some(minutes * 60.0 + seconds)
}
