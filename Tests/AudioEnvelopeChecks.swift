import Foundation

@main
struct AudioEnvelopeChecks {
    static func main() {
        var envelope = AudioEnvelope()
        for _ in 0..<300 { envelope.update(rms: 0, elapsed: 1.0 / 30) }
        precondition(envelope.opacity == 0 && envelope.phase == 0, "Silence must be dark and still.")

        envelope.update(rms: 1, elapsed: 1.0 / 30)
        precondition(envelope.opacity > 0 && envelope.opacity < 0.2, "A transient must rise gently.")
        for _ in 0..<120 { envelope.update(rms: 0.2, elapsed: 1.0 / 30) }
        let sustained = envelope.level
        precondition(sustained > 0.65 && sustained < 0.85, "Sustained music must drive visible motion.")
        precondition(envelope.pulse < 0.01, "A sustained tone must not invent a beat.")
        let steady = envelope
        for _ in 0..<4 { envelope.update(rms: 0.8, elapsed: 1.0 / 30) }
        precondition(envelope.pulse > 0.2 && envelope.lift > steady.lift + 0.15,
                     "A musical attack must raise the glow above its sustained height.")
        precondition(envelope.colorMix > steady.colorMix + 0.1, "Attacks must shift the cover's color mix.")
        let peak = envelope.level
        envelope.update(rms: 0, elapsed: 1.0 / 30)
        precondition(envelope.level > peak * 0.85, "Pauses should settle gradually.")
        for _ in 0..<60 { envelope.update(rms: 0, elapsed: 1.0 / 30) }
        let settled = envelope
        envelope.update(rms: 0, elapsed: 1.0 / 30)
        precondition(envelope.opacity == 0 && envelope.phase == settled.phase, "A quiet passage must become fully dark.")

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
        print("Passed: dark silence, softened rhythmic attacks, color response, release, bounded levels, and time-based smoothing.")
    }
}
