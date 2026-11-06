import AppKit
import CoreGraphics

/// Measures how long you actively use the Mac each day.
///
/// Time counts as active while the screen is unlocked, the Mac is awake, and there was
/// keyboard or mouse input within the idle threshold. No permissions are needed.
@MainActor
final class ActivityTracker: ObservableObject {
    @Published private(set) var todayActive: TimeInterval = 0
    @Published private(set) var firstActiveToday: Date?
    @Published private(set) var sinceLastBreak: TimeInterval = 0
    @Published private(set) var isActive = false

    /// Called with each slice of active time.
    var onActiveTime: ((TimeInterval) -> Void)?
    /// Called when the user was away long enough to count as a break, or pressed "I took a break".
    var onBreakDetected: (() -> Void)?

    private static let historyKey = "activity.history"
    private static let firstActiveKey = "activity.firstActive"
    private static let keepDays = 30

    private let settings: AppSettings
    private let defaults: UserDefaults
    private let tickInterval: TimeInterval = 10
    private var timer: Timer?
    private var lastTick = Date()
    private var lastActiveAt = Date()
    private var lastSave = Date.distantPast
    private var dayKey: String
    private var screenLocked = false
    private var systemAsleep = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        dayKey = Self.key(for: .now)
        let history = defaults.dictionary(forKey: Self.historyKey) as? [String: Double] ?? [:]
        todayActive = history[dayKey] ?? 0
        if let first = defaults.object(forKey: Self.firstActiveKey) as? Date, Self.key(for: first) == dayKey {
            firstActiveToday = first
        }
    }

    func start() {
        guard timer == nil else { return }
        lastTick = .now
        lastActiveAt = .now
        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observeSystemState()
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        save()
    }

    func takeBreakNow() {
        sinceLastBreak = 0
        onBreakDetected?()
    }

    /// Active seconds for each of the last `days` days, oldest first.
    func history(days: Int) -> [(date: Date, seconds: TimeInterval)] {
        var stored = defaults.dictionary(forKey: Self.historyKey) as? [String: Double] ?? [:]
        stored[dayKey] = todayActive
        let calendar = Calendar.current
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: .now)) else { return nil }
            return (date, stored[Self.key(for: date)] ?? 0)
        }
    }

    // MARK: - Ticking

    private func tick() {
        let now = Date()
        // Cap the slice so a sleep or a stalled timer never adds a big jump.
        let delta = min(now.timeIntervalSince(lastTick), tickInterval * 2)
        lastTick = now
        rollDayIfNeeded(now)

        let idle = Self.secondsSinceLastInput()
        let active = !screenLocked && !systemAsleep && idle < TimeInterval(settings.idleThresholdMinutes * 60)

        let away = now.timeIntervalSince(lastActiveAt)
        if away >= TimeInterval(settings.breakResetMinutes * 60), sinceLastBreak > 0 {
            sinceLastBreak = 0
            onBreakDetected?()
        }

        if active {
            lastActiveAt = now
            todayActive += delta
            sinceLastBreak += delta
            if firstActiveToday == nil {
                firstActiveToday = now
                defaults.set(now, forKey: Self.firstActiveKey)
            }
            onActiveTime?(delta)
        }
        if active != isActive { isActive = active }

        if now.timeIntervalSince(lastSave) >= 60 { save() }
    }

    private func rollDayIfNeeded(_ now: Date) {
        let key = Self.key(for: now)
        guard key != dayKey else { return }
        save()
        dayKey = key
        todayActive = 0
        firstActiveToday = nil
    }

    private func save() {
        var history = defaults.dictionary(forKey: Self.historyKey) as? [String: Double] ?? [:]
        history[dayKey] = todayActive
        // Day keys are yyyy-MM-dd, so string order is date order.
        let keys = history.keys.sorted()
        for old in keys.dropLast(Self.keepDays) { history.removeValue(forKey: old) }
        defaults.set(history, forKey: Self.historyKey)
        lastSave = .now
    }

    // MARK: - System state

    private func observeSystemState() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        func watch(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor () -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            }
            observers.append((center, token))
        }

        watch(workspace, NSWorkspace.willSleepNotification) { [weak self] in self?.systemAsleep = true }
        watch(workspace, NSWorkspace.didWakeNotification) { [weak self] in
            self?.systemAsleep = false
            self?.lastTick = .now
        }
        watch(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.screenLocked = true }
        watch(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.screenLocked = false }
    }

    private static func secondsSinceLastInput() -> TimeInterval {
        let types: [CGEventType] = [
            .mouseMoved, .keyDown, .flagsChanged, .scrollWheel,
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged,
        ]
        return types.map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }.min() ?? 0
    }

    private static func key(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
