import Foundation
import IOKit.ps

struct BatteryInfo: Equatable {
    var hasBattery: Bool
    var level: Int
    var onBattery: Bool
    var charging: Bool

    static let none = BatteryInfo(hasBattery: false, level: 100, onBattery: false, charging: false)

    static func current() -> BatteryInfo {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return .none }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }
            let cur = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let state = desc[kIOPSPowerSourceStateKey] as? String
            return BatteryInfo(
                hasBattery: true,
                level: max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur,
                onBattery: state == kIOPSBatteryPowerValue,
                charging: desc[kIOPSIsChargingKey] as? Bool ?? false
            )
        }
        return .none
    }

    var symbol: String {
        guard hasBattery else { return "powerplug.fill" }
        if !onBattery { return "battery.100.bolt" }
        switch level {
        case 88...: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        default: return "battery.0"
        }
    }

    var label: String {
        guard hasBattery else { return "Adaptör" }
        return "%\(level)"
    }

    var sourceLabel: String {
        guard hasBattery else { return "Pil yok" }
        if charging { return "Şarj oluyor" }
        return onBattery ? "Pilde" : "Adaptörde"
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: return "Normal"
        case .fair: return "Ilık"
        case .serious: return "Sıcak"
        case .critical: return "Kritik"
        @unknown default: return "?"
        }
    }

    var symbol: String {
        switch self {
        case .nominal: return "thermometer.low"
        case .fair: return "thermometer.medium"
        default: return "thermometer.high"
        }
    }
}
