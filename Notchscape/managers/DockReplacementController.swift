import AppKit
import OSLog
import Combine
import Defaults
import EventKit
import SwiftUI
import UniformTypeIdentifiers

extension Defaults.Keys {
    static let dockReplacementEnabled = Key<Bool>("dockReplacementEnabled", default: false)
    static let dockReplacementLayoutData = Key<Data?>("dockReplacementLayoutData", default: nil)
    static let dockReplacementPinsData = Key<Data?>("dockReplacementPinsData", default: nil)
    static let dockReplacementIconSize = Key<Double>("dockReplacementIconSize", default: 48)
    static let dockReplacementOverflow = Key<String>("dockReplacementOverflow", default: "pages")
}

@MainActor struct DockReplacementApp: Identifiable {
    let id: UUID
    let title: String
    let icon: NSImage
    let isRunning: Bool
    var isPinned = false
}

@MainActor struct DockReplacementFaceSnapshot {
    var primary: String
    var secondary: String
    var symbol: String
    var progress: Double? = nil
    var artwork: NSImage? = nil
    var isActive = false
    var details: [String] = []
    var metrics: [DockReplacementMetric] = []
}

struct DockReplacementMetric: Identifiable {
    let title: String
    let fraction: Double?
    var id: String { title }
    var value: String { DockReplacementPolicy.percentage(fraction) }
}

/// Optional original horizontal surface. The first preview deliberately does
/// not alter system Dock preferences; its layout is independent of old previews.
@MainActor
final class DockReplacementController: NSObject, ObservableObject {
    static let shared = DockReplacementController()
    @Published private(set) var layout = DockReplacementLayout.starter
    @Published private(set) var apps: [DockReplacementApp] = []
    @Published private(set) var currentDate = Date()
    @Published private(set) var expandedWidgetID: UUID?
    @Published private(set) var barLayout: DockReplacementBarLayout?
    @Published private(set) var isVisible = false
    @Published private(set) var isLayoutReadOnly = false
    @Published var errorMessage: String?
    private var bar: DockReplacementPanel?
    private var card: DockReplacementPanel?
    private var picker: NSOpenPanel?
    private var subscriptions = Set<AnyCancellable>()
    private var tick: Task<Void, Never>?
    private var systemLease = false
    private var calendarTask: Task<Void, Never>?
    private var unlockTask: Task<Void, Never>?
    private var localClick: Any?
    private var globalClick: Any?
    private var started = false
    private var locked = true
    private var awake = true
    private var activeSession = true
    private var generation: UInt64 = 0
    private var page = 0
    private var targetScreen: NSScreen?
    private var upcoming: [EventModel] = []
    private var lastCalendarRefresh: Date?
    private var lastWeatherCheck: ContinuousClock.Instant?
    private var appURLs: [UUID: URL] = [:]
    private var appIDs: [URL: UUID] = [:]
    private var pins: [DockWorkspacePin] = []
    private var pinsReadOnly = false
    private var calculators: [UUID: String] = [:]
    private let clock = ContinuousClock()
    private struct TimerState {
        var remaining: Double
        var started: ContinuousClock.Instant?
    }
    private var timers: [UUID: TimerState] = [:]

    private override init() { super.init(); reload() }

