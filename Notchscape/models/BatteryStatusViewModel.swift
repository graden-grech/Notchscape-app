import Cocoa
import Combine
import Defaults
import SwiftUI

@MainActor
final class BatteryStatusViewModel: ObservableObject {
    static let shared = BatteryStatusViewModel()
    @Published private(set) var levelBattery: Float = 0
    @Published private(set) var maxCapacity: Float = 0
    @Published private(set) var isPluggedIn = false
    @Published private(set) var isCharging = false
    @Published private(set) var isInLowPowerMode = false
    @Published private(set) var timeToFullCharge = 0
    @Published private(set) var hasBattery = true
    @Published private(set) var dataAvailable = false
    @Published private(set) var isFullyCharged = false
    @Published private(set) var statusText = ""
    @Published private(set) var history: [BatteryHistorySample] = []
    private let managerBattery = BatteryActivityManager.shared
    private var observerID: Int?
    private var previous: BatteryReading?
    private var previousLowPower = false
    private var subscriptions = Set<AnyCancellable>()

    private init() {
        history = BatteryHistoryPolicy.retained(Defaults[.batteryHistory], now: Date())
        update(managerBattery.initializeBatteryInfo())
        observerID = managerBattery.addObserver { [weak self] snapshot in
            Task { @MainActor in self?.update(snapshot) }
        }
        Defaults.publisher(.batteryHistoryEnabled).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recordHistory() }.store(in: &subscriptions)
        Defaults.publisher(.batteryPresentation).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recordHistory() }.store(in: &subscriptions)
    }

    private func update(_ snapshot: BatteryInfo) {
        hasBattery = snapshot.hasBattery
        dataAvailable = snapshot.isAvailable && snapshot.hasBattery
        guard dataAvailable else {
            previous = nil
            statusText = hasBattery ? "Battery unavailable" : "No built-in battery"
            return
        }
        let reading = BatteryReading(level: Double(snapshot.currentCapacity), pluggedIn: snapshot.isPluggedIn,
            charging: snapshot.isCharging, fullyCharged: snapshot.isFullyCharged)
        let old = previous
        levelBattery = snapshot.currentCapacity
        maxCapacity = snapshot.maxCapacity
        isPluggedIn = snapshot.isPluggedIn
        isCharging = snapshot.isCharging
        isFullyCharged = snapshot.isFullyCharged
        isInLowPowerMode = snapshot.isInLowPowerMode
        timeToFullCharge = snapshot.timeToFullCharge
        statusText = reading.status
        previous = reading
        recordHistory()

        let threshold = BatteryPolicy.alert(from: old, to: reading, low20: Defaults[.batteryAlert20],
            low10: Defaults[.batteryAlert10], full: Defaults[.batteryAlertFull])
        let powerChanged = old != nil && (old?.pluggedIn != reading.pluggedIn
            || old?.charging != reading.charging || previousLowPower != isInLowPowerMode)
        previousLowPower = isInLowPowerMode
        guard Defaults[.showPowerStatusNotifications], old != nil else { return }
        if Defaults[.batteryPresentation] == .enhanced, let threshold {
            statusText = threshold.title
            NotchscapeCoordinator.shared.toggleExpandingView(status: true, type: .battery)
        } else if powerChanged {
            NotchscapeCoordinator.shared.toggleExpandingView(status: true, type: .battery)
        }
    }

    private func recordHistory() {
        guard Defaults[.batteryHistoryEnabled], dataAvailable,
              Defaults[.batteryPresentation] == .enhanced else { return }
        let updated = BatteryHistoryPolicy.adding(.init(date: Date(), level: Double(levelBattery),
            pluggedIn: isPluggedIn), to: history)
        if updated != history {
            history = updated
            Defaults[.batteryHistory] = updated
        }
    }

    func clearHistory() {
        history = []
        Defaults[.batteryHistory] = []
    }

    deinit { if let observerID { managerBattery.removeObserver(byId: observerID) } }
}
