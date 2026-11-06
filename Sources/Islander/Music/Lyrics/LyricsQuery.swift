import Foundation

struct LyricLine: Equatable, Codable, Sendable {
    let time: TimeInterval
    let text: String
}

/// What a lyrics source found for a song.
enum LyricsContent: Equatable, Codable, Sendable {
    case synced([LyricLine])
    /// Lyrics exist but have no timestamps, so we cannot follow the song.
    case unsynced
    case instrumental
}

enum ProviderResult: Equatable, Sendable {
    case found(LyricsContent)
    case notFound
    /// Network error or the service is down; worth trying again later.
    case failed
}

protocol LyricsProvider: Sendable {
    var name: String { get }
    func lookup(_ query: LyricsQuery) async -> ProviderResult
}

/// The song we look for, cleaned up the way browser players need.
///
/// YouTube Music reports things like "K-391, Alan Walker, dan Ahrix" ("dan" is Indonesian
/// for "and") or "Song (Official Video)", which no lyrics service matches as-is.
struct LyricsQuery: Sendable {
    let title: String
    let artists: [String]
    /// Artist text as reported, minus "- Topic"; keeps band names like "Simon & Garfunkel" whole.
    let fullArtist: String
    let duration: TimeInterval

    var primaryArtist: String { artists.first ?? "" }
    var allArtists: String { artists.joined(separator: ", ") }
    /// True when the user plays a remix, live, acoustic or instrumental version on purpose.
    var wantsVariant: Bool { LyricsMatch.isVariant(title) }

    init(title rawTitle: String, artist rawArtist: String, duration: TimeInterval) {
        var title = LyricsMatch.cleanTitle(rawTitle)
        var artists = LyricsMatch.splitArtists(rawArtist)

        // "Artist - Title" in the title field, common for plain YouTube uploads.
        let parts = title.components(separatedBy: " - ")
        if parts.count >= 2 {
            let left = parts[0].trimmingCharacters(in: .whitespaces)
            let right = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            let leftArtists = LyricsMatch.splitArtists(left)
            if artists.isEmpty || artists.contains(where: { LyricsMatch.sameName($0, left) }) || leftArtists.contains(where: { a in artists.contains { LyricsMatch.sameName($0, a) } }) {
                title = right
                artists = leftArtists + artists.filter { a in !leftArtists.contains { LyricsMatch.sameName($0, a) } }
            }
        }

        self.title = title
        self.artists = artists
        self.fullArtist = LyricsMatch.cleanArtist(rawArtist)
        self.duration = duration
    }

    /// Stable key for caches.
    var cacheKey: String {
        LyricsMatch.normalize(primaryArtist) + "|" + LyricsMatch.normalize(title)
    }
}

enum LyricsMatch {
    private static let artistSeparators = #"\s*(?:,|&|/|;|、|\+|\s(?:x|X|×|feat\.?|ft\.?|featuring|with|and|dan|vs\.?)\s)\s*"#

    static func cleanArtist(_ artist: String) -> String {
        artist
            .replacingOccurrences(of: #"\s*-\s*Topic$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"VEVO$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// "K-391, Alan Walker, dan Ahrix" → ["K-391", "Alan Walker", "Ahrix"]
    static func splitArtists(_ artist: String) -> [String] {
        cleanArtist(artist)
            .replacingOccurrences(of: artistSeparators, with: "\u{1F}", options: .regularExpression)
            .components(separatedBy: "\u{1F}")
            // A comma before "and"/"dan" leaves the word at the start of the next name.
            .map { $0.replacingOccurrences(of: #"^\s*(?:and|dan|&)\s+"#, with: "", options: [.regularExpression, .caseInsensitive]) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func cleanTitle(_ title: String) -> String {
        let noise = #"\s*[\(\[][^\)\]]*(official|video|lyric|audio|visuali[sz]er|\bmv\b|\bhd\b|4k|remaster)[^\)\]]*[\)\]]"#
        let featuring = #"\s*[\(\[]\s*(feat\.?|ft\.?|featuring|with)\s[^\)\]]*[\)\]]"#
        return title
            .replacingOccurrences(of: noise, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: featuring, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    static func isVariant(_ title: String) -> Bool {
        title.range(of: #"\b(remix|mix|live|acoustic|instrumental|karaoke|cover|version|edit|slowed|sped up|nightcore)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Lowercased letters and digits only, accents removed: "Beyoncé!" → "beyonce".
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    static func sameName(_ a: String, _ b: String) -> Bool {
        let left = normalize(a)
        let right = normalize(b)
        return !left.isEmpty && left == right
    }

    /// The found title is the same song: equal after cleanup, and not a remix etc.
    /// unless the query asked for one.
    static func titleMatches(_ found: String, _ query: LyricsQuery) -> Bool {
        if !query.wantsVariant && isVariant(found) { return false }
        let wanted = normalize(query.title)
        let candidate = normalize(cleanTitle(found))
        return !wanted.isEmpty && (candidate == wanted || candidate.hasPrefix(wanted) && candidate.count - wanted.count <= 3)
    }

    static func sharesArtist(_ found: [String], _ query: LyricsQuery) -> Bool {
        guard !query.artists.isEmpty else { return true }
        let wanted = Set(query.artists.map(normalize))
        return found.flatMap(splitArtists).contains { wanted.contains(normalize($0)) }
    }

    /// Songs within a few seconds are the same recording. Unknown durations pass.
    static func durationMatches(_ found: TimeInterval?, _ query: LyricsQuery, tolerance: TimeInterval = 4) -> Bool {
        guard let found, found > 0, query.duration > 0 else { return true }
        return abs(found - query.duration) <= tolerance
    }
}

enum LRCParser {
    private static let tag = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)
    /// Credit lines some uploads put at the top, like "作词 : Name" (lyrics by) or "Composer: Name".
    private static let credit = try! NSRegularExpression(pattern: #"^(?:[\p{Han}\s]{1,12}|(?i:lyrics?|composer|written|producer|arranger)[^:：]{0,20})\s*[:：]"#)

    /// Parses "[mm:ss.xx] text" lines. A line may carry several time tags.
    static func parse(_ text: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in text.components(separatedBy: .newlines) {
            let range = NSRange(raw.startIndex..., in: raw)
            let matches = tag.matches(in: raw, range: range)
            guard let last = matches.last,
                  let textRange = Range(NSRange(location: last.range.upperBound, length: range.length - last.range.upperBound), in: raw)
            else { continue }
            let lyric = raw[textRange].trimmingCharacters(in: .whitespaces)
            if credit.firstMatch(in: lyric, range: NSRange(lyric.startIndex..., in: lyric)) != nil { continue }
            // Section labels like "[Verse 1]" or "(Chorus)" are not sung.
            if lyric.range(of: #"^[\[\(][^\]\)]*[\]\)]$"#, options: .regularExpression) != nil { continue }
            for match in matches {
                guard let minutes = Range(match.range(at: 1), in: raw).flatMap({ Double(raw[$0]) }),
                      let seconds = Range(match.range(at: 2), in: raw).flatMap({ Double(raw[$0]) })
                else { continue }
                lines.append(LyricLine(time: minutes * 60 + seconds, text: lyric))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }
}
