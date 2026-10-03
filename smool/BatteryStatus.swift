import IOKit.ps

struct BatteryStatus {
    let percentage: Int
    let isCharging: Bool

    var symbolName: String {
        if isCharging { return "battery.100percent.bolt" }
        switch percentage {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var description: String {
        "Battery \(percentage) percent\(isCharging ? ", charging" : "")"
    }

    static func current() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  values[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = values[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = values[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }

            return BatteryStatus(
                percentage: min(100, max(0, Int((Double(current) / Double(maximum) * 100).rounded()))),
                isCharging: values[kIOPSIsChargingKey] as? Bool ?? false
            )
        }
        return nil
    }
}
