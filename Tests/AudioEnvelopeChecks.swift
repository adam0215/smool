@testable import SmoolChecksSupport
import Foundation

@main
struct AudioEnvelopeChecks {
    static func main() {
        var envelope = AudioEnvelope()
        for _ in 0..<300 { envelope.update(rms: 0, elapsed: 1.0 / 30) }
        precondition(envelope == AudioEnvelope(), "Silence must leave the envelope at rest.")

        envelope.update(rms: 1, elapsed: 1.0 / 30)
        precondition(envelope.level > 0 && envelope.level < 0.03, "A transient must ease in without flashing.")
        for _ in 0..<120 { envelope.update(rms: 0.2, elapsed: 1.0 / 30) }
        let sustained = envelope.level
        precondition(sustained > 0.65 && sustained < 0.85, "Sustained music must drive visible motion.")
        precondition(envelope.pulse < 0.01, "A sustained tone must not invent a beat.")
        let steady = envelope
        for _ in 0..<12 { envelope.update(rms: 0.8, elapsed: 1.0 / 30) }
        precondition(envelope.pulse > 0.2 && envelope.lift > steady.lift + 0.15,
                     "A musical attack must raise the glow above its sustained height.")
        let peak = envelope.level
        envelope.update(rms: 0, elapsed: 1.0 / 30)
        precondition(envelope.level > peak * 0.85, "Pauses should settle gradually.")
        for _ in 0..<120 { envelope.update(rms: 0, elapsed: 1.0 / 30) }
        let settled = envelope
        envelope.update(rms: 0, elapsed: 1.0 / 30)
        precondition(envelope == AudioEnvelope() && envelope == settled, "A quiet passage must settle completely.")

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
        precondition(abs(slow.level - fast.level) < 0.01, "Smoothing must be consistent across update frequencies.")
        var step = AudioEnvelope()
        for _ in 0..<150 {
            let previous = step.level
            step.update(rms: 1, elapsed: 1.0 / 30)
            precondition(abs(step.level - previous) < 0.06, "Even a full-volume step must move smoothly.")
        }
        var spectrum = AudioSpectrum()
        for frame in 0..<180 {
            let previous = spectrum.visibility
            spectrum.update(AudioBands(bass: frame % 15 < 4 ? 0.8 : 0.08), elapsed: 1.0 / 30)
            precondition(abs(spectrum.visibility - previous) < 0.04,
                         "Rhythmic attacks should reshape the light without brightness flashes.")
        }
        let phase = spectrum.phase
        for _ in 0..<60 { spectrum.update(AudioBands(bass: 0.2), elapsed: 1.0 / 30) }
        precondition(spectrum.phase > phase + 0.9 && spectrum.middle.level == 0 && spectrum.treble.level == 0,
                     "Shared drift must continue even when only one frequency band plays.")
        for _ in 0..<210 { spectrum.update(AudioBands(), elapsed: 1.0 / 30) }
        precondition(spectrum.visibility == 0)
        let silentPhase = spectrum.phase
        spectrum.update(AudioBands(), elapsed: 1.0 / 30)
        precondition(spectrum.phase == silentPhase, "Silent drift must stop along with the invisible glow.")
        print("Passed: dark silence, softened attacks, steady brightness, shared drift, bounded levels, and time-based smoothing.")
    }
}
