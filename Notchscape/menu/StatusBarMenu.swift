import Foundation

/// Visibility choices, not package installation. Store availability is a
/// separate controller input and always wins over a saved visibility choice.
enum MenuBarModule: String, CaseIterable, Identifiable, Codable, Sendable {
    case dateTime, worldClock, battery, cpu, memory, network, storage
    case timer, stopwatch, countdown, keepAwake, music, devices, tools
    var id: Self { self }
    var title: String {
        switch self {
        case .dateTime: "Date & time"
        case .worldClock: "World clock"
        case .battery: "Battery"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network traffic"
        case .storage: "Storage"
        case .timer: "Timer"
        case .stopwatch: "Stopwatch"
        case .countdown: "Event countdown"
        case .keepAwake: "Keep Awake"
        case .music: "Music"
        case .devices: "Connected devices"
        case .tools: "Tools menu"
        }
    }
    var symbol: String {
        switch self {
        case .dateTime: "calendar"
        case .worldClock: "globe"
        case .battery: "battery.100percent"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "network"
        case .storage: "internaldrive"
        case .timer: "timer"
        case .stopwatch: "stopwatch"
        case .countdown: "calendar.badge.clock"
        case .keepAwake: "cup.and.saucer"
        case .music: "music.note"
        case .devices: "headphones"
        case .tools: "square.grid.2x2"
        }
    }
    /// Fixed point widths: no resizing or text measurement on sampling ticks.
    var width: Double {
        switch self {
        case .dateTime: 132
        case .worldClock: 74
        case .battery, .devices: 64
        case .cpu, .memory: 72
        case .network: 150
        case .storage: 78
        case .timer, .keepAwake: 86
        case .stopwatch, .countdown: 96
        case .music: 166
        case .tools: 30
        }
    }
    var needsSystemSampler: Bool { [.cpu, .memory, .network, .storage].contains(self) }
}

struct MenuBarModulePrivacyState: Equatable, Sendable {
    var consoleUnlocked: Bool
    var awake: Bool
    var sessionActive: Bool
    var presenting: Bool
    var permitsDisplay: Bool { consoleUnlocked && awake && sessionActive && !presenting }
}

enum MenuBarModulePolicy {
    static func selected(_ ids: [String]) -> Set<MenuBarModule> {
        Set(ids.prefix(1000).compactMap(MenuBarModule.init(rawValue:)))
    }
    static func active(selected: Set<MenuBarModule>, available: Set<MenuBarModule>,
                       privacy: MenuBarModulePrivacyState) -> Set<MenuBarModule> {
        privacy.permitsDisplay ? selected.intersection(available) : []
    }
    /// One UI clock, only where visible text actually advances. Other modules
    /// reuse existing provider publishers and never add per-item polling.
    static func clockInterval(active: Set<MenuBarModule>, stopwatchRunning: Bool,
                              eventCountingDown: Bool, keepAwakeActive: Bool) -> TimeInterval? {
        if (active.contains(.stopwatch) && stopwatchRunning)
            || (active.contains(.countdown) && eventCountingDown) { return 1 }
        if !active.intersection([.dateTime, .worldClock]).isEmpty
            || (active.contains(.keepAwake) && keepAwakeActive) { return 60 }
        return nil
    }
    static func percent(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite, (0...1).contains(fraction) else { return "—" }
        return "\(Int((fraction * 100).rounded()))%"
    }
    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        guard seconds < 86_400 * 1000 else { return "999d+" }
        let value = Int(seconds.rounded(.up))
        if value >= 86_400 { return "\(value / 86_400)d \((value / 3600) % 24)h" }
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60) }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
    static func rate(_ bytes: Double?) -> String {
        guard let bytes, bytes.isFinite, bytes >= 0 else { return "—" }
        var value = bytes
        let units = ["B", "K", "M", "G", "T"]
        var index = 0
        while value >= 1000 && index < units.count - 1 { value /= 1000; index += 1 }
        if value >= 1000 { return "999T+/s" }
        let number = value < 10 && index > 0 ? String(format: "%.1f", value) : String(format: "%.0f", value)
        return number + units[index] + "/s"
    }
    static func text(_ value: String, limit: Int = 160) -> String {
        let clean = value.unicodeScalars.prefix(2048).map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
        return String(clean.prefix(max(0, min(512, limit)))).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func worldClock(date: Date, zoneID: String) -> String? {
        guard date.timeIntervalSinceReferenceDate.isFinite, zoneID.count <= 100,
              let zone = TimeZone(identifier: zoneID) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }
}