    func start() {
        guard !started else { return }; started = true
        DockVisibilityController.shared.start()
        locked = !consoleUnlocked
        awake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
        Defaults.publisher(.dockReplacementEnabled).receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let enabled = Defaults[.dockReplacementEnabled]
                DockFocusDiagnostics.shared.barPreferenceChanged(enabled)
                reconcile()
            }.store(in: &subscriptions)
        Defaults.publisher(.dockHideSystemDock).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reconcileNativeDockVisibility() }.store(in: &subscriptions)
        Defaults.publisher(.dockReplacementLayoutData).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload(); self?.reconcile() }.store(in: &subscriptions)
        Defaults.publisher(.dockReplacementPinsData).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reloadPins(); self?.reloadApps(); self?.positionBar() }.store(in: &subscriptions)
        Defaults.publisher(.dockReplacementIconSize).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.positionBar() }.store(in: &subscriptions)
        Defaults.publisher(.dockReplacementOverflow).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.collapse(); self?.positionBar() }.store(in: &subscriptions)
        WorkspaceModeManager.shared.$session.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reconcile() }.store(in: &subscriptions)
        MusicManager.shared.objectWillChange.throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in if self?.isVisible == true { self?.objectWillChange.send() } }.store(in: &subscriptions)
        BatteryStatusViewModel.shared.objectWillChange.throttle(for: .milliseconds(250), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in if self?.isVisible == true { self?.objectWillChange.send() } }.store(in: &subscriptions)
        SystemPerformanceManager.shared.objectWillChange.throttle(for: .milliseconds(300), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in if self?.systemLease == true { self?.objectWillChange.send() } }.store(in: &subscriptions)
        WeatherManager.shared.objectWillChange.throttle(for: .milliseconds(300), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                guard let self, isVisible, layout.widgets.contains(where: { $0.kind == .weather }) else { return }
                objectWillChange.send()
            }.store(in: &subscriptions)
        Defaults.publisher(.weatherEnabled).receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, isVisible else { return }
                objectWillChange.send(); refreshWeatherIfNeeded()
            }.store(in: &subscriptions)
        CalendarManager.shared.$selectedCalendarIDs.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                generation &+= 1; calendarTask?.cancel(); calendarTask = nil
                upcoming = []; lastCalendarRefresh = nil
                objectWillChange.send(); refreshCalendarIfNeeded()
            }.store(in: &subscriptions)
        let workspace = NSWorkspace.shared.notificationCenter
        Publishers.MergeMany([NSWorkspace.didActivateApplicationNotification,
                              NSWorkspace.didLaunchApplicationNotification,
                              NSWorkspace.didTerminateApplicationNotification].map { workspace.publisher(for: $0) })
            .receive(on: RunLoop.main).sink { note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let phase = note.name == NSWorkspace.didActivateApplicationNotification ? "appActivated"
                    : note.name == NSWorkspace.didLaunchApplicationNotification ? "appLaunched" : "appTerminated"
                DockFocusDiagnostics.shared.record(phase, target: app.bundleIdentifier, targetPID: app.processIdentifier)
            }.store(in: &subscriptions)
        observe(workspace, NSWorkspace.didLaunchApplicationNotification) { $0.reloadApps(); $0.positionBar() }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { $0.reloadApps(); $0.positionBar() }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.awake = false; $0.suspend() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.awake = false; $0.suspend() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.awake = CGDisplayIsAsleep(CGMainDisplayID()) == 0; $0.reconcile() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.awake = true; $0.reconcile() }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.activeSession = false; $0.suspend() }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.activeSession = true; $0.refreshUnlock() }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { $0.targetScreen = nil; $0.reconcile() }
        observe(NotificationCenter.default, NSApplication.didHideNotification) { $0.suspend() }
        observe(NotificationCenter.default, NSApplication.didUnhideNotification) { $0.reconcile() }
        observe(NotificationCenter.default, .NSSystemClockDidChange) { $0.lastCalendarRefresh = nil; $0.refreshTime() }
        observe(NotificationCenter.default, .NSSystemTimeZoneDidChange) { $0.refreshTime() }
        DistributedNotificationCenter.default().publisher(for: .init("com.apple.screenIsLocked"))
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.locked = true; self?.suspend() }.store(in: &subscriptions)
        DistributedNotificationCenter.default().publisher(for: .init("com.apple.screenIsUnlocked"))
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshUnlock() }.store(in: &subscriptions)
        reconcile()
    }

    func stop() {
        started = false; suspend(); subscriptions.removeAll()
        unlockTask?.cancel(); unlockTask = nil
        bar = nil; card = nil; timers.removeAll(); calculators.removeAll()
    }

    func show() {
        start()
        guard Defaults[.dockReplacementEnabled] else { showSettings(); return }
        targetScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        reconcile()
    }

    func disable() { Defaults[.dockReplacementEnabled] = false }
    func showSettings() { SettingsWindowController.shared.showWindow(section: "Dock") }

    private var consoleUnlocked: Bool {
        LocalDesktopSessionPolicy.permitsDisplay(session: CGSessionCopyCurrentDictionary() as? [String: Any],
                                                 currentUID: getuid(), effectiveUID: geteuid())
    }
    private var permitsContent: Bool {
        started && Defaults[.dockReplacementEnabled] && !NSApp.isHidden && !locked && awake && activeSession && consoleUnlocked &&
        WorkspaceModeManager.shared.active?.hidesPrivateContent != true && !isLayoutReadOnly
    }
    var canAddApp: Bool { permitsContent && !pinsReadOnly && pins.count < 24 }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping @MainActor (DockReplacementController) -> Void) {
        center.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }; action(self)
        }.store(in: &subscriptions)
    }

    private func refreshUnlock() {
        unlockTask?.cancel()
        let attemptGeneration = generation
        unlockTask = Task { @MainActor [weak self] in
            for attempt in 0..<4 {
                guard let self, !Task.isCancelled, started, generation == attemptGeneration else { return }
                if consoleUnlocked { locked = false; reconcile(); return }
                if attempt < 3 { do { try await Task.sleep(for: .milliseconds(300)) } catch { return } }
            }
        }
    }

    private func reconcile() {
        guard permitsContent else { suspend(); return }
        if Defaults[.dockReplacementLayoutData] == nil { save(layout) }
        if targetScreen == nil { targetScreen = NSScreen.main ?? NSScreen.screens.first }
        if bar == nil {
            let panel = makePanel(title: "Notchscape Dock Bar")
            panel.onEscape = { [weak self] in self?.collapse() }; bar = panel
        }
        isVisible = true
        reloadApps(); positionBar()
        guard isVisible, permitsContent, barLayout != nil, bar?.contentView != nil else { return }
        bar?.orderFrontRegardless()
        DockFocusDiagnostics.shared.record("barPresented", state: bar?.isVisible == true)
        reconcileNativeDockVisibility()
        installClickMonitors()
        refreshTime()
    }

    /// Drops transient private snapshots and acquisition synchronously. A saved
    /// enabled bar returns only after the native session becomes eligible.
    private func suspend() {
        DockFocusDiagnostics.shared.record("barSuspended")
        generation &+= 1; isVisible = false
        reconcileNativeDockVisibility()
        reconcileSystemSampling()
        unlockTask?.cancel(); unlockTask = nil
        tick?.cancel(); tick = nil; calendarTask?.cancel(); calendarTask = nil
        picker?.cancel(nil); picker = nil
        collapse(); bar?.orderOut(nil); bar?.contentView = nil
        upcoming = []; lastCalendarRefresh = nil; calculators.removeAll()
        lastWeatherCheck = nil
        apps = []; appURLs.removeAll()
        if let localClick { NSEvent.removeMonitor(localClick) }; localClick = nil
        if let globalClick { NSEvent.removeMonitor(globalClick) }; globalClick = nil
    }

    private func makePanel(title: String) -> DockReplacementPanel {
        let panel = DockReplacementPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = title; panel.isReleasedWhenClosed = false; panel.isOpaque = false
        panel.backgroundColor = .clear; panel.hasShadow = true; panel.level = .floating
        panel.hidesOnDeactivate = false; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func positionBar() {
        guard isVisible, permitsContent, let screen = targetScreen ?? NSScreen.main,
              let geometry = DockReplacementPolicy.barLayout(in: screen.visibleFrame, appCount: apps.count,
                widgetKinds: layout.widgets.map(\.kind), iconSize: Defaults[.dockReplacementIconSize], requestedPage: page,
                overflow: Defaults[.dockReplacementOverflow] == "stack" ? .stack : .pages) else {
            if isVisible { errorMessage = "This display does not have enough room for the Dock bar."; suspend() }
            return
        }
        page = geometry.page
        if barLayout != geometry { barLayout = geometry }
        if bar?.frame != geometry.frame { bar?.setFrame(geometry.frame, display: true) }
        if let hosting = bar?.contentView as? NSHostingView<DockReplacementView> {
            // Only rehost on an actual layout operation, never on each clock,
            // battery or media update. The view observes snapshots directly.
            hosting.rootView = DockReplacementView(controller: self, layout: geometry)
        } else {
            // NSPanel starts with an ordinary, non-nil content view. Replace
            // that placeholder as well as the nil view left by suspension.
            bar?.contentView = NSHostingView(rootView: DockReplacementView(controller: self, layout: geometry))
        }
        if let expandedWidgetID { positionCard(expandedWidgetID) }
        reconcileSystemSampling()
        refreshWeatherIfNeeded()
        refreshCalendarIfNeeded()
    }

    func setPage(_ value: Int) { page = max(0, value); collapse(); positionBar() }
    func expand(_ id: UUID) {
        guard permitsContent, isVisible, layout.widgets.contains(where: { $0.id == id }) else { return }
        expandedWidgetID = id; positionCard(id)
    }
    private func positionCard(_ id: UUID) {
        guard let geometry = barLayout, let screen = targetScreen,
              let index = layout.widgets.firstIndex(where: { $0.id == id }),
              let anchor = geometry.widgetSlots.first(where: { $0.index == index })?.frame ?? geometry.overflowButtonFrame,
              let frame = DockReplacementPolicy.expandedCardFrame(for: anchor, in: geometry,
                usableFrame: screen.visibleFrame, preferredSize: .init(width: 320, height: 280)) else { collapse(); return }
        if card == nil { card = makePanel(title: "Notchscape Dock Controls"); card?.onEscape = { [weak self] in self?.collapse() } }
        card?.setFrame(frame, display: true)
        card?.contentView = NSHostingView(rootView: DockReplacementExpandedCard(controller: self, instance: layout.widgets[index]))
        card?.makeKeyAndOrderFront(nil)
        reconcileSystemSampling()
        refreshWeatherIfNeeded()
        refreshCalendarIfNeeded()
    }
    func collapse() {
        expandedWidgetID = nil; card?.orderOut(nil); card?.contentView = nil
        reconcileSystemSampling()
    }

    private func reconcileSystemSampling() {
        let needed = DockReplacementPolicy.needsSystemSampling(widgets: layout.widgets,
            visibleRange: barLayout?.visibleWidgetRange ?? 0..<0,
            expandedID: expandedWidgetID, active: isVisible && permitsContent)
        guard needed != systemLease else { return }
        systemLease = needed
        if needed { SystemPerformanceManager.shared.startSampling() }
        else { SystemPerformanceManager.shared.stopSampling() }
    }

    private func reconcileNativeDockVisibility() {
        DockVisibilityController.shared.update(barVisible: isVisible && permitsContent && bar?.isVisible == true,
                                               requested: Defaults[.dockHideSystemDock])
    }

    func openWeatherSettings() {
        collapse(); SettingsWindowController.shared.showWindow(section: "Weather")
    }

    private func refreshWeatherIfNeeded() {
        guard isVisible, permitsContent, Defaults[.weatherEnabled],
              layout.widgets.enumerated().contains(where: { index, widget in
                  widget.kind == .weather && (barLayout?.visibleWidgetRange.contains(index) == true || widget.id == expandedWidgetID)
              }) else { return }
        if let lastWeatherCheck, lastWeatherCheck.duration(to: clock.now) < .seconds(60) { return }
        lastWeatherCheck = clock.now
        // Reuse the provider's 15-minute cache, in-flight coalescing and permission
        // gate; the Dock adds no location request prompt or polling timer.
        WeatherManager.shared.refresh()
    }

    func openActivityMonitor() {
        collapse(); SystemPerformanceManager.shared.openActivityMonitor()
    }

    private func installClickMonitors() {
        guard localClick == nil, globalClick == nil else { return }
        localClick = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor [weak self] in self?.collapseIfOutside() }; return event
        }
        globalClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.collapseIfOutside() }
        }
    }
    private func collapseIfOutside() {
        guard expandedWidgetID != nil else { return }
        let point = NSEvent.mouseLocation
        if bar?.frame.contains(point) != true && card?.frame.contains(point) != true { collapse() }
    }

    private func reload() {
        if let data = Defaults[.dockReplacementLayoutData] {
            if let value = DockReplacementLayout.decode(data) { layout = value; isLayoutReadOnly = false }
            else { isLayoutReadOnly = true; errorMessage = "The saved Dock bar layout is unavailable. Its data has been kept." }
        }
        reloadPins()
    }
    private func save(_ value: DockReplacementLayout) {
        guard !isLayoutReadOnly, value.isValid, let data = try? JSONEncoder().encode(value), data.count <= 65_536 else { return }
        layout = value; Defaults[.dockReplacementLayoutData] = data
    }
    func addWidget(_ kind: DockReplacementWidgetKind) {
        guard permitsContent, !isLayoutReadOnly, layout.widgets.count < 48 else { return }
        let instance = DockReplacementWidgetInstance(kind: kind)
        var next = layout; next.widgets.append(instance); save(next)
        if Defaults[.dockReplacementOverflow] != "stack" { page = Int.max }
        positionBar()
        expand(instance.id)
    }
    func removeWidget(_ id: UUID) {
        guard permitsContent, !isLayoutReadOnly else { return }
        if expandedWidgetID == id { collapse() }; timers[id] = nil; calculators[id] = nil
        var next = layout; next.widgets.removeAll { $0.id == id }; save(next); positionBar(); refreshTime()
    }
    func moveWidget(_ id: UUID, by direction: Int) {
        guard permitsContent, !isLayoutReadOnly, let index = layout.widgets.firstIndex(where: { $0.id == id }) else { return }
        let target = max(0, min(layout.widgets.count - 1, index + (direction < 0 ? -1 : 1)))
        guard target != index else { return }
        var next = layout; let value = next.widgets.remove(at: index); next.widgets.insert(value, at: target)
        collapse(); save(next); positionBar()
    }
    func reorderWidget(_ id: UUID, before target: UUID) {
        guard permitsContent, !isLayoutReadOnly,
              let next = DockReplacementPolicy.placing(id, at: target, in: layout) else { return }
        collapse(); save(next); positionBar()
    }
    func setClockTimeZone(_ id: UUID, identifier: String?) {
        guard permitsContent, !isLayoutReadOnly, let index = layout.widgets.firstIndex(where: { $0.id == id && $0.kind == .clock }),
              identifier.map({ $0.utf8.count <= 128 && TimeZone(identifier: $0) != nil }) ?? true else { return }
        var next = layout; next.widgets[index].timeZoneIdentifier = identifier; save(next); refreshTime()
    }
    func setTimerDuration(_ id: UUID, seconds: Double) {
        guard permitsContent, !isLayoutReadOnly, seconds.isFinite, (1...86_400).contains(seconds),
              let index = layout.widgets.firstIndex(where: { $0.id == id && $0.kind == .timer }) else { return }
        var next = layout; next.widgets[index].timerDuration = seconds
        timers[id] = .init(remaining: seconds, started: nil); save(next); refreshTime()
    }
    private func remaining(_ state: TimerState) -> Double {
        guard let started = state.started else { return max(0, state.remaining) }
        let elapsed = started.duration(to: clock.now).components
        return max(0, state.remaining - Double(elapsed.seconds) - Double(elapsed.attoseconds) / 1e18)
    }
    func quickAction(_ id: UUID, origin: DockActionOrigin = .unspecified) {
        let instance = layout.widgets.first(where: { $0.id == id })
        let allowed = DockReplacementPolicy.permitsUserAction(contentAllowed: permitsContent,
            visible: isVisible, panelVisible: bar?.isVisible == true)
        DockFocusDiagnostics.shared.record("widgetAction", origin: origin, widget: instance?.kind, state: allowed)
        guard allowed, let instance else { return }
        switch instance.kind {
        case .nowPlaying: mediaAction("toggle")
        case .upNext:
            DockFocusDiagnostics.shared.record("calendarAction", origin: origin, widget: .upNext)
            if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
                SettingsWindowController.shared.showWindow(section: "Calendar")
            } else if let event = upcoming.first(where: { $0.end > Date() }), let url = event.calendarAppURL() {
                NSWorkspace.shared.open(url)
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                NSWorkspace.shared.open(url)
            }
        case .timer:
            var state = timers[id] ?? .init(remaining: instance.timerDuration, started: nil)
            if state.started != nil { state.remaining = remaining(state); state.started = nil }
            else { if state.remaining <= 0 { state.remaining = instance.timerDuration }; state.started = clock.now }
            timers[id] = state; refreshTime()
        default: expand(id)
        }
    }
    func mediaAction(_ action: String) {
        guard permitsContent else { return }
        switch action {
        case "previous": MusicManager.shared.previousTrack()
        case "toggle": MusicManager.shared.playPause()
        case "next": MusicManager.shared.nextTrack()
        default: break
        }
    }
    func calculatorInput(_ id: UUID, key: String) {
        guard permitsContent, layout.widgets.contains(where: { $0.id == id && $0.kind == .calculator }) else { return }
        var expression = calculators[id] ?? ""
        if key == "clear" { expression = "" }
        else if key == "backspace" { if !expression.isEmpty { expression.removeLast() } }
        else if key == "=" { expression = LocalCalculator.result(expression) ?? "Error" }
        else if key.count == 1, "0123456789.+-*/()".contains(key), expression.count < 160 {
            if expression == "Error" { expression = "" }; expression += key
        } else { return }
        calculators[id] = expression; objectWillChange.send()
    }

    func snapshot(for instance: DockReplacementWidgetInstance) -> DockReplacementFaceSnapshot {
        guard permitsContent, isVisible else { return .init(primary: "Paused", secondary: instance.kind.title, symbol: "lock.fill") }
        switch instance.kind {
        case .nowPlaying:
            let music = MusicManager.shared
            return .init(primary: music.isPlayerIdle ? "Not Playing" : music.songTitle,
                secondary: music.isPlayerIdle ? "Now Playing" : music.artistName,
                symbol: music.isPlaying ? "pause.fill" : "play.fill",
                progress: !music.isPlayerIdle && music.songDuration > 0 ? min(1, max(0, music.elapsedTime / music.songDuration)) : nil,
                artwork: music.isPlayerIdle ? nil : music.albumArt, isActive: music.isPlaying)
        case .upNext:
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
                return .init(primary: "Connect Calendar", secondary: "In Calendar settings", symbol: "calendar.badge.plus")
            }
            if let event = upcoming.first(where: { $0.end > currentDate }) {
                let when = event.isAllDay
                    ? event.start.formatted(date: .abbreviated, time: .omitted) + " · All Day"
                    : event.start.formatted(date: .abbreviated, time: .shortened)
                return .init(primary: event.title, secondary: when, symbol: "calendar")
            }
            return .init(primary: "No Upcoming Events", secondary: "Next seven days", symbol: "calendar")
        case .battery:
            let battery = BatteryStatusViewModel.shared
            return .init(primary: battery.dataAvailable ? "\(Int(battery.levelBattery.rounded()))%" : "—",
                         secondary: battery.statusText, symbol: battery.isCharging ? "battery.100percent.bolt" : "battery.100percent",
                         progress: battery.dataAvailable ? min(1, max(0, Double(battery.levelBattery) / 100)) : nil,
                         isActive: battery.isCharging)
        case .timer:
            let state = timers[instance.id] ?? .init(remaining: instance.timerDuration, started: nil)
            let seconds = remaining(state)
            return .init(primary: String(format: "%02d:%02d", Int(ceil(seconds)) / 60, Int(ceil(seconds)) % 60),
                secondary: seconds <= 0 ? "Finished" : state.started == nil ? "Timer" : "Running", symbol: "timer",
                progress: min(1, max(0, 1 - seconds / instance.timerDuration)), isActive: state.started != nil && seconds > 0)
        case .clock:
            let formatter = DateFormatter(); formatter.timeStyle = .short
            formatter.timeZone = instance.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
            let day = DateFormatter(); day.setLocalizedDateFormatFromTemplate("EEE MMM d"); day.timeZone = formatter.timeZone
            return .init(primary: formatter.string(from: currentDate),
                secondary: instance.timeZoneIdentifier == nil ? day.string(from: currentDate) : formatter.timeZone.abbreviation(for: currentDate) ?? day.string(from: currentDate), symbol: "clock")
        case .calculator:
            return .init(primary: calculators[instance.id].flatMap { $0.isEmpty ? nil : $0 } ?? "0", secondary: "Calculator", symbol: "plus.forwardslash.minus")
        case .weather:
            guard Defaults[.weatherEnabled] else {
                return .init(primary: "Set Up", secondary: "Weather is off", symbol: "cloud.sun.fill",
                             details: ["Choose a city or use your location in Weather settings."])
            }
            let provider = WeatherManager.shared
            guard let weather = provider.weather else {
                let needsLocationChoice: Bool
                switch provider.locationAuthorizationStatus {
                case .notDetermined, .denied, .restricted: needsLocationChoice = true
                default: needsLocationChoice = false
                }
                let needsSetup = Defaults[.weatherUseCurrentLocation] ? needsLocationChoice
                    : Defaults[.weatherLocation].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return .init(primary: needsSetup ? "Set Up" : provider.isLoading ? "Updating…" : "Unavailable", secondary: "Weather",
                             symbol: "cloud.fill", details: [provider.errorMessage ?? "Configure Weather to see current conditions."])
            }
            let appearance = WeatherTilePresentation(code: weather.weatherCode, isDay: weather.isDay,
                lowImpact: true, reduceTransparency: true, increasedContrast: false, reduceMotion: true)
            let current = DockReplacementPolicy.weatherIsCurrent(updatedAt: weather.updatedAt, now: currentDate,
                                                                 failed: provider.errorMessage != nil)
            return .init(primary: WeatherTilePresentation.temperature(weather.temperature),
                secondary: (current ? "" : "Last known · ") + WeatherTilePresentation.locationLabel(weather.location), symbol: appearance.conditionSymbol,
                isActive: current, details: [weather.condition,
                    "H: \(WeatherTilePresentation.temperature(weather.high))  L: \(WeatherTilePresentation.temperature(weather.low))",
                    (current ? "Updated " : "Last updated ") + weather.updatedAt.formatted(date: .omitted, time: .shortened)]
                    + (provider.errorMessage.map { [$0] } ?? []))
        case .system:
            let system = SystemPerformanceManager.shared
            let metrics = [DockReplacementMetric(title: "CPU", fraction: system.cpuDataAvailable ? DockReplacementPolicy.usageFraction(system.cpuUsage) : nil),
                           DockReplacementMetric(title: "Memory", fraction: system.memoryDataAvailable ? DockReplacementPolicy.usageFraction(system.memoryUsage) : nil),
                           DockReplacementMetric(title: "Storage", fraction: system.diskDataAvailable ? DockReplacementPolicy.usageFraction(system.diskUsage) : nil)]
            return .init(primary: metrics[0].value, secondary: "CPU · Memory \(metrics[1].value)",
                         symbol: "chart.bar.xaxis", metrics: metrics)
        }
    }

    private func refreshTime() {
        tick?.cancel(); tick = nil
        guard isVisible, permitsContent else { return }
        currentDate = Date()
        for (id, state) in timers where state.started != nil && remaining(state) <= 0 {
            timers[id] = .init(remaining: 0, started: nil)
        }
        refreshCalendarIfNeeded()
        let hasRunningTimer = timers.values.contains { $0.started != nil }
        refreshWeatherIfNeeded()
        let delay = hasRunningTimer ? 1 : max(1, 60 - currentDate.timeIntervalSince1970.truncatingRemainder(dividingBy: 60))
        tick = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }; self?.refreshTime()
        }
    }
    private func refreshCalendarIfNeeded() {
        guard permitsContent, isVisible, calendarTask == nil, let barLayout,
              layout.widgets.enumerated().contains(where: { index, widget in
                  widget.kind == .upNext && (barLayout.visibleWidgetRange.contains(index) || expandedWidgetID == widget.id)
              }), EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              lastCalendarRefresh.map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { return }
        let attempt = generation
        calendarTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let values = await CalendarManager.shared.upcomingEventsForDock(now: Date())
            guard !Task.isCancelled, attempt == generation, permitsContent, isVisible else { return }
            upcoming = values.filter { $0.end > Date() }.sorted {
                if $0.isAllDay != $1.isAllDay { return !$0.isAllDay }
                return $0.start < $1.start
            }
            lastCalendarRefresh = Date(); calendarTask = nil; objectWillChange.send()
        }
    }

    private func reloadPins() {
        guard let data = Defaults[.dockReplacementPinsData] else { pins = []; pinsReadOnly = false; return }
        guard data.count <= 2_000_000, let values = try? JSONDecoder().decode([DockWorkspacePin].self, from: data),
              values.count <= 24, values.allSatisfy(\.isValid), Set(values.map(\.id)).count == values.count else {
            pinsReadOnly = true; errorMessage = "Saved Dock apps are unavailable. Their data has been kept."; return
        }
        pins = values; pinsReadOnly = false
    }
    private func resolve(_ pin: DockWorkspacePin) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: pin.bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale),
              url.isFileURL, let values = try? url.resourceValues(forKeys: [.isApplicationKey, .isDirectoryKey]),
              values.isDirectory == true,
              (pin.kind == .folder ? values.isApplication != true : values.isApplication == true) else { return nil }
        return url
    }
    private func reloadApps() {
        guard isVisible, permitsContent else { return }
        var next: [DockReplacementApp] = []; var urls: [UUID: URL] = [:]; var seen = Set<URL>()
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != "com.graden-grech.Notchscape.DockWidget" }
        for pin in pins {
            guard let url = resolve(pin), seen.insert(url).inserted else { continue }
            next.append(.init(id: pin.id, title: pin.title, icon: NSWorkspace.shared.icon(forFile: url.path), isRunning: running.contains { $0.bundleURL == url }, isPinned: true))
            urls[pin.id] = url
        }
        for app in running where next.count < 24 {
            guard let url = app.bundleURL, seen.insert(url).inserted else { continue }
            let id = appIDs[url] ?? UUID(); appIDs[url] = id
            next.append(.init(id: id, title: app.localizedName ?? url.deletingPathExtension().lastPathComponent,
                icon: app.icon ?? NSWorkspace.shared.icon(forFile: url.path), isRunning: true)); urls[id] = url
        }
        appIDs = appIDs.filter { seen.contains($0.key) }
        apps = next; appURLs = urls
    }
    func openApp(_ id: UUID, origin: DockActionOrigin = .unspecified) {
        let allowed = DockReplacementPolicy.permitsUserAction(contentAllowed: permitsContent,
            visible: isVisible, panelVisible: bar?.isVisible == true)
        DockFocusDiagnostics.shared.record("appAction", origin: origin, state: allowed,
                                          target: appURLs[id].flatMap { Bundle(url: $0)?.bundleIdentifier })
        guard allowed, let url = appURLs[id] else { return }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle(url: url)?.bundleIdentifier ?? "").first {
            app.activate(options: [])
        } else { NSWorkspace.shared.open(url) }
    }
    func keepApp(_ id: UUID) {
        guard permitsContent, !pinsReadOnly, pins.count < 24, let url = appURLs[id],
              !pins.contains(where: { resolve($0) == url }) else { return }
        do {
            let resource = try url.resourceValues(forKeys: [.isDirectoryKey, .isApplicationKey])
            guard resource.isDirectory == true else { return }
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            let pin = DockWorkspacePin(id: UUID(), title: DockWorkspacePolicy.title(url.deletingPathExtension().lastPathComponent),
                kind: resource.isApplication == true ? .application : .folder, bookmark: bookmark)
            guard pin.isValid else { return }; savePins(pins + [pin])
        } catch { errorMessage = "This app could not be kept in Dock. Try adding it again." }
    }
    func removeApp(_ id: UUID) {
        guard permitsContent, !pinsReadOnly, pins.contains(where: { $0.id == id }) else { return }
        savePins(pins.filter { $0.id != id })
    }
    func moveApp(_ id: UUID, by direction: Int) {
        guard permitsContent, !pinsReadOnly, let source = pins.firstIndex(where: { $0.id == id }) else { return }
        let target = source + (direction < 0 ? -1 : 1)
        guard pins.indices.contains(target) else { return }
        var next = pins; next.swapAt(source, target); savePins(next)
    }
    private func savePins(_ values: [DockWorkspacePin]) {
        guard !pinsReadOnly, values.count <= 24, values.allSatisfy(\.isValid),
              Set(values.map(\.id)).count == values.count,
              let data = try? JSONEncoder().encode(values), data.count <= 2_000_000 else { return }
        Defaults[.dockReplacementPinsData] = data
    }
    func addApp() {
        guard permitsContent, !pinsReadOnly, picker == nil, pins.count < 24 else { return }
        let panel = NSOpenPanel(); picker = panel
        panel.title = "Add an App or Folder to Dock Bar"; panel.prompt = "Add"
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        let attempt = generation
        panel.begin { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, picker === panel else { return }; picker = nil
                guard response == .OK, attempt == generation, permitsContent, let url = panel.url else { return }
                do {
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isApplicationKey])
                    guard values.isDirectory == true else { errorMessage = "Choose an installed app or a folder."; return }
                    let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                    let pin = DockWorkspacePin(id: UUID(), title: DockWorkspacePolicy.title(url.deletingPathExtension().lastPathComponent),
                        kind: values.isApplication == true ? .application : .folder, bookmark: bookmark)
                    guard pin.isValid, pins.count < 24 else { return }
                    var next = pins; next.append(pin)
                    savePins(next)
                } catch { errorMessage = "This item could not be added. Please choose it again." }
            }
        }
    }
}

