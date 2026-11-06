import AppKit
import Foundation

public final class SoundPlayer: NSObject, NSSoundDelegate, @unchecked Sendable {
    public static let shared = SoundPlayer()

    private var activeSounds = Set<NSSound>()
    private let lock = NSLock()

    private override init() {
        super.init()
    }

    @discardableResult
    public func play(named name: String) -> Bool {
        guard let url = locateSoundURL(named: name) else {
            return false
        }
        guard let sound = NSSound(contentsOf: url, byReference: true) else {
            return false
        }
        sound.delegate = self
        lock.lock()
        activeSounds.insert(sound)
        lock.unlock()
        return sound.play()
    }

    public func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        lock.lock()
        activeSounds.remove(sound)
        lock.unlock()
    }

    public func locateSoundURL(named name: String) -> URL? {
        let cleanName = name.replacingOccurrences(of: ".mp3", with: "")

        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: cleanName, withExtension: "mp3") {
            return url
        }
        if let url = Bundle.module.url(forResource: cleanName, withExtension: "mp3", subdirectory: "Sounds") {
            return url
        }
        #endif

        if let url = Bundle.main.url(forResource: cleanName, withExtension: "mp3") {
            return url
        }
        if let url = Bundle.main.url(forResource: cleanName, withExtension: "mp3", subdirectory: "Sounds") {
            return url
        }

        if let resourceURL = Bundle.main.resourceURL {
            let direct = resourceURL.appendingPathComponent("\(cleanName).mp3")
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
            let inSounds = resourceURL.appendingPathComponent("Sounds/\(cleanName).mp3")
            if FileManager.default.fileExists(atPath: inSounds.path) { return inSounds }
        }

        let relativePaths = [
            "Sources/Islander/Resources/Sounds/\(cleanName).mp3",
            "Resources/Sounds/\(cleanName).mp3",
            "Sounds/\(cleanName).mp3"
        ]
        for path in relativePaths {
            let candidate = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }
}

