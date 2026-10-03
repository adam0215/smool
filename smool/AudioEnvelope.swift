import Foundation

/// Volume sets the glow's height; transients add a short, softened lift.
struct AudioEnvelope: Equatable {
    private(set) var level = 0.0
    private(set) var pulse = 0.0
    private(set) var phase = 0.0
    private var baseline = 0.0

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
        pulse += (onset - pulse) * (1 - exp(-elapsed / (onset > pulse ? 0.09 : 0.24)))
        let duration = target > level ? 0.18 : 0.3
        level += (target - level) * (1 - exp(-elapsed / duration))
        if target == 0, level < 0.01, pulse < 0.01 {
            level = 0
            pulse = 0
        }
        phase += elapsed * level * 0.4
    }
}
