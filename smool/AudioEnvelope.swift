import Foundation

struct AudioBands: Equatable, Sendable {
    var bass = 0.0
    var middle = 0.0
    var treble = 0.0
}

struct AudioSpectrum: Equatable {
    private(set) var bass = AudioEnvelope()
    private(set) var middle = AudioEnvelope()
    private(set) var treble = AudioEnvelope()

    mutating func update(_ bands: AudioBands, elapsed: Double) {
        bass.update(rms: bands.bass, elapsed: elapsed)
        middle.update(rms: bands.middle, elapsed: elapsed)
        treble.update(rms: bands.treble, elapsed: elapsed)
    }
}

/// Two smoothing stages give the light momentum without an abrupt start or stop.
struct AudioEnvelope: Equatable {
    private(set) var level = 0.0
    private(set) var pulse = 0.0
    private(set) var phase = 0.0
    private var baseline = 0.0
    private var energy = 0.0
    private var attack = 0.0

    var lift: Double { min(1, level * 0.8 + pulse * 0.35) }
    var opacity: Double { min(1, pow(level, 1.3) + pulse * 0.2) }
    var colorMix: Double { min(1, level * 0.55 + pulse * 0.35 + (sin(phase) + 1) * 0.1) }

    mutating func update(rms: Double, elapsed: Double) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        let elapsed = min(elapsed, 0.1)
        let decibels = 20 * log10(max(rms.isFinite ? rms : 0, 0.000_001))
        let target = pow(min(1, max(0, (decibels + 48) / 42)), 1.5)
        let onset = min(1, max(0, (target - baseline - 0.08) * 3))
        baseline += (target - baseline) * (1 - exp(-elapsed / 0.65))
        attack += (onset - attack) * (1 - exp(-elapsed / (onset > attack ? 0.12 : 0.5)))
        pulse += (attack - pulse) * (1 - exp(-elapsed / 0.28))
        let duration = target > energy ? 0.22 : 0.65
        energy += (target - energy) * (1 - exp(-elapsed / duration))
        level += (energy - level) * (1 - exp(-elapsed / 0.3))
        if target == 0, level < 0.01, pulse < 0.01 {
            level = 0
            pulse = 0
            energy = 0
            attack = 0
        }
        phase += elapsed * level * 0.55
    }
}
