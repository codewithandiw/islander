import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

enum AudioTapError: LocalizedError {
    case osStatus(String, OSStatus)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .osStatus(let step, let status): "Could not \(step) (error \(status))."
        case .unsupportedFormat: "System audio has an unsupported format."
        }
    }
}

/// Listens to everything the Mac plays using a Core Audio process tap (macOS 14.2+).
///
/// The first start asks for "System Audio Recording" permission. If the user says no,
/// the tap still runs but only delivers silence.
final class SystemAudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "islander.audio-tap", qos: .userInteractive)

    deinit {
        stop()
    }

    func start(onSpectrum: @escaping ([Float], Float) -> Void) throws {
        do {
            try startTap(onSpectrum: onSpectrum)
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private func startTap(onSpectrum: @escaping ([Float], Float) -> Void) throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Islander Visualizer"
        description.muteBehavior = .unmuted
        description.isPrivate = true

        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw AudioTapError.osStatus("create the audio tap", status) }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
        guard status == noErr else { throw AudioTapError.osStatus("read the audio format", status) }
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32
        else { throw AudioTapError.unsupportedFormat }
        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0

        let outputUID = try Self.defaultOutputDeviceUID()
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Islander Visualizer Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregateID)
        guard status == noErr else { throw AudioTapError.osStatus("create the capture device", status) }

        let analyzer = SpectrumAnalyzer(sampleRate: format.mSampleRate, onSpectrum: onSpectrum)
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { _, inputData, _, _, _ in
            analyzer.consume(inputData, interleaved: interleaved)
        }
        guard status == noErr else { throw AudioTapError.osStatus("listen to system audio", status) }

        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else { throw AudioTapError.osStatus("start capturing audio", status) }
    }

    static func defaultOutputDeviceUID() throws -> String {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr else { throw AudioTapError.osStatus("find the output device", status) }

        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { throw AudioTapError.osStatus("read the output device", status) }
        return uid.takeRetainedValue() as String
    }
}

/// Turns raw samples into log-spaced frequency bands (0...1). Runs on the audio queue.
final class SpectrumAnalyzer {
    static let bandCount = 24

    private let fftSize = 1024
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]
    private let sampleRate: Double
    private let onSpectrum: ([Float], Float) -> Void
    private let bandRanges: [Range<Int>]
    private var samples: [Float] = []
    private var lastPublish = DispatchTime.now()
    private let publishInterval: UInt64 = 33_000_000 // ~30 fps

    init(sampleRate: Double, onSpectrum: @escaping ([Float], Float) -> Void) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 48_000
        self.onSpectrum = onSpectrum
        log2n = vDSP_Length(log2(Double(fftSize)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
        samples.reserveCapacity(fftSize * 2)

        // Log-spaced bands from 40 Hz to 16 kHz, each at least one FFT bin wide.
        let binWidth = self.sampleRate / Double(fftSize)
        let maxBin = fftSize / 2 - 1
        var ranges: [Range<Int>] = []
        for i in 0..<Self.bandCount {
            let low = 40 * pow(16_000 / 40, Double(i) / Double(Self.bandCount))
            let high = 40 * pow(16_000 / 40, Double(i + 1) / Double(Self.bandCount))
            let start = min(max(Int(low / binWidth), 1), maxBin)
            let end = min(max(Int(high / binWidth), start + 1), maxBin + 1)
            ranges.append(start..<end)
        }
        bandRanges = ranges
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    func consume(_ list: UnsafePointer<AudioBufferList>, interleaved: Bool) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let first = buffers.first, let raw = first.mData else { return }
        let channels = interleaved ? max(Int(first.mNumberChannels), 1) : 1
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels
        let data = raw.assumingMemoryBound(to: Float.self)

        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels { sum += data[frame * channels + channel] }
            samples.append(sum / Float(channels))
        }
        if samples.count > fftSize {
            samples.removeFirst(samples.count - fftSize)
        }

        let now = DispatchTime.now()
        guard samples.count == fftSize,
              now.uptimeNanoseconds - lastPublish.uptimeNanoseconds >= publishInterval
        else { return }
        lastPublish = now
        let (bands, level) = analyze(samples)
        onSpectrum(bands, level)
    }

    private func analyze(_ frame: [Float]) -> ([Float], Float) {
        let windowed = vDSP.multiply(frame, window)
        let half = fftSize / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        // zrip output is scaled by 2; normalize to roughly 0...1 amplitude.
        let scale = 1 / Float(fftSize)
        var bands = [Float](repeating: 0, count: Self.bandCount)
        for (index, range) in bandRanges.enumerated() {
            var peak: Float = 0
            for bin in range { peak = max(peak, magnitudes[bin]) }
            let amplitude = peak * scale
            let decibels = 20 * log10(amplitude + 1e-9)
            bands[index] = min(max((decibels + 65) / 55, 0), 1)
        }

        let rms = vDSP.rootMeanSquare(frame)
        let level = min(max((20 * log10(rms + 1e-9) + 50) / 44, 0), 1)
        return (bands, level)
    }
}
