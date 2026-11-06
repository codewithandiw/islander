import SwiftUI

/// Vertical bars that follow the real audio, or a gentle fake dance when no signal is available.
struct SpectrumBars: View {
    @EnvironmentObject private var spectrum: AudioSpectrum

    let barCount: Int
    let color: Color
    let isPlaying: Bool
    var spacing: CGFloat = 2

    var body: some View {
        let live = spectrum.hasSignal
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: live || !isPlaying)) { context in
            let values = live
                ? Self.resample(spectrum.bands, to: barCount)
                : Self.simulated(count: barCount, time: context.date.timeIntervalSinceReferenceDate, playing: isPlaying)

            GeometryReader { geo in
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { index in
                        Capsule()
                            .fill(color)
                            .frame(height: max(geo.size.height * CGFloat(values[index]), 3))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .animation(.linear(duration: 0.06), value: spectrum.bands)
    }

    /// Averages the analyzer bands into `count` bars.
    static func resample(_ bands: [Float], to count: Int) -> [Float] {
        guard !bands.isEmpty, count > 0 else { return Array(repeating: 0, count: count) }
        return (0..<count).map { index in
            let start = index * bands.count / count
            let end = max((index + 1) * bands.count / count, start + 1)
            let slice = bands[start..<min(end, bands.count)]
            return slice.reduce(0, +) / Float(slice.count)
        }
    }

    static func simulated(count: Int, time: TimeInterval, playing: Bool) -> [Float] {
        guard playing else { return Array(repeating: 0.1, count: count) }
        return (0..<count).map { index in
            let i = Double(index)
            let wave = abs(sin(time * (3.1 + i * 0.73) + i * 1.3)) * (0.55 + 0.45 * sin(time * 1.7 + i))
            return Float(0.2 + 0.75 * wave)
        }
    }
}
