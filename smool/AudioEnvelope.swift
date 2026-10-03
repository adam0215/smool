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
    private(set) var visibility = 0.0
    private(set) var phase = 0.0

    var lift: Double { max(bass.lift, middle.lift, treble.lift) }

    mutating func update(_ bands: AudioBands, elapsed: Double) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        let elapsed = min(elapsed, 0.1)
        bass.update(rms: bands.bass, elapsed: elapsed)
        middle.update(rms: bands.middle, elapsed: elapsed)
        treble.update(rms: bands.treble, elapsed: elapsed)

        // Brightness follows the whole phrase, while individual bands shape the moving light.
        let level = max(bass.level, middle.level, treble.level)
        let target = pow(level, 0.65)
        visibility += (target - visibility) * (1 - exp(-elapsed / (target > visibility ? 0.45 : 0.85)))
        if level == 0, visibility < 0.02 { visibility = 0 }
        if visibility > 0 { phase += elapsed * (0.48 + level * 0.18) }
    }
}

/// Two smoothing stages give the light momentum without an abrupt start or stop.
struct AudioEnvelope: Equatable {
    private(set) var level = 0.0
    private(set) var pulse = 0.0
    private var baseline = 0.0
    private var energy = 0.0
    private var attack = 0.0

    var lift: Double { min(1, level * 0.8 + pulse * 0.35) }

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
            baseline = 0
        }
    }
}
