import AppKit
import Combine
import SwiftUI

/// Borderless, transparent panel that floats above the menu bar on every Space.
final class IslandPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Places the island at the top of the notched screen and lets clicks pass through
/// everywhere except over the visible island shape.
@MainActor
final class IslandWindowController {
    /// The panel is larger than the biggest island so the shadow and spring animation have room.
    private static let canvasSize = CGSize(width: 760, height: 300)

    private let env: AppEnvironment
    private let panel = IslandPanel()
    private var screen: NSScreen
    private var monitors: [Any] = []
    private var bag = Set<AnyCancellable>()

    init(env: AppEnvironment) {
        self.env = env
        self.screen = Self.preferredScreen()

        let root = IslandRootView(
            openSettings: { SettingsWindowController.shared.show(env: env) },
            quit: { NSApp.terminate(nil) }
        )
        .environmentObject(env.island)
        .environmentObject(env.settings)
        .environmentObject(env.nowPlaying)
        .environmentObject(env.lyrics)
        .environmentObject(env.spectrum)
        .environmentObject(env.activity)
        .environmentObject(env.reminders)
        .environmentObject(env.eventReminders)
        .environmentObject(env.shelf)

        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }

        env.island.$size
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMouseState() }
            .store(in: &bag)
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
        installMouseMonitors()
    }

    private static func preferredScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func reposition() {
        screen = Self.preferredScreen()
        env.island.metrics = NotchMetrics(screen: screen)
        let frame = screen.frame
        let size = Self.canvasSize
        panel.setFrame(
            NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height),
            display: true
        )
    }

    private func installMouseMonitors() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouseState() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updateMouseState() }
            return event
        }) {
            monitors.append(local)
        }
    }

    /// Island rectangle in screen coordinates, with a small margin so the top edge is easy to hit.
    private var islandRect: NSRect {
        let size = env.island.size
        let frame = screen.frame
        return NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
            .insetBy(dx: -4, dy: -4)
    }

    private func updateMouseState() {
        let inside = islandRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        env.island.setHovering(inside, expandOnHover: env.settings.expandOnHover)
    }
}