/// Removing one reader cannot stop the dashboard or another visible client.
struct SystemSamplingDemand: Equatable, Sendable {
    private(set) var dashboardReaders = 0
    private(set) var menuBarRequested = false
    private(set) var suspended = false
    var shouldSample: Bool { !suspended && (dashboardReaders > 0 || menuBarRequested) }
    mutating func dashboardAppeared() { dashboardReaders += 1 }
    mutating func dashboardDisappeared() { dashboardReaders = max(0, dashboardReaders - 1) }
    mutating func setMenuBarRequested(_ value: Bool) { menuBarRequested = value }
    mutating func setSuspended(_ value: Bool) { suspended = value }
}

#if !MENU_BAR_MODULE_TEST
import AppKit
import Combine
import Defaults
import SwiftUI

extension Defaults.Keys {
    static let menuBarModules = Key<[String]>("menuBarModules", default: [])
    static let menuBarWorldClockZone = Key<String>("menuBarWorldClockZone", default: "Etc/UTC")
}

@MainActor
final class MenuBarModulesController: NSObject, ObservableObject, NSMenuDelegate {
    static let shared = MenuBarModulesController()
    @Published private(set) var availableModules = Set(MenuBarModule.allCases)
    private var items: [MenuBarModule: NSStatusItem] = [:]
    private var menuModules: [ObjectIdentifier: MenuBarModule] = [:]
    private var subscriptions = Set<AnyCancellable>()
    private var providerSubscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private var timerInterval: TimeInterval?
    private var active = Set<MenuBarModule>()
    private var started = false
    private var systemAwake = true
    private var displayAwake = true
    private var sessionActive = true
    private var lockFence = false
    private var deviceViewerActive = false
    private let deviceViewerID = UUID()
    private var renderQueued = false
    private let dateFormatter = DateFormatter()
    private override init() { super.init() }

