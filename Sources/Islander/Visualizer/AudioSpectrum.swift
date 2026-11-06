import CoreAudio
import Foundation

/// Publishes smoothed frequency bands of whatever the Mac is playing.
@MainActor
final class AudioSpectrum: ObservableObject {
    @Published private(set) var bands = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
    @Published private(set) var level: Float = 0
    /// False when audio is silent or the capture permission was denied.
    @Published private(set) var hasSignal = false
    @Published private(set) var lastError: String?

    private var tap: SystemAudioTap?
    private var lastSignalAt = Date.distantPast
    private var stopWork: DispatchWorkItem?
    private var deviceListener: AudioObjectPropertyListenerBlock?

    var isRunning: Bool { tap != nil }

    /// Stopping is delayed a little so short pauses and track changes do not restart capture.
    func setActive(_ active: Bool, immediately: Bool = false) {
        stopWork?.cancel()
        if active {
            start()
        } else if immediately {
            stop()
        } else {
            let work = DispatchWorkItem { [weak self] in self?.stop() }
            stopWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
        }
    }

    private func start() {
        guard tap == nil else { return }
        let tap = SystemAudioTap()
        do {
            try tap.start { [weak self] bands, level in
                DispatchQueue.main.async { self?.apply(bands: bands, level: level) }
            }
            self.tap = tap
            lastError = nil
            installDeviceListener()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func stop() {
        tap?.stop()
        tap = nil
        bands = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
        level = 0
        hasSignal = false
    }

    private func restart() {
        guard tap != nil else { return }
        stop()
        start()
    }

    private func apply(bands newBands: [Float], level newLevel: Float) {
        guard tap != nil else { return }
        // Fast attack, slow release, so bars jump with beats and fall smoothly.
        bands = zip(bands, newBands).map { old, new in new > old ? new : max(new, old * 0.82) }
        level = newLevel > level ? newLevel : max(newLevel, level * 0.88)

        let now = Date()
        if newLevel > 0.02 { lastSignalAt = now }
        let signal = now.timeIntervalSince(lastSignalAt) < 2
        if signal != hasSignal { hasSignal = signal }
    }

    /// Rebuild the tap when the output device changes (for example, headphones plugged in).
    private func installDeviceListener() {
        guard deviceListener == nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.restart() }
        }
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        if status == noErr { deviceListener = block }
    }
}
