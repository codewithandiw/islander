import SwiftUI
import UniformTypeIdentifiers

private struct IsSnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when rendering with ImageRenderer, which cannot draw drop targets or scroll views.
    var isSnapshot: Bool {
        get { self[IsSnapshotKey.self] }
        set { self[IsSnapshotKey.self] = newValue }
    }
}

private extension View {
    @ViewBuilder
    func islandDropTarget(enabled: Bool, isTargeted: Binding<Bool>, perform: @escaping ([NSItemProvider]) -> Void) -> some View {
        if enabled {
            onDrop(of: [.fileURL, .image, .plainText], isTargeted: isTargeted) { providers in
                perform(providers)
                return true
            }
        } else {
            self
        }
    }
}

struct IslandRootView: View {
    @EnvironmentObject private var island: IslandModel
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject private var nowPlaying: NowPlayingService
    @EnvironmentObject private var reminders: ReminderScheduler
    @EnvironmentObject private var eventReminders: EventReminderStore
    @Environment(\.isSnapshot) private var isSnapshot

    let openSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        let expanded = island.isExpanded
        let targeted = island.isDropTargeted
        let shape = NotchShape(topRadius: expanded ? 12 : 6, bottomRadius: expanded ? 28 : 12)

        ZStack(alignment: .top) {
            shape.fill(Color.black)

            if expanded {
                ExpandedIslandView(openSettings: openSettings)
                    .transition(.blurReplace.combined(with: ScaleTransition(0.94, anchor: .top)))
            } else if island.showsCompact {
                CompactIslandView()
                    .transition(.blurReplace)
            }
        }
        .frame(width: island.size.width, height: island.size.height)
        .clipShape(shape)
        .overlay {
            // Edge lighting sits outside the clip so the glow can spill over the border.
            ShineSweep(shape: shape, trigger: island.shineTrigger, tint: shineTint)
            DropGlow(shape: shape, isActive: targeted)
        }
        .contentShape(shape)
        .scaleEffect(targeted ? 1.04 : 1, anchor: .top)
        .shadow(color: .black.opacity(expanded ? 0.5 : 0), radius: 16, y: 8)
        .onTapGesture {
            if !expanded { island.setExpanded(true) }
        }
        .islandDropTarget(
            enabled: !isSnapshot,
            isTargeted: Binding(get: { island.isDropTargeted }, set: { island.setDropTargeted($0) })
        ) { shelf.add($0) }
        .contextMenu {
            Button("Settings…", action: openSettings)
            Divider()
            Button("Quit Islander", action: quit)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: island.size)
        .animation(.smooth(duration: 0.3), value: expanded)
        .animation(.smooth(duration: 0.3), value: island.showsCompact)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: targeted)
        .environment(\.colorScheme, .dark)
    }

    /// Reminders shine cyan or orange; otherwise the sweep takes the song's color, or plain white.
    private var shineTint: Color {
        if eventReminders.activeAlert != nil { return .orange }
        if reminders.current != nil { return .cyan }
        return nowPlaying.nowPlaying?.isPlaying == true ? nowPlaying.accent : .white
    }
}

// MARK: - Lighting

/// A band of light that runs once along the island border each time `trigger` changes.
private struct ShineSweep<S: Shape>: View {
    let shape: S
    let trigger: Int
    let tint: Color

    var body: some View {
        Color.clear
            .keyframeAnimator(initialValue: 1.0, trigger: trigger) { [shape, tint] _, phase in
                Self.band(shape: shape, tint: tint, phase: phase)
            } keyframes: { _ in
                KeyframeTrack {
                    MoveKeyframe(0.0)
                    CubicKeyframe(1.0, duration: 1.1)
                }
            }
            .allowsHitTesting(false)
    }

