import AppKit

@main
enum IslanderMain {
    @MainActor
    static func main() {
        #if DEBUG
        SnapshotTool.runIfRequested()
        #endif
        SettingsMigration.run()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var env: AppEnvironment?
    private var islandController: IslandWindowController?

    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        quitCleanlyOnSIGTERM()
        let env = AppEnvironment()
        self.env = env
        islandController = IslandWindowController(env: env)
        islandController?.show()
        env.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        env?.stop()
    }

    /// `kill`, `pkill` and logout send SIGTERM, which normally skips applicationWillTerminate.
    /// Route it through a normal quit so the media adapter process and shelf files are cleaned up.
    private func quitCleanlyOnSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignal = source
    }
}
