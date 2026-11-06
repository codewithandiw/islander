import AppKit
import Foundation

public enum EventReminderRepeat: String, CaseIterable, Codable, Identifiable {
    case never
    case hourly
    case daily
    case weekdays
    case weekly
    case monthly
    case yearly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .never: "One-time"
        case .hourly: "Hourly"
        case .daily: "Daily"
        case .weekdays: "Weekdays (Mon–Fri)"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }

    public var symbol: String {
        switch self {
        case .never: "calendar"
        case .hourly: "clock.arrow.circlepath"
        case .daily: "arrow.triangle.2.circlepath"
        case .weekdays: "briefcase"
        case .weekly: "calendar.badge.clock"
        case .monthly: "calendar.badge.exclamationmark"
        case .yearly: "sparkles"
        }
    }

    public func nextDate(after referenceDate: Date, originalDate: Date) -> Date {
        let calendar = Calendar.current
        var candidate = originalDate
        if candidate > referenceDate { return candidate }

        switch self {
        case .never:
            return candidate
        case .hourly:
            while candidate <= referenceDate {
                guard let next = calendar.date(byAdding: .hour, value: 1, to: candidate) else { break }
                candidate = next
            }
        case .daily:
            while candidate <= referenceDate {
                guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { break }
                candidate = next
            }
        case .weekdays:
            while candidate <= referenceDate || calendar.isDateInWeekend(candidate) {
                guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { break }
                candidate = next
            }
        case .weekly:
            while candidate <= referenceDate {
                guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: candidate) else { break }
                candidate = next
            }
        case .monthly:
            while candidate <= referenceDate {
                guard let next = calendar.date(byAdding: .month, value: 1, to: candidate) else { break }
                candidate = next
            }
        case .yearly:
            while candidate <= referenceDate {
                guard let next = calendar.date(byAdding: .year, value: 1, to: candidate) else { break }
                candidate = next
            }
        }
        return candidate
    }
}

public enum EventReminderSound: String, CaseIterable, Codable, Identifiable {
    case amongUs = "among_us"
    case bruh = "bruh"
    case metalGear = "metal_gear"
    case sadViolin = "sad_violin"
    case shocked = "shocked"
    case huh = "huh"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .amongUs: "Among Us"
        case .bruh: "Bruh"
        case .metalGear: "Metal Gear Alert"
        case .sadViolin: "Sad Violin"
        case .shocked: "Shocked"
        case .huh: "Huh?"
        }
    }

    public var fileName: String {
        rawValue
    }

    public var systemSoundName: String {
        displayName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let match = EventReminderSound(rawValue: raw) {
            self = match
        } else {
            // Graceful fallback for legacy saved reminders
            self = .amongUs
        }
    }

    @discardableResult
    public func play() -> Bool {
        SoundPlayer.shared.play(named: fileName)
    }
}

public enum EventReminderLeadTime: Int, CaseIterable, Codable, Identifiable {
    case atTime = 0
    case min2 = 120
    case min5 = 300
    case min10 = 600
    case min15 = 900
    case min30 = 1800
    case hour1 = 3600

    public var id: Int { rawValue }

    public var timeInterval: TimeInterval {
        TimeInterval(rawValue)
    }

    public var title: String {
        switch self {
        case .atTime: "At event time"
        case .min2: "2 min before"
        case .min5: "5 min before"
        case .min10: "10 min before"
        case .min15: "15 min before"
        case .min30: "30 min before"
        case .hour1: "1 hour before"
        }
    }
}

public struct EventReminder: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var dueDate: Date
    public var repeatSchedule: EventReminderRepeat
    public var sound: EventReminderSound
    public var leadTime: EventReminderLeadTime
    public var isCompleted: Bool
    public var createdAt: Date
    public var approachedNotifiedAt: Date?
    public var dueNotifiedAt: Date?
    public var snoozedUntil: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        dueDate: Date,
        repeatSchedule: EventReminderRepeat = .never,
        sound: EventReminderSound = .amongUs,
        leadTime: EventReminderLeadTime = .min5,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        approachedNotifiedAt: Date? = nil,
        dueNotifiedAt: Date? = nil,
        snoozedUntil: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.repeatSchedule = repeatSchedule
        self.sound = sound
        self.leadTime = leadTime
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.approachedNotifiedAt = approachedNotifiedAt
        self.dueNotifiedAt = dueNotifiedAt
        self.snoozedUntil = snoozedUntil
    }

    public var effectiveTargetDate: Date {
        snoozedUntil ?? dueDate
    }

    /// True if the reminder is approaching (within the lead-time window before due date).
    public func isApproaching(at date: Date = Date()) -> Bool {
        guard !isCompleted, leadTime != .atTime else { return false }
        let threshold = effectiveTargetDate.addingTimeInterval(-leadTime.timeInterval)
        return date >= threshold && date < effectiveTargetDate
    }

    /// True if the reminder is due right now or past due.
    public func isDue(at date: Date = Date()) -> Bool {
        guard !isCompleted else { return false }
        return date >= effectiveTargetDate
    }
}

public struct EventReminderAlert: Equatable, Identifiable {
    public var id: UUID { reminder.id }
    public var reminder: EventReminder
    public var isApproachingWarning: Bool
    public var firedAt: Date

    public init(reminder: EventReminder, isApproachingWarning: Bool, firedAt: Date = Date()) {
        self.reminder = reminder
        self.isApproachingWarning = isApproachingWarning
        self.firedAt = firedAt
    }
}

