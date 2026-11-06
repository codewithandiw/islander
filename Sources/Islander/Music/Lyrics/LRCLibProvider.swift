import Foundation

/// LRCLIB (https://lrclib.net): free, open lyrics database, no API key.
struct LRCLibProvider: LyricsProvider {
    let name = "LRCLIB"

    private struct Record: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private static let baseURL = URL(string: "https://lrclib.net/api")!

    /// Tries several searches and stops at the first good match. One failed request
    /// (for example "server busy") does not stop the lookup.
    func lookup(_ query: LyricsQuery) async -> ProviderResult {
        var anySucceeded = false

        // Search only reads LRCLIB's own database, so it is fast; try it first.
        var artistVariants = [query.fullArtist, query.primaryArtist, ""]
        artistVariants = artistVariants.enumerated().filter { index, value in
            !artistVariants[..<index].contains(value)
        }.map(\.element)

        for artist in artistVariants {
            if Task.isCancelled { return .failed }
            guard let records = try? await search(title: query.title, artist: artist) else { continue }
            anySucceeded = true
            if let content = best(records, for: query) { return .found(content) }
        }

        // Exact lookup may ask outside sources: slower and more often "busy".
        do {
            let record = try await get(title: query.title, artist: query.primaryArtist, duration: query.duration)
            anySucceeded = true
            if let record, let content = content(from: record) { return .found(content) }
        } catch {
            // Counted as a failure only if every other request failed too.
        }
        return anySucceeded ? .notFound : .failed
    }

    // MARK: - Requests

    private func search(title: String, artist: String) async throws -> [Record] {
        var items = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty { items.append(URLQueryItem(name: "artist_name", value: artist)) }
        let (data, response) = try await URLSession.shared.data(for: request(path: "search", items: items))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([Record].self, from: data)
    }

    /// Returns `.some(nil)` when LRCLIB answered "not found".
    private func get(title: String, artist: String, duration: TimeInterval) async throws -> Record? {
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        let (data, response) = try await URLSession.shared.data(for: request(path: "get", items: items))
        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 404 { return nil }
        guard status == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Record.self, from: data)
    }

    private func request(path: String, items: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = items
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.setValue("Islander/1.1 (macOS notch music app)", forHTTPHeaderField: "User-Agent")
        return request
    }

    // MARK: - Matching

    private func best(_ records: [Record], for query: LyricsQuery) -> LyricsContent? {
        let matches = records.filter { record in
            LyricsMatch.titleMatches(record.trackName ?? "", query)
                && LyricsMatch.sharesArtist([record.artistName ?? ""], query)
                && LyricsMatch.durationMatches(record.duration, query)
        }
        // Prefer synced lyrics, then the closest length.
        let ranked = matches.sorted { a, b in
            let aSynced = !(a.syncedLyrics ?? "").isEmpty
            let bSynced = !(b.syncedLyrics ?? "").isEmpty
            if aSynced != bSynced { return aSynced }
            return distance(a, query) < distance(b, query)
        }
        return ranked.lazy.compactMap(content(from:)).first
    }

    private func distance(_ record: Record, _ query: LyricsQuery) -> TimeInterval {
        guard let duration = record.duration, query.duration > 0 else { return 999 }
        return abs(duration - query.duration)
    }

    private func content(from record: Record) -> LyricsContent? {
        if record.instrumental == true { return .instrumental }
        if let synced = record.syncedLyrics {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = record.plainLyrics, !plain.isEmpty { return .unsynced }
        return nil
    }
}
