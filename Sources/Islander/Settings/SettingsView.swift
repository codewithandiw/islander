import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(env: AppEnvironment) {
        if window == nil {
            let view = SettingsView()
                .environmentObject(env.settings)
                .environmentObject(env.nowPlaying)
                .environmentObject(env.spectrum)
                .environmentObject(env.reminders)
                .environmentObject(env.eventReminders)
                .environmentObject(env.shelf)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Islander Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            MusicSettings()
                .tabItem { Label("Music", systemImage: "music.note") }
            RemindersSettings()
                .tabItem { Label("Reminders", systemImage: "bell") }
            FocusSettings()
                .tabItem { Label("Focus", systemImage: "timer") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 460)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Island") {
                Toggle("Expand when the pointer is over the island", isOn: $settings.expandOnHover)
                Text("When off, click the island to open it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LaunchAtLoginToggle()
            }

            Section("Mascot") {
                Toggle("Show mascot", isOn: $settings.showMascot)
                HStack(spacing: 14) {
                    ForEach(MascotColor.allCases) { option in
                        Button {
                            settings.mascotColor = option
                        } label: {
                            MascotView(mood: settings.mascotColor == option ? .dancing : .idle, color: option.color, energy: 0.3, size: 40)
                                .padding(4)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(settings.mascotColor == option ? Color.accentColor : .clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(option.name)
                    }
                }
                .disabled(!settings.showMascot)
                .padding(.vertical, 4)
                MascotMoodPreview(color: settings.mascotColor.color)
                    .disabled(!settings.showMascot)
            }

            Section("Shelf") {
                ShelfSettingsRow()
            }

            Section {
                Button("Quit Islander", role: .destructive) { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShelfSettingsRow: View {
    @EnvironmentObject private var shelf: ShelfStore

    var body: some View {
        LabeledContent("Files on shelf") {
            Text("\(shelf.items.count) · \(ShelfStore.format(shelf.totalSize))")
        }
        Button("Clean shelf now", role: .destructive) { shelf.clean() }
            .disabled(shelf.items.isEmpty)
        Text("Drop files on the island to keep a temporary copy (max 10 MB each, 100 MB total). Originals are never changed. The shelf is emptied when Islander quits.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Lets the user see every mascot animation.
private struct MascotMoodPreview: View {
    let color: Color
    @State private var mood: MascotMood = .dancing

    var body: some View {
        HStack(spacing: 16) {
            MascotView(mood: mood, color: color, energy: 0.5, size: 72)
                .frame(width: 84, height: 84)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.black))
            Picker("Animation", selection: $mood) {
                ForEach(MascotMood.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
        }
        .padding(.vertical, 4)
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var errorText: String?

    var body: some View {
        Toggle("Open Islander at login", isOn: Binding(
            get: { enabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    enabled = newValue
                    errorText = nil
                } catch {
                    errorText = error.localizedDescription
                }
            }
        ))
        if let errorText {
            Text(errorText)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Music

private struct MusicSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var nowPlaying: NowPlayingService
    @EnvironmentObject private var spectrum: AudioSpectrum

    var body: some View {
        Form {
            Section("Now Playing") {
                LabeledContent("Media detection") {
                    switch nowPlaying.status {
                    case .starting: Text("Starting…").foregroundStyle(.secondary)
                    case .running: Text("Working").foregroundStyle(.green)
                    case .unavailable(let reason): Text(reason).foregroundStyle(.orange)
                    }
                }
                Text("Works with Spotify, Apple Music, and music in Safari, Chrome, Arc or Edge (YouTube Music, SoundCloud, …).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Visualizer") {
                Toggle("Show audio visualizer", isOn: $settings.showVisualizer)
                if let error = spectrum.lastError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                Text("The visualizer listens to system audio. If the bars do not follow the music, allow Islander under Privacy & Security › Screen & System Audio Recording › System Audio Recording Only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Section("Lyrics") {
                Toggle("Show lyrics", isOn: $settings.showLyrics)
                Toggle("Show the current line under the notch", isOn: $settings.showCompactLyrics)
                    .disabled(!settings.showLyrics)
                Text("Lyrics come from LRCLIB (lrclib.net). The song title and artist are sent to look them up. Found lyrics are kept on this Mac for 30 days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Reminders

private struct RemindersSettings: View {
    @EnvironmentObject private var eventReminders: EventReminderStore
    @State private var previewSound: EventReminderSound = .amongUs

    var body: some View {
        Form {
            Section("Event Reminders") {
                let activeCount = eventReminders.reminders.filter { !$0.isCompleted }.count
                let completedCount = eventReminders.reminders.filter { $0.isCompleted }.count

                LabeledContent("Active reminders") {
                    Text("\(activeCount)")
                }
                LabeledContent("Completed reminders") {
                    Text("\(completedCount)")
                }

                if completedCount > 0 {
                    Button("Clear completed reminders", role: .destructive) {
                        for item in eventReminders.reminders where item.isCompleted {
                            eventReminders.delete(id: item.id)
                        }
                    }
                }
            }

            Section("Notification Ringtones") {
                HStack {
                    Picker("Audition ringtone", selection: $previewSound) {
                        ForEach(EventReminderSound.allCases) { snd in
                            Text(snd.displayName).tag(snd)
                        }
                    }
                    Button("Play") {
                        previewSound.play()
                    }
                }

                Button("Test Notch Notification & Banner") {
                    eventReminders.triggerTestAlert()
                }

                Text("Reminders can play a chime as the event approaches (2–30 min before) and when it is due. Works with the Dynamic Island notch banner and macOS Notifications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Focus

private struct FocusSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var reminders: ReminderScheduler

    var body: some View {
        Form {
            Section("Work time") {
                Stepper("Daily goal: \(settings.dailyGoalHours) h", value: $settings.dailyGoalHours, in: 1...16)
                Stepper("Idle after \(settings.idleThresholdMinutes) min without input", value: $settings.idleThresholdMinutes, in: 1...30)
                Stepper("Count as a break after \(settings.breakResetMinutes) min away", value: $settings.breakResetMinutes, in: 5...60, step: 5)
            }

            Section("Reminders") {
                ForEach(ReminderKind.allCases) { kind in
                    HStack {
                        Toggle(isOn: binding(kind, \.enabled)) {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                        Spacer()
                        Stepper(
                            "every \(Format.duration(TimeInterval(settings.config(for: kind).minutes * 60)))",
                            value: binding(kind, \.minutes),
                            in: 15...480,
                            step: 15
                        )
                        .disabled(!settings.config(for: kind).enabled)
                        .fixedSize()
                        Button("Test") { reminders.preview(kind) }
                    }
                }
                Toggle("Play a sound", isOn: $settings.playReminderSound)
                if settings.playReminderSound {
                    HStack {
                        Picker("Sound effect", selection: $settings.focusReminderSound) {
                            ForEach(EventReminderSound.allCases) { sound in
                                Text(sound.displayName).tag(sound)
                            }
                        }
                        Button {
                            settings.focusReminderSound.play()
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Preview sound")
                    }
                }
                Text("Reminders count only active time. Locked, sleeping or idle time does not count.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ kind: ReminderKind, _ keyPath: WritableKeyPath<ReminderConfig, Value>) -> Binding<Value> {
        Binding(
            get: { settings.config(for: kind)[keyPath: keyPath] },
            set: { newValue in
                var config = settings.config(for: kind)
                config[keyPath: keyPath] = newValue
                settings.reminders[kind] = config
            }
        )
    }
}

// MARK: - About

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 12) {
            MascotView(mood: .dancing, color: MascotColor.sunny.color, energy: 0.5, size: 80)
            Text("Islander")
                .font(.title.bold())
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text("Media info via mediaremote-adapter (BSD-3-Clause).\nLyrics by LRCLIB.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
