import SwiftUI

struct MusicTabView: View {
    @EnvironmentObject private var nowPlaying: NowPlayingService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var lyrics: LyricsService

    /// Spins while looking up lyrics, dances while playing, rests when paused.
    private func mascotMood(isPlaying: Bool) -> MascotMood {
        guard isPlaying else { return .idle }
        switch lyrics.state {
        case .loading, .retrying: return .spinning
        default: return .dancing
        }
    }

    var body: some View {
        if let track = nowPlaying.nowPlaying {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    ArtworkView(image: nowPlaying.artwork, size: 76, cornerRadius: 14, badge: nowPlaying.sourceIcon)

                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(track.title)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Text(track.artist.isEmpty ? track.album : track.artist)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                        ProgressScrubber(track: track, accent: nowPlaying.accent) { nowPlaying.seek(to: $0) }
                        PlaybackControls(isPlaying: track.isPlaying) { nowPlaying.send($0) }
                    }

                    VStack(spacing: 6) {
                        if settings.showMascot {
                            DancingMascot(mood: mascotMood(isPlaying: track.isPlaying), size: 54, spinsOnTap: true)
                        }
                        if settings.showVisualizer {
                            SpectrumBars(barCount: 10, color: nowPlaying.accent, isPlaying: track.isPlaying)
                                .frame(width: 70, height: 22)
                        }
                    }
                    .frame(width: 76)
                }

                if settings.showLyrics {
                    CurrentLyricLine(font: .system(size: 14, weight: .semibold), showsNextLine: true)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        } else {
            NothingPlayingView()
        }
    }
}

private struct NothingPlayingView: View {
    @EnvironmentObject private var nowPlaying: NowPlayingService
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 18) {
            if settings.showMascot {
                // Confused when media detection is broken, asleep when simply idle.
                MascotView(mood: isUnavailable ? .confused : .sleeping, color: settings.mascotColor.color, energy: 0, size: 70)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing playing")
                    .font(.system(size: 15, weight: .semibold))
                if case .unavailable(let reason) = nowPlaying.status {
                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                } else {
                    Text("Play something in Spotify, Apple Music or YouTube Music and it shows up here.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private var isUnavailable: Bool {
        if case .unavailable = nowPlaying.status { return true }
        return false
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat
    var badge: NSImage? = nil

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [.purple.opacity(0.7), .blue.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if let badge {
                Image(nsImage: badge)
                    .resizable()
                    .frame(width: size * 0.36, height: size * 0.36)
                    .offset(x: size * 0.08, y: size * 0.08)
            }
        }
    }
}

struct ProgressScrubber: View {
    let track: NowPlaying
    let accent: Color
    let onSeek: (TimeInterval) -> Void

    @State private var dragPosition: TimeInterval?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = dragPosition ?? track.position(at: context.date)
            let fraction = track.duration > 0 ? position / track.duration : 0

            VStack(spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(accent)
                            .frame(width: max(geo.size.width * fraction, 5))
                    }
                    .frame(height: dragPosition == nil ? 5 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard track.duration > 0 else { return }
                                let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                                dragPosition = ratio * track.duration
                            }
                            .onEnded { _ in
                                if let dragPosition { onSeek(dragPosition) }
                                dragPosition = nil
                            }
                    )
                }
                .frame(height: 12)

                HStack {
                    Text(Format.clock(position))
                    Spacer()
                    Text("-" + Format.clock(max(track.duration - position, 0)))
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

struct PlaybackControls: View {
    let isPlaying: Bool
    let send: (NowPlayingService.Command) -> Void

    var body: some View {
        HStack(spacing: 26) {
            control("backward.fill", size: 15) { send(.previousTrack) }
            control(isPlaying ? "pause.fill" : "play.fill", size: 20) { send(.togglePlayPause) }
            control("forward.fill", size: 15) { send(.nextTrack) }
        }
        .frame(maxWidth: .infinity)
    }

    private func control(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The lyric line that matches the current playback position.
struct CurrentLyricLine: View {
    @EnvironmentObject private var lyrics: LyricsService
    @EnvironmentObject private var nowPlaying: NowPlayingService

    let font: Font
    let showsNextLine: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            content(at: context.date)
        }
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
        switch lyrics.state {
        case .synced(let lines):
            // Show a line slightly early so it does not feel late.
            let time = (nowPlaying.nowPlaying?.position(at: date) ?? 0) + 0.25
            let index = LyricsService.lineIndex(in: lines, at: time)
            let current = index.map { lines[$0].text } ?? ""
            let next = lines[safe: (index ?? -1) + 1]?.text ?? ""

            VStack(spacing: 2) {
                Text(current.isEmpty ? "♪" : current)
                    .font(font)
                    .foregroundStyle(.white)
                    .id("current-\(index ?? -1)")
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                if showsNextLine {
                    Text(next.isEmpty ? " " : next)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .id("next-\(index ?? -1)")
                        .transition(.opacity)
                }
            }
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .animation(.easeOut(duration: 0.25), value: index)
        case .loading:
            status("Looking for lyrics…")
        case .retrying:
            status("Lyrics services are busy, retrying…")
        case .unsynced:
            status("Lyrics found, but they are not time-synced")
        case .instrumental:
            status("Instrumental ♪")
        case .notFound:
            status("No lyrics found")
        case .failed:
            status("Lyrics unavailable (offline?)")
        case .idle:
            EmptyView()
        }
    }

    private func status(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.45))
            .lineLimit(1)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