@MainActor private final class DockReplacementPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
/// Short event-driven trace of a real enable transition. Fixed app classes and
/// numeric process/event IDs only: never titles, document URLs, calendar data,
/// key characters, images or preference contents. No polling or trace timer.
@MainActor final class DockFocusDiagnostics {
    static let shared = DockFocusDiagnostics()
    private let logger = Logger(subsystem: "com.graden-grech.Notchscape", category: "DockFocus")
    private var startedAt: TimeInterval?
    private var traceID = UUID()
    private var wasEnabled = false

    func barPreferenceChanged(_ enabled: Bool) {
        if enabled && !wasEnabled {
            startedAt = ProcessInfo.processInfo.systemUptime
            traceID = UUID()
        }
        wasEnabled = enabled
        record("barPreference", state: enabled)
    }

    func record(_ phase: String, origin: DockActionOrigin = .unspecified,
                widget: DockReplacementWidgetKind? = nil, state: Bool? = nil,
                target: String? = nil, targetPID: pid_t? = nil) {
        let now = ProcessInfo.processInfo.systemUptime
        guard DockReplacementPolicy.shouldTraceFocus(startedAt: startedAt, now: now) else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let event = NSApp.currentEvent
        let line = "trace=\(traceID.uuidString) elapsed=\(now - (startedAt ?? now)) phase=\(phase) origin=\(origin.rawValue)" +
            " widget=\(widget?.rawValue ?? "none") state=\(state.map(String.init) ?? "none")" +
            " front=\(Self.appClass(front?.bundleIdentifier)) frontPID=\(front?.processIdentifier ?? 0)" +
            " target=\(Self.appClass(target)) targetPID=\(targetPID ?? 0)" +
            " eventType=\(event.map { String($0.type.rawValue) } ?? "none") eventWindow=\(event?.windowNumber ?? 0)"
        logger.notice("\(line, privacy: .public)")
    }

    private static func appClass(_ bundleID: String?) -> String {
        switch bundleID {
        case "com.apple.iCal", "com.apple.calendar": "calendar"
        case "com.apple.dock": "systemDock"
        case "theboringteam.boringnotch": "notchscape"
        case "com.graden-grech.Notchscape.DockWidget": "dockCompanion"
        case nil: "none"
        default: "other"
        }
    }
}