    func start() {
        guard !started else { return }; started = true
        systemAwake = true; sessionActive = true; lockFence = !Self.consoleUnlocked
        displayAwake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
        configureDateFormatter()
        Defaults.publisher(.menuBarModules).receive(on: RunLoop.main).sink { [weak self] _ in self?.configure() }.store(in: &subscriptions)
        Defaults.publisher(.menuBarWorldClockZone).receive(on: RunLoop.main).sink { [weak self] _ in self?.render() }.store(in: &subscriptions)
        Defaults.publisher(.deviceControlsEnabled).receive(on: RunLoop.main).sink { [weak self] _ in self?.configure(forceProviders: true) }.store(in: &subscriptions)
        WorkspaceModeManager.shared.$session.receive(on: RunLoop.main).sink { [weak self] _ in self?.configure() }.store(in: &subscriptions)
        let center = NSWorkspace.shared.notificationCenter
        observe(center, NSWorkspace.willSleepNotification) { $0.systemAwake = false; $0.configure() }
        observe(center, NSWorkspace.didWakeNotification) {
            $0.systemAwake = true; $0.displayAwake = CGDisplayIsAsleep(CGMainDisplayID()) == 0; $0.configure()
        }
        observe(center, NSWorkspace.screensDidSleepNotification) { $0.displayAwake = false; $0.configure() }
        observe(center, NSWorkspace.screensDidWakeNotification) { $0.displayAwake = true; $0.configure() }
        observe(center, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionActive = false; $0.configure() }
        observe(center, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionActive = true; $0.configure() }
        observe(NotificationCenter.default, NSApplication.willTerminateNotification) { $0.stop() }
        observe(NotificationCenter.default, NSLocale.currentLocaleDidChangeNotification) { $0.configureDateFormatter(); $0.render() }
        observe(NotificationCenter.default, .NSSystemTimeZoneDidChange) { $0.configureDateFormatter(); $0.render() }
        observe(NotificationCenter.default, .NSSystemClockDidChange) { $0.render() }
        DistributedNotificationCenter.default().publisher(for: .init("com.apple.screenIsLocked"))
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.lockFence = true; self?.configure() }.store(in: &subscriptions)
        DistributedNotificationCenter.default().publisher(for: .init("com.apple.screenIsUnlocked"))
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self, Self.consoleUnlocked else { return }; lockFence = false; configure()
            }.store(in: &subscriptions)
        configure()
    }

    func stop() {
        guard started else { return }; started = false
        subscriptions.removeAll(); providerSubscriptions.removeAll()
        timer?.invalidate(); timer = nil; timerInterval = nil
        removeItems(); active = []
        SystemPerformanceManager.shared.setMenuBarSampling(false)
        SystemPerformanceManager.shared.setSamplingSuspended(true)
        releaseDeviceViewer()
    }

    /// Availability is independent of saved visibility. Removing a capability
    /// immediately removes its item and releases all of its provider demand.
    func setAvailableModules(_ modules: Set<MenuBarModule>) {
        guard availableModules != modules else { return }
        availableModules = modules; configure()
    }
    private var privacy: MenuBarModulePrivacyState {
        .init(consoleUnlocked: !lockFence && Self.consoleUnlocked,
              awake: systemAwake && displayAwake, sessionActive: sessionActive,
              presenting: WorkspaceModeManager.shared.active?.hidesPrivateContent == true)
    }
    private static var consoleUnlocked: Bool {
        LocalDesktopSessionPolicy.permitsDisplay(
            session: CGSessionCopyCurrentDictionary() as? [String: Any],
            currentUID: getuid(), effectiveUID: geteuid())
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping @MainActor (MenuBarModulesController) -> Void) {
        center.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }; action(self)
        }.store(in: &subscriptions)
    }

    private func configure(forceProviders: Bool = false) {
        guard started else { return }
        let state = privacy
        SystemPerformanceManager.shared.setSamplingSuspended(!state.permitsDisplay)
        let next = MenuBarModulePolicy.active(selected: MenuBarModulePolicy.selected(Defaults[.menuBarModules]),
                                              available: availableModules, privacy: state)
        if next != active || forceProviders {
            providerSubscriptions.removeAll()
            for module in Array(items.keys) where !next.contains(module) {
                if let item = items.removeValue(forKey: module) {
                    if let menu = item.menu { menu.cancelTracking(); menu.removeAllItems(); menuModules[ObjectIdentifier(menu)] = nil }
                    NSStatusBar.system.removeStatusItem(item)
                }
            }
            active = next
            for module in MenuBarModule.allCases where next.contains(module) && items[module] == nil {
                let item = NSStatusBar.system.statusItem(withLength: CGFloat(module.width))
                item.autosaveName = "Notchscape.module." + module.rawValue
                let menu = NSMenu(title: module.title); menu.delegate = self
                menuModules[ObjectIdentifier(menu)] = module; item.menu = menu
                if let button = item.button {
                    button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                    button.cell?.lineBreakMode = .byTruncatingTail
                    button.imagePosition = .imageLeading; button.image = symbol(module.symbol)
                    button.setAccessibilityLabel(module.title)
                }
                items[module] = item
            }
            configureProviders()
        }
        SystemPerformanceManager.shared.setMenuBarSampling(active.contains(where: \.needsSystemSampler))
        render()
    }
    private func removeItems() {
        for item in items.values {
            item.menu?.cancelTracking(); item.menu?.removeAllItems(); NSStatusBar.system.removeStatusItem(item)
        }
        items = [:]; menuModules = [:]
    }
    private func configureProviders() {
        if active.contains(where: \.needsSystemSampler) { observeProvider(SystemPerformanceManager.shared.objectWillChange) }
        if active.contains(.battery) { observeProvider(BatteryStatusViewModel.shared.objectWillChange) }
        if active.contains(.music) {
            let music = MusicManager.shared
            observeProvider(Publishers.CombineLatest4(music.$songTitle, music.$artistName, music.$isPlaying, music.$isPlayerIdle))
        }
        if active.contains(.timer) { observeProvider(NotchTimerManager.shared.objectWillChange) }
        if !active.intersection([.stopwatch, .keepAwake]).isEmpty { observeProvider(WorkspaceClockManager.shared.objectWillChange) }
        if active.contains(.countdown) { observeProvider(PinnedEventManager.shared.objectWillChange) }
        if active.contains(.devices), Defaults[.deviceControlsEnabled] {
            observeProvider(DeviceControlsManager.shared.objectWillChange)
            if !deviceViewerActive { deviceViewerActive = true; DeviceControlsManager.shared.appear(deviceViewerID) }
        } else { releaseDeviceViewer() }
    }
    private func releaseDeviceViewer() {
        if deviceViewerActive { deviceViewerActive = false; DeviceControlsManager.shared.disappear(deviceViewerID) }
    }
    private func observeProvider<P: Publisher>(_ publisher: P) where P.Failure == Never {
        publisher.receive(on: RunLoop.main).sink { [weak self] _ in self?.queueRender() }.store(in: &providerSubscriptions)
    }
    private func queueRender() {
        guard !renderQueued else { return }; renderQueued = true
        DispatchQueue.main.async { [weak self] in self?.renderQueued = false; self?.render() }
    }
    private func configureDateFormatter() {
        dateFormatter.locale = .current; dateFormatter.timeZone = .current
        dateFormatter.setLocalizedDateFormatFromTemplate("MMM d HH:mm")
    }
    private func render() {
        guard started, !active.isEmpty else { updateClock(interval: nil); return }
        guard privacy.permitsDisplay else { configure(); return }
        let now = Date()
        for module in active {
            let value = reading(module, now: now)
            guard let button = items[module]?.button else { continue }
            if button.title != value.0 { button.title = value.0 }
            let detail = module.title + " · " + value.1
            button.toolTip = detail; button.setAccessibilityValue(detail)
        }
        updateClock(interval: MenuBarModulePolicy.clockInterval(active: active,
            stopwatchRunning: active.contains(.stopwatch) && WorkspaceClockManager.shared.stopwatchRunning,
            eventCountingDown: active.contains(.countdown) && PinnedEventManager.shared.visibleEvent != nil,
            keepAwakeActive: active.contains(.keepAwake) && WorkspaceClockManager.shared.keepAwakeEnd != nil))
    }
    private func updateClock(interval: TimeInterval?) {
        guard interval != timerInterval else { return }
        timer?.invalidate(); timer = nil; timerInterval = interval
        guard let interval else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in Task { @MainActor in self?.render() } }
        timer.tolerance = interval == 1 ? 0.15 : 0.5
        if interval == 60 { timer.fireDate = Date().addingTimeInterval(60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60)) }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }

    private func reading(_ module: MenuBarModule, now: Date) -> (String, String) {
        switch module {
        case .dateTime: return (dateFormatter.string(from: now), now.formatted(date: .complete, time: .shortened))
        case .worldClock:
            let id = Defaults[.menuBarWorldClockZone]
            let time = MenuBarModulePolicy.worldClock(date: now, zoneID: id)
            return (time ?? "—", time.map { id + " · " + $0 } ?? "Choose a valid time zone in General Settings")
        case .battery:
            let battery = BatteryStatusViewModel.shared
            guard battery.hasBattery else { return ("AC", "No built-in battery") }
            let value = MenuBarModulePolicy.percent(battery.dataAvailable ? Double(battery.levelBattery) / 100 : nil)
            return (value, value + " · " + MenuBarModulePolicy.text(battery.statusText))
        case .cpu:
            let p = SystemPerformanceManager.shared
            let value = MenuBarModulePolicy.percent(p.cpuDataAvailable ? p.cpuUsage : nil)
            return (value, value + " CPU usage · Thermal: " + p.thermalState)
        case .memory:
            let p = SystemPerformanceManager.shared
            return (MenuBarModulePolicy.percent(p.memoryDataAvailable ? p.memoryUsage : nil),
                    p.memoryDataAvailable ? bytes(p.usedMemory) + " of " + bytes(p.totalMemory) + " used · " + p.memoryPressure : "Memory reading unavailable")
        case .storage:
            let p = SystemPerformanceManager.shared
            return (MenuBarModulePolicy.percent(p.diskDataAvailable ? p.diskUsage : nil),
                    p.diskDataAvailable ? bytes(UInt64(max(0, p.usedDisk))) + " of " + bytes(UInt64(max(0, p.totalDisk))) + " used" : "Storage reading unavailable")
        case .network:
            let p = SystemPerformanceManager.shared
            let down = MenuBarModulePolicy.rate(p.networkDataAvailable ? p.networkReceived : nil)
            let up = MenuBarModulePolicy.rate(p.networkDataAvailable ? p.networkSent : nil)
            let title = ("↓" + down + " ↑" + up).replacingOccurrences(of: "/s", with: "")
            return (title, "Receive " + down + " · Send " + up + " · Bytes per second, physical en* interfaces only; passive counters, no speed test")
        case .timer:
            let clock = NotchTimerManager.shared
            guard let end = clock.endDate else { return (clock.justFinished ? "Done" : "Off", clock.justFinished ? "Timer finished" : "No timer running") }
            let duration = MenuBarModulePolicy.duration(max(0, end.timeIntervalSince(now)))
            return (duration, MenuBarModulePolicy.text(clock.label) + " · " + duration + " remaining")
        case .stopwatch:
            let clock = WorkspaceClockManager.shared
            let duration = MenuBarModulePolicy.duration(clock.elapsed.rounded(.down))
            return (duration, (clock.stopwatchRunning ? "Running · " : "Paused · ") + duration)
        case .countdown:
            guard let event = PinnedEventManager.shared.visibleEvent else { return ("—", "No currently available pinned event; choose one in Workspace Tools") }
            let upcoming = event.start > now
            let duration = MenuBarModulePolicy.duration(max(0, (upcoming ? event.start : event.end).timeIntervalSince(now)))
            return (duration, MenuBarModulePolicy.text(event.title) + (upcoming ? " starts in " : " ends in ") + duration)
        case .keepAwake:
            guard let end = WorkspaceClockManager.shared.keepAwakeEnd else { return ("Off", "Timed Keep Awake is off; showing this item never starts it") }
            let minutes = max(0, Int(ceil(end.timeIntervalSince(now) / 60)))
            return ("\(minutes)m", "Timed Keep Awake ends at " + end.formatted(date: .omitted, time: .shortened))
        case .music:
            let music = MusicManager.shared
            guard !music.isPlayerIdle else { return ("Not playing", "No current track supplied by the music provider") }
            let title = MenuBarModulePolicy.text(music.songTitle), artist = MenuBarModulePolicy.text(music.artistName)
            return (title.isEmpty ? "Music" : title, (music.isPlaying ? "Playing · " : "Paused · ") + title + (artist.isEmpty ? "" : " — " + artist))
        case .devices:
            guard Defaults[.deviceControlsEnabled] else { return ("—", "Device controls are off; enable them in Tools settings") }
            let device = DeviceControlsManager.shared
            guard !device.devices.isEmpty else { return ("—", device.refreshing ? "Reading paired devices…" : "No paired-device data supplied") }
            let connected = device.devices.filter(\.connected)
            return ("\(connected.count)", connected.isEmpty ? "No connected devices in the current snapshot" : connected.map { MenuBarModulePolicy.text($0.name, limit: 60) }.joined(separator: ", "))
        case .tools: return ("", "Open existing Notchscape tools")
        }
    }
    private func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(min(UInt64(Int64.max), value)), countStyle: .binary) }
    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true; image?.size = .init(width: 14, height: 14); return image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard privacy.permitsDisplay, let module = menuModules[ObjectIdentifier(menu)], active.contains(module) else { return }
        let value = reading(module, now: Date())
        addInfo(module.title, to: menu)
        if module != .tools { addInfo(value.1, to: menu); menu.addItem(.separator()) }
        switch module {
        case .dateTime: addAction("Calendar Settings…", command: "settings:Calendar", to: menu)
        case .worldClock:
            for zone in MenuBarModuleSettingsSection.zones {
                let item = addAction(zone.replacingOccurrences(of: "_", with: " ") + " · " + (MenuBarModulePolicy.worldClock(date: Date(), zoneID: zone) ?? "—"), command: "zone:" + zone, to: menu)
                item.state = Defaults[.menuBarWorldClockZone] == zone ? .on : .off
            }
        case .battery: addAction("Battery Settings…", command: "settings:Battery", to: menu)
        case .cpu, .memory, .network, .storage:
            addAction("Open Activity Monitor", command: "activity-monitor", to: menu)
            addAction("System & Power Settings…", command: "settings:System", to: menu)
        case .timer:
            for minutes in [5,15,25,60] { addAction("Start \(minutes)-minute timer", command: "timer:\(minutes)", to: menu) }
            if NotchTimerManager.shared.endDate != nil { addAction("Cancel timer", command: "timer-cancel", to: menu) }
        case .stopwatch:
            addAction(WorkspaceClockManager.shared.stopwatchRunning ? "Pause stopwatch" : "Start stopwatch", command: "stopwatch-toggle", to: menu)
            addAction("Reset stopwatch", command: "stopwatch-reset", to: menu)
            addAction("Workspace Tools…", command: "action:workspace", to: menu)
        case .countdown:
            addAction("Workspace Tools…", command: "action:workspace", to: menu)
            addAction("Calendar Settings…", command: "settings:Calendar", to: menu)
        case .keepAwake:
            if WorkspaceClockManager.shared.keepAwakeEnd != nil { addAction("Stop Keep Awake", command: "awake-stop", to: menu) }
            else { for minutes in [15,30,60,120] { addAction("Keep awake for \(minutes) minutes", command: "awake:\(minutes)", to: menu) } }
        case .music:
            addAction(MusicManager.shared.isPlaying ? "Pause" : "Play", command: "music-play-pause", to: menu)
            addAction("Next track", command: "music-next", to: menu)
            addAction("Previous track", command: "music-previous", to: menu)
            addAction("Open music app", command: "music-open", to: menu)
        case .devices:
            if Defaults[.deviceControlsEnabled] {
                for device in DeviceControlsManager.shared.devices.filter(\.connected).prefix(12) {
                    let levels = [("Battery", device.battery), ("L", device.left), ("R", device.right), ("Case", device.caseBattery)]
                        .compactMap { label, value -> String? in guard let value, (0...100).contains(value) else { return nil }; return "\(label) \(value)%" }
                    addInfo(MenuBarModulePolicy.text(device.name, limit: 70) + (levels.isEmpty ? "" : " · " + levels.joined(separator: " · ")), to: menu)
                }
            }
            addAction("Open Devices…", command: "devices-open", to: menu)
        case .tools:
            for action in WorkspaceActions.all where ["tools", "workspace", "capture", "windows", "wallpapers", "scratchpad"].contains(action.id) {
                addAction(action.title + "…", command: "action:" + action.id, to: menu)
            }
        }
        menu.addItem(.separator())
        addAction("Menu Bar Modules Settings…", command: "settings:General", to: menu)
    }
    private func addInfo(_ text: String, to menu: NSMenu) {
        let item = NSMenuItem(title: MenuBarModulePolicy.text(text, limit: 256), action: nil, keyEquivalent: "")
        item.isEnabled = false; menu.addItem(item)
    }
    @discardableResult
    private func addAction(_ title: String, command: String, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
        item.target = self; item.representedObject = command; menu.addItem(item); return item
    }
    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard started, privacy.permitsDisplay, let menu = sender.menu, let module = menuModules[ObjectIdentifier(menu)],
              active.contains(module), availableModules.contains(module), let command = sender.representedObject as? String else { return }
        if command.hasPrefix("settings:") { SettingsWindowController.shared.showWindow(section: String(command.dropFirst(9))) }
        else if command.hasPrefix("action:") { WorkspaceActions.run(String(command.dropFirst(7))) }
        else if command.hasPrefix("zone:"), let zone = TimeZone(identifier: String(command.dropFirst(5))) { Defaults[.menuBarWorldClockZone] = zone.identifier }
        else if command.hasPrefix("timer:"), let minutes = Int(command.dropFirst(6)), [5,15,25,60].contains(minutes) { NotchTimerManager.shared.start(minutes: minutes) }
        else if command.hasPrefix("awake:"), let minutes = Int(command.dropFirst(6)), [15,30,60,120].contains(minutes) { WorkspaceClockManager.shared.startKeepAwake(minutes: minutes) }
        else {
            switch command {
            case "activity-monitor": SystemPerformanceManager.shared.openActivityMonitor()
            case "timer-cancel": NotchTimerManager.shared.cancel()
            case "stopwatch-toggle": WorkspaceClockManager.shared.toggleStopwatch()
            case "stopwatch-reset": WorkspaceClockManager.shared.resetStopwatch()
            case "awake-stop": WorkspaceClockManager.shared.stopKeepAwake()
            case "music-play-pause": MusicManager.shared.playPause()
            case "music-next": MusicManager.shared.nextTrack()
            case "music-previous": MusicManager.shared.previousTrack()
            case "music-open": MusicManager.shared.openMusicApp()
            case "devices-open": NotchToolsWindowController.shared.show(.devices)
            default: break
            }
        }
        render()
    }
}

