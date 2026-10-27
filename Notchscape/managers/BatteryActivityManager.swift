import Foundation
import IOKit.ps

/// Atomic snapshots from system power notifications, without polling.
final class BatteryActivityManager {
    static let shared = BatteryActivityManager()
    private var batterySource: CFRunLoopSource?
    private var observers: [Int: (BatteryInfo) -> Void] = [:]
    private var nextID = 0

    private init() {
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<BatteryActivityManager>.fromOpaque(context).takeUnretainedValue().notifyBatteryChanges()
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() {
            batterySource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(notifyBatteryChanges),
            name: .NSProcessInfoPowerStateDidChange, object: nil)
    }

    @objc private func notifyBatteryChanges() {
        let snapshot = initializeBatteryInfo()
        DispatchQueue.main.async { [weak self] in self?.observers.values.forEach { $0(snapshot) } }
    }

    func initializeBatteryInfo() -> BatteryInfo {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return .unavailable
        }
        let descriptions = sources.compactMap {
            IOPSGetPowerSourceDescription(snapshot, $0)?.takeUnretainedValue() as? [String: Any]
        }
        if !sources.isEmpty && descriptions.isEmpty { return .unavailable }
        guard let description = descriptions.first(where: {
            ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
                && ($0[kIOPSIsPresentKey] as? Bool) != false
        }) else { return .absent }
        guard let current = description[kIOPSCurrentCapacityKey] as? NSNumber,
              let maximum = description[kIOPSMaxCapacityKey] as? NSNumber,
              let level = BatteryPolicy.percentage(current: current.doubleValue, maximum: maximum.doubleValue),
              let powerSource = description[kIOPSPowerSourceStateKey] as? String,
              let charging = description[kIOPSIsChargingKey] as? Bool else { return .unavailable }
        return BatteryInfo(hasBattery: true, isAvailable: true,
            isPluggedIn: powerSource == kIOPSACPowerValue, isCharging: charging,
            currentCapacity: Float(level), maxCapacity: maximum.floatValue,
            isInLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            timeToFullCharge: (description[kIOPSTimeToFullChargeKey] as? Int) ?? 0,
            isFullyCharged: (description[kIOPSIsChargedKey] as? Bool) ?? (level >= 100 && !charging))
    }

    func addObserver(_ observer: @escaping (BatteryInfo) -> Void) -> Int {
        let id = nextID
        nextID += 1
        observers[id] = observer
        return id
    }
    func removeObserver(byId id: Int) { observers[id] = nil }

    deinit {
        if let batterySource { CFRunLoopRemoveSource(CFRunLoopGetMain(), batterySource, .commonModes) }
        NotificationCenter.default.removeObserver(self)
    }
}

struct BatteryInfo {
    var hasBattery: Bool
    var isAvailable: Bool
    var isPluggedIn: Bool
    var isCharging: Bool
    var currentCapacity: Float
    // IOPS's charge scale is not battery health.
    var maxCapacity: Float
    var isInLowPowerMode: Bool
    var timeToFullCharge: Int
    var isFullyCharged: Bool
    static let absent = BatteryInfo(hasBattery: false, isAvailable: true, isPluggedIn: false,
        isCharging: false, currentCapacity: 0, maxCapacity: 0, isInLowPowerMode: false,
        timeToFullCharge: 0, isFullyCharged: false)
    static let unavailable = BatteryInfo(hasBattery: true, isAvailable: false, isPluggedIn: false,
        isCharging: false, currentCapacity: 0, maxCapacity: 0, isInLowPowerMode: false,
        timeToFullCharge: 0, isFullyCharged: false)
}
