import Foundation

/// A soft attack follows musical phrases; a longer release lets them settle.
struct AudioEnvelope: Equatable {
    private(set) var level = 0.0
    private(set) var phase = 0.0

    mutating func update(rms: Double, elapsed: Double) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        let elapsed = min(elapsed, 0.1)
        let decibels = 20 * log10(max(rms.isFinite ? rms : 0, 0.000_001))
        let target = min(1, max(0, (decibels + 54) / 48))
        let duration = target > level ? 0.45 : 1.6
        level += (target - level) * (1 - exp(-elapsed / duration))
        if target == 0, level < 0.001 { level = 0 }
        phase += elapsed * level * 0.24
    }
}