struct MenuBarModuleSettingsSection: View {
    @Default(.menuBarModules) private var selectedIDs
    @Default(.menuBarWorldClockZone) private var zone
    @ObservedObject private var controller = MenuBarModulesController.shared
    @State private var expanded = false
    static let zones = ["Etc/UTC", "America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles",
                        "America/Sao_Paulo", "Europe/London", "Europe/Paris", "Europe/Berlin", "Asia/Dubai",
                        "Asia/Kolkata", "Asia/Singapore", "Asia/Tokyo", "Australia/Sydney", "Pacific/Auckland"]
    private var selected: Set<MenuBarModule> { MenuBarModulePolicy.selected(selectedIDs) }
    var body: some View {
        Section {
            DisclosureGroup("Choose menu bar items", isExpanded: $expanded) {
                ForEach(MenuBarModule.allCases) { module in
                    Toggle(isOn: visibility(module)) { Label(module.title, systemImage: module.symbol) }
                        .disabled(!controller.availableModules.contains(module))
                }
            }
            LabeledContent("Selected", value: "\(selected.intersection(controller.availableModules).count) items")
            if selected.contains(.worldClock), controller.availableModules.contains(.worldClock) {
                Picker("World clock time zone", selection: $zone) {
                    if !Self.zones.contains(zone) { Text(zone).tag(zone) }
                    ForEach(Self.zones, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                }
            }
            if !selected.isEmpty { Button("Hide all module items") { selectedIDs = [] } }
        } header: { Text("Menu Bar Modules") } footer: {
            Text("Choose readouts for your menu bar. They pause while your Mac is locked, asleep or in Presentation mode. macOS may hide items when space is limited.")
        }
    }
    private func visibility(_ module: MenuBarModule) -> Binding<Bool> {
        Binding(get: { selected.contains(module) }, set: { value in
            var next = selected
            if value { next.insert(module) } else { next.remove(module) }
            selectedIDs = MenuBarModule.allCases.filter { next.contains($0) }.map(\.rawValue)
        })
    }
}
#endif
