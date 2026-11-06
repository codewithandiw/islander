import AppKit

enum IslandTab: String, CaseIterable, Identifiable {
    case music, reminder, focus, shelf

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .music: "music.note"
        case .reminder: "bell.badge.fill"
        case .focus: "timer"
        case .shelf: "tray.full"
        }
    }

    var title: String {
        switch self {
        case .music: "Music"
        case .reminder: "Reminder"
        case .focus: "Focus"
        case .shelf: "Shelf"
        }
    }
}

/// Size of the hardware notch, or of a stand-in pill on screens without one.
struct NotchMetrics: Equatable {
    var width: CGFloat
    var height: CGFloat
    var hasNotch: Bool

    static let fallback = NotchMetrics(width: 190, height: 32, hasNotch: false)

    init(width: CGFloat, height: CGFloat, hasNotch: Bool) {
        self.width = width
        self.height = height
        self.hasNotch = hasNotch
    }

    init(screen: NSScreen) {
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            width = screen.frame.width - left.width - right.width
            height = top
            hasNotch = true
        } else {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            width = 170
            height = min(max(menuBar, 24), 40)
            hasNotch = false
        }
    }
}

/// UI state of the island: expanded or not, which tab, and its current size.
@MainActor
final class IslandModel: ObservableObject {
    static let expandedWidth: CGFloat = 600
    static let expandedContentHeight: CGFloat = 176
    static let compactSide: CGFloat = 72
    static let compactLyricHeight: CGFloat = 28
    /// Side columns when the lyric row is shown; artwork and mascot fill both rows.
    static let compactLyricSide: CGFloat = 86
    /// Must stay inside the panel canvas (760 pt) with room for the shadow.
    static let maxCompactWidth: CGFloat = 660
    static let compactLyricFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)

    /// Width of the longest synced line, so the island can widen once per song
    /// instead of jumping with every line.
    static func longestLyricWidth(_ lines: [LyricLine]) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: compactLyricFont]
        return lines.reduce(0) { max($0, ceil(($1.text as NSString).size(withAttributes: attributes).width)) }
    }

    @Published private(set) var isExpanded = false
    @Published var tab: IslandTab = .music { didSet { recomputeSize() } }
    @Published private(set) var isHovering = false
    @Published var metrics = NotchMetrics.fallback { didSet { recomputeSize() } }
    @Published private(set) var size = CGSize(width: 190, height: 32)
    @Published private(set) var showsCompact = false
    @Published private(set) var showsCompactLyric = false
    private var compactLyricWidth: CGFloat = 0
    /// True while a file is dragged over the island.
    @Published private(set) var isDropTargeted = false
    /// Bumped to play the light sweep along the island edge.
    @Published private(set) var shineTrigger = 0

    private var pendingWork: DispatchWorkItem?

    func updateLayout(isPlaying: Bool, hasReminder: Bool, compactLyric: Bool, compactLyricWidth: CGFloat = 0) {
        showsCompact = isPlaying || hasReminder
        showsCompactLyric = compactLyric && isPlaying && !hasReminder
        self.compactLyricWidth = compactLyricWidth
        recomputeSize()
    }

    func setExpanded(_ expanded: Bool) {
        pendingWork?.cancel()
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        if expanded { shineTrigger += 1 }
        recomputeSize()
    }

    /// Dragging a file over the island opens the shelf.
    func setDropTargeted(_ targeted: Bool) {
        guard targeted != isDropTargeted else { return }
        isDropTargeted = targeted
        if targeted {
            tab = .shelf
            setExpanded(true)
        }
    }

    func setHovering(_ hovering: Bool, expandOnHover: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        if hovering {
            if expandOnHover && !isExpanded {
                schedule(after: 0.15) { [weak self] in self?.setExpanded(true) }
            } else {
                pendingWork?.cancel()
            }
        } else if isExpanded {
            schedule(after: 0.35) { [weak self] in
                guard let self, !self.isHovering else { return }
                self.setExpanded(false)
            }
        } else {
            pendingWork?.cancel()
        }
    }

    /// Opens the island to show a reminder, then folds it back if the user is not looking.
    func presentReminder() {
        setExpanded(true)
        shineTrigger += 1
        schedule(after: 20) { [weak self] in
            guard let self, !self.isHovering else { return }
            self.setExpanded(false)
        }
    }

    private func schedule(after seconds: TimeInterval, _ block: @escaping () -> Void) {
        pendingWork?.cancel()
        let work = DispatchWorkItem(block: block)
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func recomputeSize() {
        let next: CGSize
        if isExpanded {
            let contentHeight: CGFloat = (tab == .reminder) ? 190 : Self.expandedContentHeight
            next = CGSize(
                width: max(Self.expandedWidth, metrics.width + 2 * 180),
                height: metrics.height + contentHeight
            )
        } else if showsCompactLyric {
            // Wide enough for the longest line between the side columns, within limits.
            let base = metrics.width + 2 * Self.compactLyricSide
            let needed = compactLyricWidth + 2 * Self.compactLyricSide + 24
            next = CGSize(
                width: min(max(base, needed), Self.maxCompactWidth),
                height: metrics.height + Self.compactLyricHeight
            )
        } else if showsCompact {
            next = CGSize(width: metrics.width + 2 * Self.compactSide, height: metrics.height)
        } else {
            next = CGSize(width: metrics.width, height: metrics.height)
        }
        if next != size { size = next }
    }
}
