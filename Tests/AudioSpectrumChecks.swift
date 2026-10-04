@testable import SmoolChecksSupport
import Foundation

@main
struct AudioSpectrumChecks {
    static func main() {
        for rate in [44_100.0, 48_000, 96_000] {
            for frequency in [80.0, 800, 8_000] {
                let mono = (0..<Int(rate / 2)).map { Float(sin(2 * .pi * frequency * Double($0) / rate) * 0.4) }
                let stereo = mono.flatMap { [$0, -$0] }
                var meter = AudioSpectrumAnalyzer(sampleRate: rate, channelCount: 2)
                stereo.withUnsafeBufferPointer { meter.process($0, channelCount: 2, firstChannel: 0) }
                let bands = meter.read()
                let selected = frequency == 80 ? bands.bass : frequency == 800 ? bands.middle : bands.treble
                let others = frequency == 80 ? [bands.middle, bands.treble]
                    : frequency == 800 ? [bands.bass, bands.treble] : [bands.bass, bands.middle]
                precondition(selected > 0.25 && others.allSatisfy { selected > $0 * 5 },
                             "\(frequency) Hz must dominate its band at \(rate) Hz, even with opposite stereo phases.")
                precondition(meter.read() == AudioBands(), "An absent callback must never reuse old levels.")

                var planar = AudioSpectrumAnalyzer(sampleRate: rate, channelCount: 2)
                mono.withUnsafeBufferPointer { planar.process($0, channelCount: 1, firstChannel: 0) }
                mono.map { -$0 }.withUnsafeBufferPointer { planar.process($0, channelCount: 1, firstChannel: 1) }
                let split = planar.read()
                precondition(abs(split.bass - bands.bass) < 1e-9 && abs(split.middle - bands.middle) < 1e-9
                             && abs(split.treble - bands.treble) < 1e-9, "Planar and interleaved stereo must agree.")

                var chunked = AudioSpectrumAnalyzer(sampleRate: rate, channelCount: 1)
                var whole = AudioSpectrumAnalyzer(sampleRate: rate, channelCount: 1)
                mono.withUnsafeBufferPointer { buffer in
                    whole.process(buffer, channelCount: 1, firstChannel: 0)
                    for start in stride(from: 0, to: buffer.count, by: 127) {
                        chunked.process(UnsafeBufferPointer(rebasing: buffer[start..<min(start + 127, buffer.count)]),
                                        channelCount: 1, firstChannel: 0)
                    }
                }
                precondition(chunked.read() == whole.read(), "Filter history must survive callback boundaries.")
            }
        }
        var silence = AudioSpectrumAnalyzer(sampleRate: 48_000, channelCount: 1)
        [Float.nan, .infinity, -.infinity, 0].withUnsafeBufferPointer {
            silence.process($0, channelCount: 1, firstChannel: 0)
        }
        precondition(silence.read() == AudioBands())
        print("Passed: frequency separation, sample rates, stereo phase, planar buffers, callback continuity, and silence.")
    }
}
