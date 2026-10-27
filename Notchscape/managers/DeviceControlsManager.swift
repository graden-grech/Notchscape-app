import AppKit
import CoreAudio
import Defaults
import IOBluetooth
import IOKit
import Combine
import UserNotifications

struct NotchBluetoothDevice: Identifiable, Equatable {
    var id: String
    var name: String
    var connected: Bool
    var battery: Int?
    var left: Int?
    var right: Int?
    var caseBattery: Int?
    var symbol: String {
        let value = name.lowercased()
        if value.contains("airpods") { return "airpodspro" }
        if value.contains("keyboard") { return "keyboard" }
        if value.contains("trackpad") { return "magictrackpad" }
        if value.contains("mouse") { return "magicmouse" }
        if value.contains("head") || value.contains("beats") { return "headphones" }
        return "hifispeaker"
    }
}
struct NotchAudioOutput: Identifiable, Equatable {
    var id: AudioDeviceID
    var name: String
}

@MainActor
final class DeviceControlsManager: NSObject, ObservableObject {
    static let shared = DeviceControlsManager()
    @Published private(set) var devices: [NotchBluetoothDevice] = []
    @Published private(set) var outputs: [NotchAudioOutput] = []
    @Published private(set) var selectedOutput: AudioDeviceID = 0
    @Published private(set) var refreshing = false
    @Published private(set) var connecting: String?
    @Published private(set) var message: String?
    private var timer: Timer?
    private var connectionTimeout: Task<Void, Never>?
    private let worker = DispatchQueue(label: "notch.devices", qos: .utility)
    private var viewers = Set<UUID>()
    private var reportedBattery: [String: [String: Int]] = [:]
    private var lastBatteryReport = Date.distantPast
    private var subscriptions = Set<AnyCancellable>()
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [IOBluetoothUserNotification] = []
    private var lowBatteryReported = Set<String>()
    private override init() { super.init() }

