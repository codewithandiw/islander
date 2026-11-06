import AppKit
import Combine
import Foundation
import UserNotifications

@MainActor
public final class EventReminderStore: ObservableObject {
    @Published public private(set) var reminders: [EventReminder] = []
    @Published public var activeAlert: EventReminderAlert? = nil

    private let storageKey = "islander.eventReminders.v1"
    private let defaults: UserDefaults
    private var timer: AnyCancellable?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.reminders = Self.load(from: defaults, key: storageKey)
        if self.reminders.isEmpty {
            self.reminders = Self.defaultSeedReminders()
            self.save()
        }
        startMonitoring()
        requestNotificationPermission()
    }

    deinit {
        timer?.cancel()
    }

    public func startMonitoring() {
        timer?.cancel()
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.evaluateReminders()
            }
    }

    public func stopMonitoring() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Actions

    public func add(
        title: String,
        notes: String = "",
        dueDate: Date,
        repeatSchedule: EventReminderRepeat = .never,
        sound: EventReminderSound = .amongUs,
        leadTime: EventReminderLeadTime = .min5
    ) {
        let reminder = EventReminder(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: dueDate,
            repeatSchedule: repeatSchedule,
            sound: sound,
            leadTime: leadTime
        )
        reminders.insert(reminder, at: 0)
        sortReminders()
        save()
    }

    public func update(_ updated: EventReminder) {
        guard let index = reminders.firstIndex(where: { $0.id == updated.id }) else { return }
        reminders[index] = updated
        sortReminders()
        save()
        if activeAlert?.reminder.id == updated.id {
            activeAlert?.reminder = updated
        }
    }

    public func delete(id: UUID) {
        reminders.removeAll { $0.id == id }
        if activeAlert?.reminder.id == id {
            activeAlert = nil
        }
        save()
    }

    public func toggleCompleted(id: UUID) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        var reminder = reminders[index]

        if reminder.isCompleted {
            // Uncompleting
            reminder.isCompleted = false
            reminder.approachedNotifiedAt = nil
            reminder.dueNotifiedAt = nil
            reminder.snoozedUntil = nil
        } else {
            // Marking completed
            if reminder.repeatSchedule != .never {
                // Advance to next recurrence
                let next = reminder.repeatSchedule.nextDate(after: Date(), originalDate: reminder.dueDate)
                reminder.dueDate = next
                reminder.isCompleted = false
                reminder.approachedNotifiedAt = nil
                reminder.dueNotifiedAt = nil
                reminder.snoozedUntil = nil
            } else {
                reminder.isCompleted = true
            }
        }

        reminders[index] = reminder
        if activeAlert?.reminder.id == id {
            activeAlert = nil
        }
        sortReminders()
        save()
    }

    public func snooze(id: UUID, minutes: Int = 10) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        let snoozedDate = Date().addingTimeInterval(Double(minutes * 60))
        reminders[index].snoozedUntil = snoozedDate
        reminders[index].dueNotifiedAt = nil
        reminders[index].approachedNotifiedAt = nil
        if activeAlert?.reminder.id == id {
            activeAlert = nil
        }
        sortReminders()
        save()
    }

    public func dismissAlert() {
        activeAlert = nil
    }

    public func previewSound(_ sound: EventReminderSound) {
        sound.play()
    }

    public func triggerTestAlert(for id: UUID? = nil) {
        let reminder: EventReminder
        if let id, let match = reminders.first(where: { $0.id == id }) {
            reminder = match
        } else if let first = reminders.first {
            reminder = first
        } else {
            reminder = EventReminder(
                title: "Test Reminder Alert",
                notes: "This is a preview of the approaching notification ringtone and island banner.",
                dueDate: Date().addingTimeInterval(300),
                sound: .amongUs,
                leadTime: .min5
            )
        }
        reminder.sound.play()
        activeAlert = EventReminderAlert(reminder: reminder, isApproachingWarning: true, firedAt: Date())
    }

    // MARK: - Evaluation & Notification

    private func evaluateReminders() {
        let now = Date()
        var modified = false

        for index in reminders.indices {
            var item = reminders[index]
            guard !item.isCompleted else { continue }

            // 1. Approaching warning
            if item.leadTime != .atTime && item.isApproaching(at: now) && item.approachedNotifiedAt == nil {
                item.approachedNotifiedAt = now
                reminders[index] = item
                modified = true

                // Play sound and trigger dynamic island alert
                item.sound.play()
                activeAlert = EventReminderAlert(reminder: item, isApproachingWarning: true, firedAt: now)
                dispatchNotification(for: item, isApproaching: true)
                break
            }

            // 2. Due alert
            if item.isDue(at: now) && item.dueNotifiedAt == nil {
                item.dueNotifiedAt = now
                reminders[index] = item
                modified = true

                // Play ringtone and alert
                item.sound.play()
                activeAlert = EventReminderAlert(reminder: item, isApproachingWarning: false, firedAt: now)
                dispatchNotification(for: item, isApproaching: false)
                break
            }
        }

        if modified {
            save()
        }
    }

    private var canUseUserNotifications: Bool {
        guard let id = Bundle.main.bundleIdentifier, !id.isEmpty else { return false }
        return Bundle.main.bundleURL.pathExtension == "app"
    }

    private func dispatchNotification(for reminder: EventReminder, isApproaching: Bool) {
        guard canUseUserNotifications else { return }
        let content = UNMutableNotificationContent()
        if isApproaching {
            content.title = "Approaching: \(reminder.title)"
            content.subtitle = "Due in \(reminder.leadTime.title)"
        } else {
            content.title = "Reminder: \(reminder.title)"
            content.subtitle = reminder.repeatSchedule != .never ? "Repeating \(reminder.repeatSchedule.title)" : "Due now"
        }
        content.body = reminder.notes.isEmpty ? "Tap to view in Islander" : reminder.notes
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(reminder.sound.fileName).mp3"))

        let request = UNNotificationRequest(
            identifier: "islander.reminder.\(reminder.id.uuidString).\(isApproaching ? "approach" : "due")",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func requestNotificationPermission() {
        guard canUseUserNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func sortReminders() {
        reminders.sort { r1, r2 in
            if r1.isCompleted != r2.isCompleted {
                return !r1.isCompleted && r2.isCompleted
            }
            return r1.effectiveTargetDate < r2.effectiveTargetDate
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [EventReminder] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([EventReminder].self, from: data)
        else { return [] }
        return list
    }

    private static func defaultSeedReminders() -> [EventReminder] {
        let calendar = Calendar.current
        let today = Date()

        // 1. One-time reminder approaching soon (+20 minutes)
        let upcoming = calendar.date(byAdding: .minute, value: 20, to: today) ?? today.addingTimeInterval(1200)

        // 2. Daily recurring reminder for evening wrap-up (today at 17:30 or tomorrow)
        var components = calendar.dateComponents([.year, .month, .day], from: today)
        components.hour = 17
        components.minute = 30
        let wrapupDate = calendar.date(from: components) ?? today.addingTimeInterval(3600 * 2)

        return [
            EventReminder(
                title: "Hydrate & Quick Stretch",
                notes: "Drink a glass of cold water and rest your eyes.",
                dueDate: upcoming,
                repeatSchedule: .never,
                sound: .bruh,
                leadTime: .min5
            ),
            EventReminder(
                title: "Daily Wrap-up & Plan Tomorrow",
                notes: "Review accomplishments, clear inbox, and set top priorities.",
                dueDate: wrapupDate,
                repeatSchedule: .daily,
                sound: .amongUs,
                leadTime: .min10
            )
        ]
    }
}
