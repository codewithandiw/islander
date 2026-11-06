import AppKit
import SwiftUI

/// A snapshot of what the system "Now Playing" reports (Spotify, Apple Music, browser tabs, …).
struct NowPlaying: Equatable {
    var sourceBundleID: String
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var duration: TimeInterval
    /// Elapsed time as of `timestamp`.
    var elapsed: TimeInterval
    var timestamp: Date
    var playbackRate: Double

    var trackKey: String { "\(artist)\u{1F}\(title)" }

    func position(at date: Date = .now) -> TimeInterval {
        var value = elapsed
        if isPlaying {
            value += date.timeIntervalSince(timestamp) * (playbackRate > 0 ? playbackRate : 1)
        }
        value = max(value, 0)
        return duration > 0 ? min(value, duration) : value
    }

    func settingPlaying(_ playing: Bool, at date: Date = .now) -> NowPlaying {
        var copy = self
        copy.elapsed = position(at: date)
        copy.timestamp = date
        copy.isPlaying = playing
        copy.playbackRate = playing ? 1 : 0
        return copy
    }

    func seeking(to seconds: TimeInterval, at date: Date = .now) -> NowPlaying {
        var copy = self
        copy.elapsed = seconds
        copy.timestamp = date
        return copy
    }
}

extension NowPlaying {
    /// Builds a snapshot from the adapter's JSON payload (started with `--micros`).
    init?(payload: [String: Any]) {
        guard let bundle = payload["bundleIdentifier"] as? String,
              let title = payload["title"] as? String, !title.isEmpty,
              let playing = payload["playing"] as? Bool
        else { return nil }

        func number(_ key: String) -> Double? { (payload[key] as? NSNumber)?.doubleValue }

        self.sourceBundleID = (payload["parentApplicationBundleIdentifier"] as? String) ?? bundle
        self.title = title
        self.artist = payload["artist"] as? String ?? ""
        self.album = payload["album"] as? String ?? ""
        self.isPlaying = playing
        self.duration = (number("durationMicros") ?? 0) / 1_000_000
        self.elapsed = (number("elapsedTimeMicros") ?? 0) / 1_000_000
        self.timestamp = number("timestampEpochMicros").map { Date(timeIntervalSince1970: $0 / 1_000_000) } ?? .now
        self.playbackRate = number("playbackRate") ?? (playing ? 1 : 0)
    }
}

/// Reads now-playing information through the bundled mediaremote-adapter.
///
/// macOS 15.4+ only lets Apple-signed binaries use MediaRemote, so the adapter runs
/// inside `/usr/bin/perl` and streams JSON lines to us.
@MainActor
final class NowPlayingService: ObservableObject {
    enum Status: Equatable {
        case starting
        case running
        case unavailable(String)
    }

    /// IDs from the adapter's `send` command.
    enum Command: Int {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = .white
    @Published private(set) var sourceIcon: NSImage?
    @Published private(set) var status: Status = .starting

    private let adapter = AdapterPaths.locate()
    private var process: Process?
    private var state: [String: Any] = [:]
    private var lineBuffer = Data()
    private var artworkHash: Int?
    private var shouldRun = false
    private var restartDelay: TimeInterval = 1
    private var launchedAt = Date()

    func start() {
        shouldRun = true
        launch()
    }

    func stop() {
        shouldRun = false
        process?.terminate()
        process = nil
    }

    func send(_ command: Command) {
        runAdapter(["send", String(command.rawValue)])
        guard let current = nowPlaying else { return }
        switch command {
        case .togglePlayPause: nowPlaying = current.settingPlaying(!current.isPlaying)
        case .play: nowPlaying = current.settingPlaying(true)
        case .pause: nowPlaying = current.settingPlaying(false)
        case .nextTrack, .previousTrack: break
        }
    }

    func seek(to seconds: TimeInterval) {
        runAdapter(["seek", String(Int64(max(seconds, 0) * 1_000_000))])
        nowPlaying = nowPlaying?.seeking(to: seconds)
    }

    #if DEBUG
    /// Used by the snapshot tool to render the UI with sample data.
    func injectForSnapshot(_ track: NowPlaying?, artwork: NSImage? = nil) {
        nowPlaying = track
        self.artwork = artwork
        accent = artwork?.islandAccentColor().map(Color.init(nsColor:)) ?? .pink
        status = .running
    }
    #endif

    // MARK: - Process

    private func launch() {
        guard shouldRun, process == nil else { return }
        guard let adapter else {
            status = .unavailable("Media adapter is missing from the app bundle. Build the app with scripts/build-app.sh.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [adapter.script.path, adapter.framework.path, "stream", "--micros", "--debounce=80"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { self?.consume(data) }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.processDidExit() }
        }

        do {
            try process.run()
            self.process = process
            launchedAt = .now
        } catch {
            status = .unavailable("Could not start the media adapter: \(error.localizedDescription)")
            scheduleRestart()
        }
    }

    private func processDidExit() {
        process = nil
        lineBuffer.removeAll()
        guard shouldRun else { return }
        if Date().timeIntervalSince(launchedAt) < 3, status != .running {
            status = .unavailable("The media adapter stopped right after starting. A macOS update may have broken it.")
        }
        scheduleRestart()
    }

    private func scheduleRestart() {
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, 30)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.launch() }
    }

    /// Fire-and-forget adapter call, used for playback commands.
    private func runAdapter(_ arguments: [String]) {
        guard let adapter else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [adapter.script.path, adapter.framework.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // MARK: - Parsing

    private func consume(_ data: Data) {
        lineBuffer.append(data)
        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            let line = lineBuffer[lineBuffer.startIndex..<newline]
            handle(line: Data(line))
            lineBuffer.removeSubrange(lineBuffer.startIndex...newline)
        }
    }

    private func handle(line: Data) {
        guard !line.isEmpty,
              let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              message["type"] as? String == "data",
              let payload = message["payload"] as? [String: Any]
        else { return }

        let isDiff = message["diff"] as? Bool ?? false
        if !isDiff {
            state.removeAll()
            if payload["artworkData"] == nil { setArtwork(nil) }
        }
        for (key, value) in payload {
            if key == "artworkData" {
                setArtwork(value as? String)
            } else if value is NSNull {
                state.removeValue(forKey: key)
            } else {
                state[key] = value
            }
        }

        let next = NowPlaying(payload: state)
        if next?.sourceBundleID != nowPlaying?.sourceBundleID {
            sourceIcon = next.flatMap { Self.appIcon(bundleID: $0.sourceBundleID) }
        }
        if next == nil { setArtwork(nil) }
        if next != nowPlaying { nowPlaying = next }
        status = .running
        restartDelay = 1
    }

    private func setArtwork(_ base64: String?) {
        guard let base64, !base64.isEmpty else {
            if artworkHash != nil {
                artworkHash = nil
                artwork = nil
                accent = .white
            }
            return
        }
        let hash = base64.hashValue
        guard hash != artworkHash else { return }
        artworkHash = hash
        guard let data = Data(base64Encoded: base64), let image = NSImage(data: data) else { return }
        artwork = image
        accent = image.islandAccentColor().map(Color.init(nsColor:)) ?? .white
    }

    private static func appIcon(bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Locations of the adapter files inside Islander.app.
private struct AdapterPaths {
    let script: URL
    let framework: URL

    static func locate() -> AdapterPaths? {
        let bundle = Bundle.main
        guard let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let framework = bundle.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework"),
              FileManager.default.fileExists(atPath: framework.path)
        else { return nil }
        return AdapterPaths(script: script, framework: framework)
    }
}
