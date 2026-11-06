import AppKit

enum ReminderKind: String, CaseIterable, Codable, Identifiable {
    case workBreak, stretch, drink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workBreak: "Take a break"
        case .stretch: "Stretch"
        case .drink: "Drink water"
        }
    }

    var message: String {
        switch self {
        case .workBreak: "Step away from the screen for a few minutes."
        case .stretch: "Stand up, roll your shoulders and stretch your back."
        case .drink: "Have a glass of water."
        }
    }

    var symbol: String {
        switch self {
        case .workBreak: "figure.walk"
        case .stretch: "figure.flexibility"
        case .drink: "drop.fill"
        }
    }
}

struct ReminderConfig: Codable, Equatable {
    var enabled: Bool
    var minutes: Int

    static let `default` = ReminderConfig(enabled: true, minutes: 180)
}

struct ReminderAlert: Equatable {
    var kinds: [ReminderKind]
    let firedAt: Date
}

/// Fires reminders after a set amount of *active* time, so idle or locked time does not count.
@MainActor
final class ReminderScheduler: ObservableObject {
    @Published private(set) var activeSince: [ReminderKind: TimeInterval] = [:]
    @Published private(set) var current: ReminderAlert?

    private let settings: AppSettings
    private let snoozeSeconds: TimeInterval = 10 * 60

    init(settings: AppSettings) {
        self.settings = settings
    }

    func addActiveTime(_ delta: TimeInterval) {
        var due: [ReminderKind] = []
        for kind in ReminderKind.allCases {
            let config = settings.config(for: kind)
            guard config.enabled else { continue }
            let value = activeSince[kind, default: 0] + delta
            activeSince[kind] = value
            if value >= interval(config) { due.append(kind) }
        }
        guard !due.isEmpty else { return }

        if var alert = current {
            let added = due.filter { !alert.kinds.contains($0) }
            guard !added.isEmpty else { return }
            alert.kinds += added
            current = alert
        } else {
            current = ReminderAlert(kinds: due, firedAt: .now)
            playSound()
        }
    }

    /// Seconds of active time left before `kind` fires, or nil when it is turned off.
    func remaining(for kind: ReminderKind) -> TimeInterval? {
        let config = settings.config(for: kind)
        guard config.enabled else { return nil }
        return max(interval(config) - activeSince[kind, default: 0], 0)
    }

    func complete() {
        for kind in current?.kinds ?? [] { activeSince[kind] = 0 }
        current = nil
    }

    func snooze() {
        for kind in current?.kinds ?? [] {
            activeSince[kind] = max(interval(settings.config(for: kind)) - snoozeSeconds, 0)
        }
        current = nil
    }

    /// Hides the reminder when the user moves to another tab; it comes back after the snooze time.
    func dismissForNow() {
        snooze()
    }

    func resetAll() {
        activeSince = [:]
        current = nil
    }

    func preview(_ kind: ReminderKind) {
        current = ReminderAlert(kinds: [kind], firedAt: .now)
        playSound()
    }

    private func interval(_ config: ReminderConfig) -> TimeInterval {
        TimeInterval(max(config.minutes, 1) * 60)
    }

    private func playSound() {
        guard settings.playReminderSound else { return }
        settings.focusReminderSound.play()
    }
}
