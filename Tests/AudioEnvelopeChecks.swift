import Foundation

@main
struct AudioEnvelopeChecks {
    static func main() {
        var envelope = AudioEnvelope()
        for _ in 0..<300 { envelope.update(rms: 0, elapsed: 1.0 / 30) }
        precondition(envelope.level == 0 && envelope.phase == 0, "Silence must remain still.")

        envelope.update(rms: 1, elapsed: 1.0 / 30)
        precondition(envelope.level > 0 && envelope.level < 0.08, "A transient must not flash.")
        for _ in 0..<60 { envelope.update(rms: 0.2, elapsed: 1.0 / 30) }
        let sustained = envelope.level
        precondition(sustained > 0.7 && sustained < 0.9, "Sustained music must drive visible motion.")
        envelope.update(rms: 0, elapsed: 1.0 / 30)
        precondition(envelope.level > sustained * 0.97, "Pauses should settle gradually.")
        for _ in 0..<400 { envelope.update(rms: 0, elapsed: 1.0 / 30) }
        let settled = envelope
        envelope.update(rms: 0, elapsed: 1.0 / 30)
        precondition(envelope.level == 0 && envelope.phase == settled.phase)

        for rms in [Double.nan, .infinity, -.infinity, -1, 100] {
            envelope.update(rms: rms, elapsed: 1.0 / 30)
            precondition(envelope.level.isFinite && (0...1).contains(envelope.level))
        }
        let valid = envelope
        for elapsed in [Double.nan, .infinity, -1, 0] { envelope.update(rms: 1, elapsed: elapsed) }
        precondition(envelope == valid)

        var slow = AudioEnvelope()
        var fast = AudioEnvelope()
        for _ in 0..<30 { slow.update(rms: 0.1, elapsed: 1.0 / 30) }
        for _ in 0..<60 { fast.update(rms: 0.1, elapsed: 1.0 / 60) }
        precondition(abs(slow.level - fast.level) < 0.000_001, "Smoothing must be independent of update frequency.")
        print("Passed: silent rest, soft attack, gradual release, bounded levels, and time-based smoothing.")
    }
}
