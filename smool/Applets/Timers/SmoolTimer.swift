import Foundation

struct SmoolTimer: Identifiable, Codable, Equatable {
    enum State: Codable, Equatable {
        case running(deadline: Date)
        case paused(remaining: TimeInterval)
        case expired(at: Date)
    }

    let id: UUID
    let name: String
    var state: State

    var title: String { name.isEmpty ? "Timer" : name }

    var deadline: Date? {
        if case .running(let deadline) = state { return deadline }
        return nil
    }

    var isExpired: Bool {
        if case .expired = state { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    func remaining(at date: Date) -> TimeInterval {
        switch state {
        case .running(let deadline): max(0, deadline.timeIntervalSince(date))
        case .paused(let remaining): remaining
        case .expired: 0
        }
    }
}

/// Bare numbers are minutes. A colon always means minutes:seconds, never hours:minutes.
enum TimerDuration {
    static let maximum: TimeInterval = 7 * 24 * 60 * 60
    static let syntax = "25 min · 90 s · 2 h · 1:30 = 1 min 30 s"

    static func parse(_ input: String) -> TimeInterval? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        let duration: TimeInterval

        if parts.count == 2 {
            guard let minutes = integer(String(parts[0])),
                  parts[1].count == 2, let seconds = integer(String(parts[1])), seconds < 60 else { return nil }
            duration = minutes * 60 + seconds
        } else if parts.count == 1 {
            var number = text
            var multiplier = 60.0
            for (suffix, unit) in [("min", 60.0), ("s", 1.0), ("h", 3600.0)] {
                if text.hasSuffix(suffix) {
                    number = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                    multiplier = unit
                    break
                }
            }
            guard let value = integer(number) else { return nil }
            duration = value * multiplier
        } else {
            return nil
        }
        return duration > 0 && duration <= maximum ? duration : nil
    }

    private static func integer(_ value: String) -> Double? {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Double(value), number.isFinite else { return nil }
        return number
    }

    static func display(_ duration: TimeInterval) -> String {
        let seconds = Int(ceil(min(max(duration, 0), maximum)))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
