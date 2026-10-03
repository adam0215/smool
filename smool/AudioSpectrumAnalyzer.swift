import Foundation

/// Independent channel filters keep stereo phase cancellation out of the meter.
struct AudioSpectrumAnalyzer {
    private var channels: [Channel]
    private var energy = AudioBands()
    private var count = 0

    init(sampleRate: Double, channelCount: Int) {
        channels = (0..<channelCount).map { _ in Channel(sampleRate: sampleRate) }
    }

    mutating func process(_ samples: UnsafeBufferPointer<Float>, channelCount: Int, firstChannel: Int) {
        guard channelCount > 0, firstChannel >= 0, firstChannel + channelCount <= channels.count else { return }
        for frame in stride(from: 0, to: samples.count - samples.count % channelCount, by: channelCount) {
            for channel in 0..<channelCount {
                let sample = Double(samples[frame + channel])
                let bands = channels[firstChannel + channel].process(sample.isFinite ? sample : 0)
                energy.bass += bands.bass * bands.bass
                energy.middle += bands.middle * bands.middle
                energy.treble += bands.treble * bands.treble
                count += 1
            }
        }
    }

    mutating func read() -> AudioBands {
        defer { energy = AudioBands(); count = 0 }
        guard count > 0 else { return AudioBands() }
        return AudioBands(bass: sqrt(energy.bass / Double(count)),
                          middle: sqrt(energy.middle / Double(count)),
                          treble: sqrt(energy.treble / Double(count)))
    }

    private struct Channel {
        var bass: Filter
        var middleLow: Filter
        var middleHigh: Filter
        var treble: Filter

        init(sampleRate: Double) {
            bass = Filter(cutoff: 250, sampleRate: sampleRate, highPass: false)
            middleLow = Filter(cutoff: 250, sampleRate: sampleRate, highPass: true)
            middleHigh = Filter(cutoff: 2_500, sampleRate: sampleRate, highPass: false)
            treble = Filter(cutoff: 2_500, sampleRate: sampleRate, highPass: true)
        }

        mutating func process(_ sample: Double) -> AudioBands {
            let middle = middleHigh.process(middleLow.process(sample))
            return AudioBands(bass: bass.process(sample), middle: middle, treble: treble.process(sample))
        }
    }

    /// Second-order Butterworth filters, with continuous state across audio buffers.
    private struct Filter {
        let b0: Double
        let b1: Double
        let b2: Double
        let a1: Double
        let a2: Double
        var z1 = 0.0
        var z2 = 0.0

        init(cutoff: Double, sampleRate: Double, highPass: Bool) {
            let angle = 2 * Double.pi * cutoff / sampleRate
            let cosine = cos(angle)
            let alpha = sin(angle) / sqrt(2)
            let denominator = 1 + alpha
            b0 = (1 + (highPass ? cosine : -cosine)) / (2 * denominator)
            b1 = (highPass ? -2 : 2) * b0
            b2 = b0
            a1 = -2 * cosine / denominator
            a2 = (1 - alpha) / denominator
        }

        mutating func process(_ sample: Double) -> Double {
            let output = b0 * sample + z1
            z1 = b1 * sample - a1 * output + z2
            z2 = b2 * sample - a2 * output
            return output
        }
    }
}
