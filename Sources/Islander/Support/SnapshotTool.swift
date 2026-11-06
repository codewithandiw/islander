#if DEBUG
import AppKit
import SwiftUI

/// Debug helper: `Islander --snapshot <dir>` renders each island state to PNG files and exits.
/// Lets us check the layout without hovering over the real notch.
@MainActor
enum SnapshotTool {
    static func runIfRequested() {
        let args = CommandLine.arguments
        // `Islander --mascot <file.png>` renders every mood at several moments in one sheet.
        if let flag = args.firstIndex(of: "--mascot"), args.indices.contains(flag + 1) {
            let times: [TimeInterval] = [0.05, 0.2, 0.35, 0.5, 0.7, 0.95, 1.15]
            let sheet = VStack(alignment: .leading, spacing: 6) {
                ForEach(MascotMood.allCases) { mood in
                    HStack(spacing: 6) {
                        Text(mood.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).frame(width: 70, alignment: .leading)
                        ForEach(times, id: \.self) { time in
                            MascotView(mood: mood, color: MascotColor.sky.color, energy: 0.6, size: 90, fixedTime: time)
                        }
                        MascotView(mood: mood, color: MascotColor.sky.color, energy: 0.6, size: 24, fixedTime: 0.3)
                    }
                }
            }
            .padding(12)
            .background(Color.black)
            let renderer = ImageRenderer(content: sheet)
            renderer.scale = 2
            if let tiff = renderer.nsImage?.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: args[flag + 1]))
            }
            exit(0)
        }
        // `Islander --lyrics <artist> <title> <seconds>` prints what the lyrics lookup finds.
        if let flag = args.firstIndex(of: "--lyrics"), args.count > flag + 3 {
            let artist = args[flag + 1], title = args[flag + 2], duration = Double(args[flag + 3]) ?? 0
            Task {
                print(await LyricsService.debugLookup(title: title, artist: artist, duration: duration), terminator: "")
                exit(0)
            }
            RunLoop.main.run()
        }
        guard let flag = args.firstIndex(of: "--snapshot"), args.indices.contains(flag + 1) else { return }
        let directory = URL(fileURLWithPath: args[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let env = AppEnvironment()
        env.island.metrics = NotchMetrics(width: 185, height: 32, hasNotch: true)
        let track = NowPlaying(
            sourceBundleID: "com.spotify.client",
            title: "Blinding Lights",
            artist: "The Weeknd",
            album: "After Hours",
            isPlaying: true,
            duration: 200,
            elapsed: 74,
            timestamp: .now,
            playbackRate: 1
        )
        env.nowPlaying.injectForSnapshot(track, artwork: sampleArtwork())
        env.lyrics.injectForSnapshot(.synced([
            LyricLine(time: 60, text: "I've been tryna call"),
            LyricLine(time: 70, text: "I've been on my own for long enough"),
            LyricLine(time: 80, text: "Maybe you can show me how to love, maybe"),
        ]))
        if case .synced(let lines) = env.lyrics.state {
            env.island.updateLayout(isPlaying: true, hasReminder: false, compactLyric: true, compactLyricWidth: IslandModel.longestLyricWidth(lines))
        }

        render(env, to: directory.appendingPathComponent("1-compact.png"))

        // A long line widens the compact island so it is not cut off.
        let longLines = [
            LyricLine(time: 60, text: "痛みも悲しみも拭いきれず"),
            LyricLine(time: 70, text: "Maybe you can show me how to love, maybe someday soon"),
        ]
        env.lyrics.injectForSnapshot(.synced(longLines))
        env.island.updateLayout(isPlaying: true, hasReminder: false, compactLyric: true, compactLyricWidth: IslandModel.longestLyricWidth(longLines))
        render(env, to: directory.appendingPathComponent("1b-compact-long-lyric.png"))
        env.lyrics.injectForSnapshot(.synced([
            LyricLine(time: 60, text: "I've been tryna call"),
            LyricLine(time: 70, text: "I've been on my own for long enough"),
            LyricLine(time: 80, text: "Maybe you can show me how to love, maybe"),
        ]))

        env.island.setExpanded(true)
        env.island.tab = .music
        render(env, to: directory.appendingPathComponent("2-music.png"))

        env.island.tab = .focus
        render(env, to: directory.appendingPathComponent("3-focus.png"))

        env.island.tab = .reminder
        render(env, to: directory.appendingPathComponent("3b-reminder-tab.png"))

        let formContainer = ReminderTabView(initialCreatingNew: true)
            .environmentObject(env.eventReminders)
            .environmentObject(env.settings)
            .environment(\.isSnapshot, true)
            .padding(14)
            .frame(width: 600, height: 210)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(30)
            .frame(width: 760, height: 260)
            .background(Color(red: 0.25, green: 0.45, blue: 0.7))
        renderCustom(formContainer, to: directory.appendingPathComponent("3c-reminder-form.png"))

        env.reminders.preview(.stretch)
        render(env, to: directory.appendingPathComponent("4-reminder.png"))

        env.reminders.resetAll()
        env.eventReminders.triggerTestAlert()
        render(env, to: directory.appendingPathComponent("4b-event-reminder-alert.png"))
        env.eventReminders.dismissAlert()
        env.island.tab = .shelf
        render(env, to: directory.appendingPathComponent("6-shelf-empty.png"))
        let sample = FileManager.default.temporaryDirectory.appendingPathComponent("Screenshot 2026-10-30 at 22.41.07.png")
        try? sampleArtwork().tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }?.write(to: sample)
        env.shelf.addFile(sample)
        env.shelf.addFile(URL(fileURLWithPath: "/System/Library/CoreServices/SystemVersion.plist"))
        // Copies finish on a background task; give them a moment.
        RunLoop.main.run(until: .now + 1.5)
        render(env, to: directory.appendingPathComponent("7-shelf-files.png"))

        let tooBig = FileManager.default.temporaryDirectory.appendingPathComponent("big-video.mov")
        try? Data(count: Int(ShelfStore.maxFileSize) + 1).write(to: tooBig)
        env.shelf.addFile(tooBig)
        render(env, to: directory.appendingPathComponent("8-shelf-too-big.png"))
        try? FileManager.default.removeItem(at: tooBig)
        env.shelf.clean()

        env.nowPlaying.injectForSnapshot(nil)
        env.island.tab = .music
        render(env, to: directory.appendingPathComponent("5-nothing-playing.png"))

        print("Snapshots written to \(directory.path)")
        exit(0)
    }

    private static func renderCustom<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
    }

    private static func render(_ env: AppEnvironment, to url: URL) {
        let view = IslandRootView(openSettings: {}, quit: {})
            .environmentObject(env.island)
            .environmentObject(env.settings)
            .environmentObject(env.nowPlaying)
            .environmentObject(env.lyrics)
            .environmentObject(env.spectrum)
            .environmentObject(env.activity)
            .environmentObject(env.reminders)
            .environmentObject(env.eventReminders)
            .environmentObject(env.shelf)
            .environment(\.isSnapshot, true)
            .frame(width: 760, height: 260)
            .background(Color(red: 0.25, green: 0.45, blue: 0.7))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
    }

    private static func sampleArtwork() -> NSImage {
        let size = NSSize(width: 200, height: 200)
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [.systemRed, .systemOrange, .systemPink])?.draw(in: rect, angle: 45)
            return true
        }
    }
}
#endif
