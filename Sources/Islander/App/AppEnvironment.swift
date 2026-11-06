import AppKit
import Combine

/// Owns every long-lived service and wires them together.
@MainActor
final class AppEnvironment {
    let settings = AppSettings()
    let nowPlaying = NowPlayingService()
    let lyrics = LyricsService()
    let spectrum = AudioSpectrum()
    let island = IslandModel()
    let shelf = ShelfStore()
    let activity: ActivityTracker
    let reminders: ReminderScheduler
    let eventReminders = EventReminderStore()

    private var bag = Set<AnyCancellable>()

    init() {
        activity = ActivityTracker(settings: settings)
        reminders = ReminderScheduler(settings: settings)

        activity.onActiveTime = { [weak reminders] delta in reminders?.addActiveTime(delta) }
        activity.onBreakDetected = { [weak reminders] in reminders?.resetAll() }

        nowPlaying.$nowPlaying
            .sink { [weak lyrics] in lyrics?.update(for: $0) }
            .store(in: &bag)

        // Capture system audio only while something plays and the visualizer is on.
        nowPlaying.$nowPlaying
            .map { $0?.isPlaying ?? false }
            .removeDuplicates()
            .combineLatest(settings.$showVisualizer)
            .sink { [weak spectrum] playing, enabled in spectrum?.setActive(playing && enabled) }
            .store(in: &bag)

        reminders.$current
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak island] hasReminder in
                if hasReminder { island?.presentReminder() }
            }
            .store(in: &bag)

        eventReminders.$activeAlert
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak island] hasAlert in
                if hasAlert { island?.presentReminder() }
            }
            .store(in: &bag)

        // Recompute the island size whenever anything that affects it changes.
        // receive(on:) runs after @Published has stored the new value.
        Publishers.MergeMany(
            nowPlaying.$nowPlaying.map { _ in () }.eraseToAnyPublisher(),
            lyrics.$state.map { _ in () }.eraseToAnyPublisher(),
            reminders.$current.map { _ in () }.eraseToAnyPublisher(),
            eventReminders.$activeAlert.map { _ in () }.eraseToAnyPublisher(),
            settings.$showCompactLyrics.map { _ in () }.eraseToAnyPublisher(),
            settings.$showLyrics.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.updateIslandLayout() }
        .store(in: &bag)
    }

    func start() {
        nowPlaying.start()
        activity.start()
        eventReminders.startMonitoring()
        updateIslandLayout()
    }

    func stop() {
        nowPlaying.stop()
        spectrum.setActive(false, immediately: true)
        activity.stop()
        eventReminders.stopMonitoring()
        shelf.clean()
    }

    private func updateIslandLayout() {
        let isPlaying = nowPlaying.nowPlaying?.isPlaying ?? false
        var syncedLines: [LyricLine]?
        if case .synced(let lines) = lyrics.state { syncedLines = lines }
        island.updateLayout(
            isPlaying: isPlaying,
            hasReminder: reminders.current != nil || eventReminders.activeAlert != nil,
            compactLyric: settings.showLyrics && settings.showCompactLyrics && syncedLines != nil,
            compactLyricWidth: syncedLines.map(IslandModel.longestLyricWidth) ?? 0
        )
    }
}