    private nonisolated static func band(shape: S, tint: Color, phase: Double) -> some View {
        // Travel from just left of the island to just right of it.
        let center = phase * 1.6 - 0.3
        let gradient = LinearGradient(
            stops: [
                .init(color: tint.opacity(0), location: Self.clamp(center - 0.2)),
                .init(color: tint, location: Self.clamp(center)),
                .init(color: tint.opacity(0), location: Self.clamp(center + 0.2)),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        return ZStack {
            shape.stroke(gradient, lineWidth: 6).blur(radius: 6)
            shape.stroke(gradient, lineWidth: 1.5)
        }
        .opacity(sin(phase * .pi))
    }

    private nonisolated static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// Pulsing cyan outline while a file is dragged over the island.
private struct DropGlow<S: Shape>: View {
    let shape: S
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive)) { context in
            let pulse = 0.65 + 0.35 * sin(context.date.timeIntervalSinceReferenceDate * 5)
            ZStack {
                shape.stroke(Color.cyan.opacity(0.8 * pulse), lineWidth: 8).blur(radius: 8)
                shape.stroke(Color.cyan.opacity(pulse), lineWidth: 2)
            }
        }
        .opacity(isActive ? 1 : 0)
        .animation(.smooth(duration: 0.25), value: isActive)
        .allowsHitTesting(false)
    }
}

// MARK: - Compact

/// The small island next to the notch: artwork on the left, visualizer and mascot on the right.
struct CompactIslandView: View {
    @EnvironmentObject private var island: IslandModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var nowPlaying: NowPlayingService
    @EnvironmentObject private var reminders: ReminderScheduler
    @EnvironmentObject private var eventReminders: EventReminderStore

