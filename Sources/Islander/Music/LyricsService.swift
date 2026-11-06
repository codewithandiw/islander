import Foundation

/// Finds lyrics for the current track. Sources are tried in order; results are kept in
/// memory and on disk (30 days), so replayed songs still work while a source is down.
@MainActor
final class LyricsService: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        /// Every source failed (offline or down); trying again shortly.
        case retrying
        case synced([LyricLine])
        case unsynced
        case instrumental
        case notFound
        case failed
    }

    @Published private(set) var state: State = .idle
    /// Name of the source that provided the current lyrics, for credit.
    @Published private(set) var source: String?

    private static let maxAttempts = 3
    private static let retryDelay: Duration = .seconds(15)

    private let providers: [LyricsProvider]
    private let diskCache = LyricsDiskCache()
    private var memoryCache: [String: (content: LyricsContent?, source: String?)] = [:]
    private var currentKey: String?
    private var task: Task<Void, Never>?

    init(providers: [LyricsProvider] = [LRCLibProvider()]) {
        self.providers = providers
        let cache = diskCache
        Task.detached(priority: .background) { cache.prune() }
    }

    func update(for nowPlaying: NowPlaying?) {
        guard let nowPlaying else {
            task?.cancel()
            currentKey = nil
            state = .idle
            source = nil
            return
        }
        let query = LyricsQuery(title: nowPlaying.title, artist: nowPlaying.artist, duration: nowPlaying.duration)
        let key = query.cacheKey
        guard key != currentKey else { return }
        currentKey = key
        task?.cancel()

        if let cached = memoryCache[key] {
            show(cached.content, source: cached.source)
            return
        }
        state = .loading
        source = nil
        fetch(key: key, query: query, attempt: 1)
    }

    private func fetch(key: String, query: LyricsQuery, attempt: Int) {
        let providers = providers
        let diskCache = diskCache
        task = Task { [weak self] in
            if attempt > 1 { try? await Task.sleep(for: Self.retryDelay) }
            guard !Task.isCancelled else { return }

            let outcome = await Self.lookup(query, key: key, providers: providers, diskCache: diskCache)
            guard !Task.isCancelled, let self, key == self.currentKey else { return }

            switch outcome {
            case .found(let content, let source):
                self.memoryCache[key] = (content, source)
                self.show(content, source: source)
            case .notFound:
                self.memoryCache[key] = (nil, nil)
                self.show(nil, source: nil)
            case .failed where attempt < Self.maxAttempts:
                self.state = .retrying
                self.fetch(key: key, query: query, attempt: attempt + 1)
            case .failed:
                // Not cached, so the next play of this song tries again.
                self.state = .failed
            }
        }
    }

    private enum Outcome {
        case found(LyricsContent, source: String)
        case notFound
        case failed
    }

    /// Disk cache first, then each source in order. Reports `.failed` only when no source
    /// found the song and at least one could not be reached.
    private nonisolated static func lookup(
        _ query: LyricsQuery,
        key: String,
        providers: [LyricsProvider],
        diskCache: LyricsDiskCache
    ) async -> Outcome {
        if let cached = diskCache.load(key) {
            return .found(cached, source: "cache")
        }
        var anyFailed = false
        for provider in providers {
            if Task.isCancelled { return .failed }
            switch await provider.lookup(query) {
            case .found(let content):
                diskCache.save(content, source: provider.name, key: key)
                return .found(content, source: provider.name)
            case .notFound:
                continue
            case .failed:
                anyFailed = true
            }
        }
        return anyFailed ? .failed : .notFound
    }

    private func show(_ content: LyricsContent?, source: String?) {
        self.source = source
        switch content {
        case .synced(let lines): state = .synced(lines)
        case .unsynced: state = .unsynced
        case .instrumental: state = .instrumental
        case nil: state = .notFound
        }
    }

    #if DEBUG
    func injectForSnapshot(_ state: State) {
        self.state = state
    }

    /// Used by `Islander --lyrics`: runs every source without caches and reports each result.
    nonisolated static func debugLookup(title: String, artist: String, duration: TimeInterval) async -> String {
        let query = LyricsQuery(title: title, artist: artist, duration: duration)
        var report = "query: title=\"\(query.title)\" artists=\(query.artists) full=\"\(query.fullArtist)\"\n"
        for provider: LyricsProvider in [LRCLibProvider()] {
            let result = await provider.lookup(query)
            switch result {
            case .found(.synced(let lines)):
                report += "\(provider.name): synced, \(lines.count) lines, first: \(lines.first?.text ?? "")\n"
            default:
                report += "\(provider.name): \(result)\n"
            }
        }
        return report
    }
    #endif

    /// Index of the line being sung at `time`, or nil before the first line.
    static func lineIndex(in lines: [LyricLine], at time: TimeInterval) -> Int? {
        var low = 0
        var high = lines.count - 1
        var result: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= time {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }
}
