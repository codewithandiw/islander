import Foundation
import SwiftUI

enum MascotColor: String, CaseIterable, Identifiable {
    case sunny, bubblegum, mint, sky, grape

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .sunny: Color(red: 1.00, green: 0.80, blue: 0.25)
        case .bubblegum: Color(red: 1.00, green: 0.56, blue: 0.72)
        case .mint: Color(red: 0.45, green: 0.90, blue: 0.70)
        case .sky: Color(red: 0.45, green: 0.75, blue: 1.00)
        case .grape: Color(red: 0.72, green: 0.58, blue: 1.00)
        }
    }
}

/// User preferences, persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    @Published var expandOnHover: Bool { didSet { store(expandOnHover, .expandOnHover) } }
    @Published var showMascot: Bool { didSet { store(showMascot, .showMascot) } }
    @Published var mascotColor: MascotColor { didSet { store(mascotColor.rawValue, .mascotColor) } }
    @Published var showVisualizer: Bool { didSet { store(showVisualizer, .showVisualizer) } }
    @Published var showLyrics: Bool { didSet { store(showLyrics, .showLyrics) } }
    @Published var showCompactLyrics: Bool { didSet { store(showCompactLyrics, .showCompactLyrics) } }
    @Published var playReminderSound: Bool { didSet { store(playReminderSound, .playReminderSound) } }
    @Published var focusReminderSound: EventReminderSound { didSet { store(focusReminderSound.rawValue, .focusReminderSound) } }
    /// No keyboard or mouse input for this long means you are not working.
    @Published var idleThresholdMinutes: Int { didSet { store(idleThresholdMinutes, .idleThresholdMinutes) } }
    /// Being away this long counts as a real break and resets the reminders.
    @Published var breakResetMinutes: Int { didSet { store(breakResetMinutes, .breakResetMinutes) } }
    @Published var dailyGoalHours: Int { didSet { store(dailyGoalHours, .dailyGoalHours) } }
    @Published var reminders: [ReminderKind: ReminderConfig] { didSet { storeReminders() } }

    private enum Key: String {
        case expandOnHover, showMascot, mascotColor, showVisualizer, showLyrics, showCompactLyrics
        case playReminderSound, focusReminderSound, idleThresholdMinutes, breakResetMinutes, dailyGoalHours, reminders
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.expandOnHover.rawValue: true,
            Key.showMascot.rawValue: true,
            Key.mascotColor.rawValue: MascotColor.sunny.rawValue,
            Key.showVisualizer.rawValue: true,
            Key.showLyrics.rawValue: true,
            Key.showCompactLyrics.rawValue: true,
            Key.playReminderSound.rawValue: true,
            Key.focusReminderSound.rawValue: EventReminderSound.amongUs.rawValue,
            Key.idleThresholdMinutes.rawValue: 5,
            Key.breakResetMinutes.rawValue: 15,
            Key.dailyGoalHours.rawValue: 8,
        ])
        expandOnHover = defaults.bool(forKey: Key.expandOnHover.rawValue)
        showMascot = defaults.bool(forKey: Key.showMascot.rawValue)
        mascotColor = MascotColor(rawValue: defaults.string(forKey: Key.mascotColor.rawValue) ?? "") ?? .sunny
        showVisualizer = defaults.bool(forKey: Key.showVisualizer.rawValue)
        showLyrics = defaults.bool(forKey: Key.showLyrics.rawValue)
        showCompactLyrics = defaults.bool(forKey: Key.showCompactLyrics.rawValue)
        playReminderSound = defaults.bool(forKey: Key.playReminderSound.rawValue)
        focusReminderSound = EventReminderSound(rawValue: defaults.string(forKey: Key.focusReminderSound.rawValue) ?? "") ?? .amongUs
        idleThresholdMinutes = defaults.integer(forKey: Key.idleThresholdMinutes.rawValue)
        breakResetMinutes = defaults.integer(forKey: Key.breakResetMinutes.rawValue)
        dailyGoalHours = defaults.integer(forKey: Key.dailyGoalHours.rawValue)
        reminders = Self.loadReminders(from: defaults)
    }

    func config(for kind: ReminderKind) -> ReminderConfig {
        reminders[kind] ?? .default
    }

    private func store(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    private func storeReminders() {
        let byName = Dictionary(uniqueKeysWithValues: reminders.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(byName) {
            defaults.set(data, forKey: Key.reminders.rawValue)
        }
    }

    private static func loadReminders(from defaults: UserDefaults) -> [ReminderKind: ReminderConfig] {
        var result = Dictionary(uniqueKeysWithValues: ReminderKind.allCases.map { ($0, ReminderConfig.default) })
        guard let data = defaults.data(forKey: Key.reminders.rawValue),
              let byName = try? JSONDecoder().decode([String: ReminderConfig].self, from: data)
        else { return result }
        for (name, config) in byName {
            if let kind = ReminderKind(rawValue: name) { result[kind] = config }
        }
        return result
    }
}