    var body: some View {
        let isPlaying = nowPlaying.nowPlaying?.isPlaying ?? false
        let hasActiveAlert = reminders.current != nil || eventReminders.activeAlert != nil

        if island.showsCompactLyric {
            lyricLayout(isPlaying: isPlaying)
        } else {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leading
                    .frame(width: IslandModel.compactSide - 18, alignment: .leading)
                    .padding(.leading, 18)
                Spacer(minLength: island.metrics.width)
                HStack(spacing: 6) {
                    // Compact mode shows the mascot alone; the equalizer only stands in when the mascot is off.
                    if settings.showVisualizer && isPlaying && !settings.showMascot {
                        SpectrumBars(barCount: 4, color: nowPlaying.accent, isPlaying: isPlaying)
                            .frame(width: 18, height: 14)
                            .transition(.blurReplace)
                    }
                    if settings.showMascot {
                        DancingMascot(mood: hasActiveAlert ? .shock : (isPlaying ? .dancing : .idle), size: 24)
                    }
                }
                .frame(width: IslandModel.compactSide - 18, alignment: .trailing)
                .padding(.trailing, 18)
            }
            .frame(height: island.metrics.height)
        }
        }
    }

    /// Two rows tall: big artwork on the left, big mascot on the right, and the lyric
    /// centered under the notch between them.
    private func lyricLayout(isPlaying: Bool) -> some View {
        let side = IslandModel.compactLyricSide
        let art = island.metrics.height + IslandModel.compactLyricHeight - 16

        return HStack(spacing: 0) {
            ArtworkView(image: nowPlaying.artwork, size: art, cornerRadius: 10)
                .padding(.leading, 16)
                .frame(width: side, alignment: .leading)

            VStack(spacing: 0) {
                Color.clear.frame(height: island.metrics.height)
                CurrentLyricLine(font: Font(IslandModel.compactLyricFont as CTFont), showsNextLine: false)
                    .frame(maxWidth: .infinity)
                    .frame(height: IslandModel.compactLyricHeight - 6)
            }
            .frame(maxWidth: .infinity)

            Group {
                if settings.showMascot {
                    DancingMascot(mood: isPlaying ? .dancing : .idle, size: art)
                } else if settings.showVisualizer {
                    SpectrumBars(barCount: 5, color: nowPlaying.accent, isPlaying: isPlaying)
                        .frame(width: art * 0.6, height: art * 0.5)
                }
            }
            // Mirrors the artwork's padding so both sides look balanced.
            .padding(.trailing, 16)
            .frame(width: side, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
        .transition(.blurReplace)
    }

    @ViewBuilder
    private var leading: some View {
        if let alert = eventReminders.activeAlert {
            Image(systemName: alert.isApproachingWarning ? "bell.badge.fill" : "alarm.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(alert.isApproachingWarning ? .orange : .red)
                .symbolEffect(.pulse)
                .transition(.blurReplace)
        } else if let alert = reminders.current, let kind = alert.kinds.first {
            Image(systemName: kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.cyan)
                .symbolEffect(.pulse)
                .transition(.blurReplace)
        } else {
            ArtworkView(image: nowPlaying.artwork, size: 22, cornerRadius: 6)
                .transition(.blurReplace)
        }
    }
}

/// Mascot that reads the audio level itself, so only this small view redraws
/// with the music instead of its whole parent.
struct DancingMascot: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var spectrum: AudioSpectrum

    let mood: MascotMood
    let size: CGFloat
    /// Clicking the mascot makes it spin once.
    var spinsOnTap = false

    @State private var spinning = false

    var body: some View {
        MascotView(mood: spinning ? .spinning : mood, color: settings.mascotColor.color, energy: Double(spectrum.level), size: size)
            .contentShape(Rectangle())
            .onTapGesture {
                guard spinsOnTap, !spinning else { return }
                spinning = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { spinning = false }
            }
            .allowsHitTesting(spinsOnTap)
    }
}

// MARK: - Expanded

struct ExpandedIslandView: View {
    @EnvironmentObject private var island: IslandModel
    @EnvironmentObject private var reminders: ReminderScheduler
    @EnvironmentObject private var eventReminders: EventReminderStore
    @EnvironmentObject private var shelf: ShelfStore
    @Namespace private var tabHighlight

    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: island.metrics.height)

            ZStack(alignment: .top) {
                if let alert = eventReminders.activeAlert {
                    EventReminderAlertCard(
                        alert: alert,
                        onDone: { eventReminders.toggleCompleted(id: alert.reminder.id) },
                        onSnooze: { eventReminders.snooze(id: alert.reminder.id, minutes: 5) },
                        onDismiss: { eventReminders.dismissAlert() }
                    )
                    .transition(.blurReplace)
                } else if let alert = reminders.current {
                    ReminderCard(alert: alert)
                        .transition(.blurReplace)
                } else {
                    switch island.tab {
                    case .music: MusicTabView().transition(.blurReplace)
                    case .reminder: ReminderTabView().transition(.blurReplace)
                    case .focus: FocusTabView().transition(.blurReplace)
                    case .shelf: ShelfTabView().transition(.blurReplace)
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 10)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.smooth(duration: 0.3), value: island.tab)
            .animation(.smooth(duration: 0.3), value: reminders.current != nil)
            .animation(.smooth(duration: 0.3), value: eventReminders.activeAlert != nil)
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(IslandTab.allCases) { tab in
                Button {
                    island.tab = tab
                    if eventReminders.activeAlert != nil { eventReminders.dismissAlert() }
                    if reminders.current != nil { reminders.dismissForNow() }
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 22)
                        .background {
                            if island.tab == tab {
                                Capsule()
                                    .fill(Color.white.opacity(0.18))
                                    .matchedGeometryEffect(id: "tab", in: tabHighlight)
                            }
                        }
                        .foregroundStyle(island.tab == tab ? .white : .white.opacity(0.55))
                        .overlay(alignment: .topTrailing) {
                            if tab == .shelf && !shelf.items.isEmpty {
                                Text("\(shelf.items.count)")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 3)
                                    .frame(minWidth: 12, minHeight: 12)
                                    .background(Capsule().fill(Color.cyan))
                                    .foregroundStyle(.black)
                                    .offset(x: 3, y: -3)
                                    .transition(.scale.combined(with: .opacity))
                            } else if tab == .reminder {
                                let pending = eventReminders.reminders.filter { !$0.isCompleted }.count
                                if pending > 0 {
                                    Text("\(pending)")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 3)
                                        .frame(minWidth: 12, minHeight: 12)
                                        .background(Capsule().fill(Color.orange))
                                        .foregroundStyle(.black)
                                        .offset(x: 3, y: -3)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
            Spacer()
            Button(action: openSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 22)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 28)
        .padding(.top, 2)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: island.tab)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: shelf.items.count)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: eventReminders.reminders.filter { !$0.isCompleted }.count)
    }
}

/// Small rounded pill button used inside the island.
struct IslandButtonStyle: ButtonStyle {
    var prominent = false
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let background: Color = tint ?? (prominent ? .white : .white.opacity(configuration.isPressed ? 0.25 : 0.14))
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(background))
            .foregroundStyle(prominent && tint == nil ? Color.black : Color.white)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