    func start() {
        guard subscriptions.isEmpty else { return }
        Defaults.publisher(.deviceControlsEnabled).receive(on: RunLoop.main).sink { [weak self] change in
            if !change.newValue { self?.stop() } else { self?.configureNotifications() }
        }.store(in: &subscriptions)
        Defaults.publisher(.deviceConnectionAlerts).receive(on: RunLoop.main).sink { [weak self] _ in
            self?.configureNotifications()
        }.store(in: &subscriptions)
        Defaults.publisher(.deviceLowBatteryAlerts).receive(on: RunLoop.main).sink { [weak self] _ in
            self?.configureNotifications(); self?.configurePolling()
        }.store(in: &subscriptions)
        WorkspaceModeManager.shared.$session.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            if !WorkspaceAccess.privateToolsAllowed { stop() }
            else { configureNotifications(); configurePolling() }
        }.store(in: &subscriptions)
    }
    func requestConnectionNotifications() {
        guard Defaults[.deviceControlsEnabled], Defaults[.deviceConnectionAlerts] || Defaults[.deviceLowBatteryAlerts] else { return }
        Task {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) == true
            if granted { configureNotifications() }
            else { Defaults[.deviceConnectionAlerts] = false; Defaults[.deviceLowBatteryAlerts] = false; message = "Device notifications are off. You can allow them in System Settings." }
        }
    }
    func configureNotifications() {
        connectNotification?.unregister(); connectNotification = nil
        disconnectNotifications.forEach { $0.unregister() }; disconnectNotifications = []
        guard Defaults[.deviceControlsEnabled], Defaults[.deviceConnectionAlerts] || Defaults[.deviceLowBatteryAlerts], WorkspaceAccess.privateToolsAllowed,
              let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session["CGSSessionScreenIsLocked"] as? Bool != true else { return }
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        observeDisconnects()
        configurePolling()
    }
    private func observeDisconnects() {
        disconnectNotifications.forEach { $0.unregister() }; disconnectNotifications = []
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] where device.isConnected() {
            if let token = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:))) {
                disconnectNotifications.append(token)
            }
        }
    }
    @objc nonisolated private func deviceConnected(_ notification: IOBluetoothUserNotification!, device: IOBluetoothDevice!) {
        guard let device, device.isPaired() else { return }
        let name = String((device.name ?? "Bluetooth device").prefix(100))
        Task { @MainActor [weak self] in self?.notify(name, connected: true); self?.observeDisconnects(); self?.refresh() }
    }
    @objc nonisolated private func deviceDisconnected(_ notification: IOBluetoothUserNotification!, device: IOBluetoothDevice!) {
        guard let device, device.isPaired() else { return }
        let name = String((device.name ?? "Bluetooth device").prefix(100))
        Task { @MainActor [weak self] in self?.notify(name, connected: false); self?.refresh() }
    }
    private func notify(_ name: String, connected: Bool) {
        guard Defaults[.deviceControlsEnabled], Defaults[.deviceConnectionAlerts], WorkspaceAccess.privateToolsAllowed,
              let session = CGSessionCopyCurrentDictionary() as? [String: Any], session["CGSSessionScreenIsLocked"] as? Bool != true else { return }
        let content = UNMutableNotificationContent()
        content.title = connected ? "Bluetooth connected" : "Bluetooth disconnected"
        content.body = name
        UNUserNotificationCenter.current().add(.init(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func appear(_ id: UUID) {
        viewers.insert(id)
        guard Defaults[.deviceControlsEnabled] else { return }
        refresh(includeBatteryReport: Date().timeIntervalSince(lastBatteryReport) >= 300)
        configurePolling()
    }
    func disappear(_ id: UUID) {
        viewers.remove(id)
        configurePolling()
    }
    private func configurePolling() {
        timer?.invalidate(); timer = nil
        guard Defaults[.deviceControlsEnabled], WorkspaceAccess.privateToolsAllowed,
              !viewers.isEmpty || Defaults[.deviceLowBatteryAlerts] else { return }
        let seconds: TimeInterval = viewers.isEmpty ? 120 : 30
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        timer?.tolerance = seconds/6
    }
    func stop() {
        timer?.invalidate(); timer = nil; devices = []; outputs = []
        connectNotification?.unregister(); connectNotification = nil
        disconnectNotifications.forEach { $0.unregister() }; disconnectNotifications = []
    }

    func refresh(includeBatteryReport: Bool = false) {
        guard Defaults[.deviceControlsEnabled], WorkspaceAccess.privateToolsAllowed, !refreshing else { return }
        refreshing = true
        let readReport = includeBatteryReport && Date().timeIntervalSince(lastBatteryReport) >= 30
        let cache = Date().timeIntervalSince(lastBatteryReport) < 300 ? reportedBattery : [:]
        worker.async { [weak self] in
            let report = readReport ? Self.batteryReport() : cache
            let snapshot = Self.readDevices(report: report)
            let audio = Self.readAudio()
            Task { @MainActor in
                guard let self else { return }; self.refreshing = false
                guard Defaults[.deviceControlsEnabled], WorkspaceAccess.privateToolsAllowed else { return }
                self.devices = snapshot; self.outputs = audio.0; self.selectedOutput = audio.1
                self.checkLowBattery(snapshot)
                if readReport { self.reportedBattery = report; self.lastBatteryReport = Date() }
            }
        }
    }

    func connect(_ model: NotchBluetoothDevice) {
        guard Defaults[.deviceControlsEnabled], connecting == nil,
              let device = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?.first(where: { $0.addressString == model.id }) else { return }
        connecting = model.id; message = nil
        // Supplying a delegate makes this asynchronous; never wait for a
        // Bluetooth page timeout on SwiftUI's main thread.
        let status = device.openConnection(self)
        guard status == kIOReturnSuccess else { connecting = nil; message = "Couldn’t connect. Check Bluetooth and try again."; return }
        connectionTimeout?.cancel()
        connectionTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard let self, connecting == model.id else { return }
            connecting = nil; message = "Connection timed out. Open Bluetooth settings to finish connecting."; refresh()
        }
    }
    private func checkLowBattery(_ devices: [NotchBluetoothDevice]) {
        guard Defaults[.deviceLowBatteryAlerts], WorkspaceAccess.privateToolsAllowed else { return }
        let threshold = max(5, min(30, Defaults[.deviceLowBatteryThreshold]))
        for device in devices where device.connected {
            guard let level = [device.battery, device.left, device.right, device.caseBattery].compactMap({ $0 }).min() else { continue }
            if level >= threshold+10 { lowBatteryReported.remove(device.id) }
            guard level <= threshold, lowBatteryReported.insert(device.id).inserted else { continue }
            let content = UNMutableNotificationContent(); content.title = "Accessory battery low"
            content.body = "\(device.name): \(level)% remaining"
            UNUserNotificationCenter.current().add(.init(identifier: "notchscape-low-battery-\(DeviceBatteryPolicy.address(device.id))", content: content, trigger: nil))
        }
    }
    @objc nonisolated func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            connectionTimeout?.cancel(); connecting = nil
            message = status == kIOReturnSuccess ? "Connected" : "Couldn’t connect. Try Bluetooth settings."
            refresh()
        }
    }
    func selectOutput(_ id: AudioDeviceID) {
        guard Defaults[.deviceControlsEnabled], outputs.contains(where: { $0.id == id }) else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = id
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                               UInt32(MemoryLayout<AudioDeviceID>.size), &value)
        if status == noErr { selectedOutput = id; message = nil }
        else { message = "macOS couldn’t change the audio output." }
    }

    private nonisolated static func readDevices(report: [String: [String: Int]]) -> [NotchBluetoothDevice] {
        let batteries = batteryRegistry()
        return (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).prefix(40).map { device in
            let address = device.addressString ?? ""
            let values = batteries[DeviceBatteryPolicy.address(address)] ?? [:]
            let reported = report[DeviceBatteryPolicy.address(address)] ?? [:]
            let connected = device.isConnected()
            return NotchBluetoothDevice(id: address, name: device.name ?? "Bluetooth device", connected: connected,
                battery: connected ? DeviceBatteryPolicy.percent(values["BatteryPercent"]) ?? reported["battery"] : nil,
                left: connected ? DeviceBatteryPolicy.percent(values["BatteryPercentLeft"]) ?? reported["left"] : nil,
                right: connected ? DeviceBatteryPolicy.percent(values["BatteryPercentRight"]) ?? reported["right"] : nil,
                caseBattery: connected ? DeviceBatteryPolicy.percent(values["BatteryPercentCase"]) ?? reported["case"] : nil)
        }.filter { !$0.id.isEmpty }.sorted { $0.connected != $1.connected ? $0.connected : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private nonisolated static func batteryReport() -> [String: [String: Int]] {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 6, execute: timeout)
            defer { timeout.cancel() }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, data.count <= 1_000_000,
                  let object = try? JSONSerialization.jsonObject(with: data) else { return [:] }
            return DeviceBatteryPolicy.report(object)
        } catch { return [:] }
    }
    /// Read only published registry properties, matched by exact address.
    /// There is no private Bluetooth API, cache scraping, or invented battery value.
    private nonisolated static func batteryRegistry() -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        for kind in ["AppleDeviceManagementHIDEventService", "AppleBluetoothHIDKeyboard", "AppleBluetoothHIDMouse", "AppleBluetoothHIDMultiTouch", "IOBluetoothDevice"] {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kind), &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            var object = IOIteratorNext(iterator)
            while object != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(object, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let values = properties?.takeRetainedValue() as? [String: Any] {
                    let address = ["DeviceAddress", "BluetoothDeviceAddress", "BD_ADDR", "Address"].compactMap { values[$0] as? String }.first
                    if let address, !DeviceBatteryPolicy.address(address).isEmpty {
                        result[DeviceBatteryPolicy.address(address), default: [:]].merge(values) { _, new in new }
                    }
                }
                IOObjectRelease(object); object = IOIteratorNext(iterator)
            }
        }
        return result
    }
    private nonisolated static func readAudio() -> ([NotchAudioOutput], AudioDeviceID) {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return ([], 0) }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!) }
        guard status == noErr else { return ([], 0) }
        let outputs = ids.compactMap { id -> NotchAudioOutput? in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name) == noErr else { return nil }
            return .init(id: id, name: name?.takeRetainedValue() as String? ?? "Audio output")
        }
        var selected: AudioDeviceID = 0; var selectedSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        address.mSelector = kAudioHardwarePropertyDefaultOutputDevice
        _ = AudioObjectGetPropertyData(system, &address, 0, nil, &selectedSize, &selected)
        return (outputs, selected)
    }
}
