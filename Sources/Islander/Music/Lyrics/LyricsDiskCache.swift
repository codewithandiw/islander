import CryptoKit
import Foundation

/// Keeps found lyrics in ~/Library/Caches/<bundle id>/Lyrics for 30 days, so replayed
/// songs load instantly and still work offline or while a lyrics service is down.
struct LyricsDiskCache: Sendable {
    static let maxAge: TimeInterval = 30 * 24 * 3600

    private struct Entry: Codable {
        let savedAt: Date
        let source: String
        let content: LyricsContent
    }

    let directory: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "Islander"
        directory = caches.appendingPathComponent(bundleID, isDirectory: true).appendingPathComponent("Lyrics", isDirectory: true)
    }

    func load(_ key: String) -> LyricsContent? {
        let url = file(for: key)
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry.self, from: data)
        else { return nil }
        guard Date().timeIntervalSince(entry.savedAt) < Self.maxAge else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return entry.content
    }

    func save(_ content: LyricsContent, source: String, key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entry = Entry(savedAt: .now, source: source, content: content)
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: file(for: key), options: .atomic)
        }
    }

    /// Deletes entries older than `maxAge`.
    func prune() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for url in files {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(modified) >= Self.maxAge {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Hashed file names keep song titles out of the file system and avoid bad characters.
    private func file(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest).appendingPathExtension("json")
    }
}
