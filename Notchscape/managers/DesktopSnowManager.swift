import AppKit
import Combine
import CoreGraphics
import Defaults
import QuartzCore
import SwiftUI

/// Desktop weather is independent of the notch's seasonal appearance.
enum DesktopSnowSeason: String, CaseIterable, Identifiable {
    case winterDawn, holidayNight, mapleAir, blossomLight, rainGarden, woodlandBreeze
    var id: Self { self }

    var title: String {
        switch self {
        case .winterDawn: "Winter Dawn"
        case .holidayNight: "Holiday Night"
        case .mapleAir: "Maple Air"
        case .blossomLight: "Blossom Light"
        case .rainGarden: "Rain Garden"
        case .woodlandBreeze: "Woodland Breeze"
        }
    }

    var isSnow: Bool { self == .winterDawn || self == .holidayNight }
    var canSettle: Bool { self != .rainGarden }
    var speedMultiplier: Double {
        switch self {
        case .rainGarden: 2.5
        case .holidayNight: 0.72
        default: 1
        }
    }

    var wallpapers: [Wallpaper] {
        let suffixes: [String] = switch self {
        case .winterDawn: ["winter-arctic-sunrise", "winter-teton-blue"]
        case .holidayNight: ["winter-cabin-lights", "winter-christmas-snow"]
        case .mapleAir: ["fall-golden-forest", "fall-autumn-lane", "fall-pumpkin-harvest"]
        case .blossomLight: ["spring-cherry-overlook", "spring-mountain-meadow", "spring-lake-valley"]
        case .rainGarden: ["spring-misty-forest", "spring-lake-valley", "summer-coastal-mountains"]
        case .woodlandBreeze: ["summer-green-valley", "summer-blue-lake", "summer-coastal-mountains"]
        }
        return suffixes.compactMap { suffix in SeasonalInternetCatalog.all.first { $0.id == "internet-\(suffix)" } }
    }

    var previewColors: [Color] {
        let colors: [UInt32] = switch self {
        case .winterDawn: [0x849fc5, 0xc6d7ed, 0xefc6b9]
        case .holidayNight: [0x161925, 0x282637, 0x58402e]
        case .mapleAir: [0x3c301f, 0x79523c, 0x9b6840]
        case .blossomLight: [0x7f5377, 0xac829e, 0xd0a1a5]
        case .rainGarden: [0x25374e, 0x536981, 0x7e9ba4]
        case .woodlandBreeze: [0x334e3d, 0x647b51, 0x99a36c]
        }
        return colors.map { value in
            Color(red: Double(value >> 16) / 255, green: Double(value >> 8 & 255) / 255, blue: Double(value & 255) / 255)
        }
    }

    var bankTint: NSColor {
        switch self {
        case .mapleAir: .init(srgbRed: 0.71, green: 0.30, blue: 0.12, alpha: 1)
        case .holidayNight: .init(srgbRed: 1, green: 0.93, blue: 0.82, alpha: 1)
        default: tint()
        }
    }

    func tint(variant: Int = 0) -> NSColor {
        let colors: [NSColor] = switch self {
        case .winterDawn: [.init(srgbRed: 0.91, green: 0.97, blue: 1, alpha: 1), .white]
        case .holidayNight: [.init(srgbRed: 1, green: 0.78, blue: 0.46, alpha: 1),
                             .init(srgbRed: 1, green: 0.93, blue: 0.82, alpha: 1), .white, .white, .white, .white]
        case .mapleAir: [.init(srgbRed: 0.99, green: 0.67, blue: 0.27, alpha: 1), .systemOrange, .systemRed]
        case .blossomLight: [.init(srgbRed: 1, green: 0.78, blue: 0.86, alpha: 1), .systemPink]
        case .rainGarden: [.init(srgbRed: 0.59, green: 0.76, blue: 0.92, alpha: 1)]
        case .woodlandBreeze: [.init(srgbRed: 0.71, green: 0.84, blue: 0.44, alpha: 1), .systemGreen]
        }
        return colors[variant % colors.count]
    }

    func particlePath(in rect: CGRect, variant: Int = 0) -> CGPath {
        if self == .holidayNight && variant.isMultiple(of: 6) {
            let path = CGMutablePath()
            for index in 0..<8 {
                let angle = Double(index) * .pi / 4
                let scale = index.isMultiple(of: 2) ? 0.67 : 0.19
                let point = CGPoint(x: rect.midX + cos(angle) * rect.width * scale,
                                    y: rect.midY + sin(angle) * rect.height * scale)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            return path
        }
        if isSnow { return CGPath(ellipseIn: rect, transform: nil) }
        if self == .rainGarden { return CGPath(roundedRect: rect, cornerWidth: rect.width / 2, cornerHeight: rect.width / 2, transform: nil) }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension Defaults.Keys {
    static let desktopSnowSeason = Key<String>("desktopSnowSeason", default: DesktopSnowSeason.winterDawn.rawValue)
    static let desktopSnowWallpaperSelections = Key<[String: String]>("desktopSnowWallpaperSelections", default: [:])
    static let desktopSnowMatchWallpaper = Key<Bool>("desktopSnowMatchWallpaper", default: false)
    static let desktopSnowPileLayouts = Key<[String: DesktopSnowPileLayout]>("desktopSnowPileLayouts", default: [:])
    static let desktopSnowPointerSweep = Key<Bool>("desktopSnowPointerSweep", default: false)
    static let desktopSnowEnabled = Key<Bool>("desktopSnowEnabled", default: false)
    static let desktopSnowIntensity = Key<Double>("desktopSnowIntensity", default: 0.5)
    static let desktopSnowSpeed = Key<Double>("desktopSnowSpeed", default: 1)
    static let desktopSnowWind = Key<Double>("desktopSnowWind", default: 0)
    static let desktopSnowAccumulation = Key<Bool>("desktopSnowAccumulation", default: true)
    static let desktopSnowWindowEdges = Key<Bool>("desktopSnowWindowEdges", default: false)
    static let desktopSnowMoundHeight = Key<Double>("desktopSnowMoundHeight", default: 1)
    static let desktopSnowMoundWidth = Key<Double>("desktopSnowMoundWidth", default: 1)
    static let desktopSnowMoundSpacing = Key<Double>("desktopSnowMoundSpacing", default: 1)
    static let desktopSnowAllDisplays = Key<Bool>("desktopSnowAllDisplays", default: true)
}

struct DesktopSnowPileLayout: Codable, Defaults.Serializable, Equatable {
    var limit: Double = 18
    var baseDepth: Double = 0
    var placed = false
    var mounds: [DesktopSnowAuthoredMound] = []

    func apply(to options: inout DesktopSnowOptions) {
        options.bottomLimit = limit
        options.baseDepth = baseDepth
        options.customBottomLayout = placed
        options.authoredMounds = mounds
    }
}

extension DesktopSnowMound {
    static func filledPath(for mounds: [Self]) -> CGPath {
        let path = CGMutablePath()
        for mound in mounds {
            guard let first = mound.points.first, let last = mound.points.last else { continue }
            path.move(to: first)
            for index in 1..<mound.points.count {
                let previous = mound.points[index - 1], point = mound.points[index]
                let middle = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
                path.addQuadCurve(to: middle, control: previous)
            }
            path.addQuadCurve(to: last, control: last)
            path.addLine(to: CGPoint(x: last.x, y: 0))
            path.addLine(to: CGPoint(x: first.x, y: 0))
            path.closeSubpath()
        }
        return path
    }
}

/// Optional app-owned decoration. It neither captures pixels nor manipulates
/// other apps. Window geometry is an explicit, separate opt-in; no Screen
/// Recording, Accessibility, camera, or credential API is requested here.
@MainActor
final class DesktopSnowManager: NSObject, ObservableObject {
    static let shared = DesktopSnowManager()
    @Published private(set) var isEditing = false
    @Published var editTool: DesktopSnowBrushTool = .build {
        didSet { editStroke = nil; editSession.interact(now: ProcessInfo.processInfo.systemUptime) }
    }
    @Published var editBrushRadius: Double = 30 {
        didSet { editSession.interact(now: ProcessInfo.processInfo.systemUptime) }
    }
    private var editSession = DesktopSnowEditingSession()
    private var editorPanel: DesktopSnowEditorPanel?
    private struct EditStroke {
        let displayID: UInt32
        let surfaceID: UInt64
        var previous: CGPoint
        var pending: CGPoint?
    }
    private var editStroke: EditStroke?
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "Off"
    @Published private(set) var windowEdgesAvailable = false

    private final class DisplayState {
        let frame: CGRect
        let usableFrame: CGRect
        let topSafeInset: Double
        let panel: DesktopSnowPanel
        let view: DesktopSnowView
        var simulation: DesktopSnowSimulation
        init(frame: CGRect, usableFrame: CGRect, topSafeInset: Double, panel: DesktopSnowPanel,
             view: DesktopSnowView, simulation: DesktopSnowSimulation) {
            self.frame = frame; self.usableFrame = usableFrame; self.topSafeInset = topSafeInset
            self.panel = panel; self.view = view; self.simulation = simulation
        }
    }
    private var displays: [CGDirectDisplayID: DisplayState] = [:]
    private var observations = Set<AnyCancellable>()
    private var frameTimer: Timer?
    private var unlockTask: Task<Void, Never>?
    private var frameRate: Int?
    private var lastFrameTime: TimeInterval?
    private var lastGeometryTime: TimeInterval?
    private var lastSessionCheck: TimeInterval?
    private var windowGeometry: [DesktopSnowWindowGeometry] = []
    private var started = false
    private var locked = true
    private var awake = true
    private var activeSession = true
    private var captureSuppressed = false
    private var generation: UInt64 = 0
    private var displayedSeason: DesktopSnowSeason?
    private var pileLayouts: [String: DesktopSnowPileLayout] = [:]

    private override init() { super.init() }

    func start() {
        guard !started else { return }
        started = true
        locked = !consoleUnlocked
        awake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
        observePreference(.desktopSnowEnabled)
        observePreference(.desktopSnowSeason)
        observePreference(.desktopSnowPointerSweep)
        observe(NotificationCenter.default, UserDefaults.didChangeNotification) { $0.refreshScenery() }
        observePreference(.desktopSnowIntensity)
        observePreference(.desktopSnowSpeed)
        observePreference(.desktopSnowWind)
        observePreference(.desktopSnowAccumulation)
        observePreference(.desktopSnowMoundHeight)
        observePreference(.desktopSnowMoundWidth)
        observePreference(.desktopSnowMoundSpacing)
        observePreference(.desktopSnowPileLayouts)
        observePreference(.desktopSnowWindowEdges)
        observePreference(.desktopSnowAllDisplays)
        observePreference(.showOnExternalDisplays)
        WorkspaceModeManager.shared.$session.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reconcile() }.store(in: &observations)
        AppPerformanceManager.shared.objectWillChange.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reconcile() }.store(in: &observations)
        BatteryStatusViewModel.shared.objectWillChange.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reconcile() }.store(in: &observations)
        DockReplacementController.shared.$barLayout.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshSurfaces() }.store(in: &observations)
        DockReplacementController.shared.$isVisible.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshSurfaces() }.store(in: &observations)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main).sink { [weak self] event in
                guard let self, self.isEditing else { return }
                let app = event.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                self.endEditing()
            }.store(in: &observations)
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.awake = false; $0.suspend() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.awake = false; $0.suspend() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.awake = CGDisplayIsAsleep(CGMainDisplayID()) == 0; $0.reconcile() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.awake = true; $0.reconcile() }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.activeSession = false; $0.suspend() }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.activeSession = true; $0.refreshUnlock() }
        observe(NotificationCenter.default, NSApplication.willTerminateNotification) { $0.stop() }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) {
            $0.suspend(); $0.awake = CGDisplayIsAsleep(CGMainDisplayID()) == 0; $0.reconcile()
        }
        observe(NotificationCenter.default, .NSProcessInfoPowerStateDidChange) { $0.reconcile() }
        observe(NotificationCenter.default, ProcessInfo.thermalStateDidChangeNotification) { $0.reconcile() }
        observe(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { $0.reconcile() }
        DistributedNotificationCenter.default().publisher(for: .init("com.apple.screenIsLocked"))
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.locked = true; self?.suspend() }.store(in: &observations)
        DistributedNotificationCenter.default().publisher(for: .init("com.apple.screenIsUnlocked"))
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshUnlock() }.store(in: &observations)
        reconcile()
    }

    /// App shutdown only; the saved opt-in survives normal relaunch.
    func stop() {
        started = false
        suspend()
        observations.removeAll()
        updateStatus("Off")
    }

    /// Clears transient banks and shedding flakes, never any user preference.
    func clearSnow() {
        for state in displays.values {
            state.simulation.clearAccumulation()
            state.view.update(state.simulation, options: options, season: season, frameInterval: 1 / Double(frameRate ?? 30))
        }
    }

    /// Our own recording flow calls this synchronously before presenting its
    /// picker. Window sharingType is not a promise about other recorders.
    func setCaptureSuppressed(_ active: Bool) {
        guard captureSuppressed != active else { return }
        captureSuppressed = active
        if active { suspend(); updateStatus("Paused while Notchscape is recording.") }
        else { reconcile() }
    }

    private var eligibilityAllowsEditing: Bool {
        started && isRunning && !displays.isEmpty && options.accumulation && eligibility.framesPerSecond != nil
    }

    func beginEditing() {
        guard !isEditing, editSession.begin(eligible: eligibilityAllowsEditing,
            now: ProcessInfo.processInfo.systemUptime) else { return }
        isEditing = true
        for state in displays.values {
            state.panel.isEditingCanvas = true
            state.panel.ignoresMouseEvents = false
            // Above the Dock while editing, below the system menu bar.
            state.panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
            state.panel.acceptsMouseMovedEvents = true
            state.view.setEditing(true, radius: editBrushRadius)
        }
        let palette = DesktopSnowEditorPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 190),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        palette.isReleasedWhenClosed = false; palette.isOpaque = false; palette.backgroundColor = .clear
        palette.hasShadow = true; palette.hidesOnDeactivate = false
        palette.level = .statusBar; palette.sharingType = .none
        palette.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        palette.title = "Edit Snow Piles"
        palette.onFinish = { [weak self] in self?.endEditing() }
        palette.contentView = NSHostingView(rootView: DesktopSnowEditorToolbar(snow: self))
        if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            palette.setFrameOrigin(NSPoint(x: frame.midX - 210, y: frame.maxY - 224))
        }
        editorPanel = palette
        palette.makeKeyAndOrderFront(nil)
    }

    func endEditing() {
        editSession.end(); editStroke = nil
        if isEditing { isEditing = false }
        // Restore click-through before dismissing the always-available Done control.
        for state in displays.values {
            state.panel.ignoresMouseEvents = true
            state.panel.isEditingCanvas = false
            state.panel.level = .floating
            state.panel.acceptsMouseMovedEvents = false
            state.view.setEditing(false, radius: editBrushRadius)
        }
        if let palette = editorPanel {
            editorPanel = nil; palette.onFinish = nil
            palette.orderOut(nil); palette.contentView = nil; palette.close()
        }
    }

    func focusEditingCanvas() {
        guard isEditing else { return }
        let point = NSEvent.mouseLocation
        let state = displays.values.first { $0.frame.contains(point) } ?? displays.values.first
        state?.panel.makeKeyAndOrderFront(nil)
    }

    func resetMoundStyle() {
        Defaults[.desktopSnowMoundHeight] = 1
        Defaults[.desktopSnowMoundWidth] = 1
        Defaults[.desktopSnowMoundSpacing] = 1
    }

    private func handleEdit(displayID: UInt32, point: CGPoint, phase: DesktopSnowEditPhase) {
        let now = ProcessInfo.processInfo.systemUptime
        guard isEditing, editSession.validate(eligible: eligibilityAllowsEditing, now: now),
              let state = displays[displayID], point.x.isFinite, point.y.isFinite else {
            endEditing(); return
        }
        editSession.interact(now: now)
        switch phase {
        case .began:
            guard let surface = state.simulation.editableSurface(at: point, radius: editBrushRadius, options: options) else {
                editStroke = nil; return
            }
            editStroke = EditStroke(displayID: displayID, surfaceID: surface, previous: point, pending: point)
            if editTool != .move { processEditStroke(); state.view.update(state.simulation, options: options, season: season, frameInterval: 1 / Double(frameRate ?? 30)) }
        case .dragged:
            guard editStroke?.displayID == displayID else { return }
            editStroke?.pending = point // Coalesce high-polling-rate mice into the existing frame loop.
        case .ended:
            guard editStroke?.displayID == displayID else { return }
            if editStroke?.previous != point { editStroke?.pending = point }
            processEditStroke(); editStroke = nil
            state.view.update(state.simulation, options: options, season: season, frameInterval: 1 / Double(frameRate ?? 30))
        }
    }

    private func processEditStroke() {
        guard isEditing, var stroke = editStroke, let endpoint = stroke.pending,
              let state = displays[stroke.displayID] else { return }
        var previous = stroke.previous
        for point in DesktopSnowEditingSession.samples(from: previous, to: endpoint, radius: editBrushRadius) {
            state.simulation.sculpt(surfaceID: stroke.surfaceID, at: point, tool: editTool,
                radius: editBrushRadius, strength: 0.45, from: previous, options: options)
            previous = point
        }
        stroke.previous = endpoint; stroke.pending = nil; editStroke = stroke
    }

    private func observePreference<Value>(_ key: Defaults.Key<Value>) where Value: Defaults.Serializable {
        Defaults.publisher(key).receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            if !Defaults[.desktopSnowWindowEdges] {
                windowGeometry = []; lastGeometryTime = nil
                if windowEdgesAvailable { windowEdgesAvailable = false }
            }
            reconcile()
            refreshSurfaces()
        }.store(in: &observations)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping @MainActor (DesktopSnowManager) -> Void) {
        center.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }; action(self)
        }.store(in: &observations)
    }

    private var consoleUnlocked: Bool {
        LocalDesktopSessionPolicy.permitsDisplay(session: CGSessionCopyCurrentDictionary() as? [String: Any],
                                                 currentUID: getuid(), effectiveUID: geteuid())
    }

    private var eligibility: DesktopSnowEligibility {
        let performance = AppPerformanceManager.shared
        let battery = BatteryStatusViewModel.shared
        let thermal = ProcessInfo.processInfo.thermalState
        let onBattery = battery.dataAvailable && !battery.isPluggedIn
        return .init(enabled: started && Defaults[.desktopSnowEnabled], unlocked: !locked && consoleUnlocked,
            awake: awake, activeSession: activeSession,
            presenting: WorkspaceModeManager.shared.active?.hidesPrivateContent == true,
            reduceMotion: performance.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            lowImpact: performance.lowImpact || ProcessInfo.processInfo.isLowPowerModeEnabled || thermal == .fair,
            onBattery: onBattery, criticalBattery: onBattery && battery.levelBattery <= 10,
            seriousThermal: thermal == .serious || thermal == .critical, capturing: captureSuppressed)
    }

    private var season: DesktopSnowSeason { DesktopSnowSeason(rawValue: Defaults[.desktopSnowSeason]) ?? .winterDawn }

    private var options: DesktopSnowOptions {
        var result = DesktopSnowOptions(intensity: Defaults[.desktopSnowIntensity], speed: Defaults[.desktopSnowSpeed] * season.speedMultiplier,
              wind: Defaults[.desktopSnowWind], accumulation: Defaults[.desktopSnowAccumulation] && season.canSettle,
              moundHeight: Defaults[.desktopSnowMoundHeight], moundWidth: Defaults[.desktopSnowMoundWidth],
              moundSpacing: Defaults[.desktopSnowMoundSpacing],
              pointerSweep: Defaults[.desktopSnowPointerSweep] && !isEditing)
        pileLayouts[season.rawValue]?.apply(to: &result)
        return result.bounded
    }

    private func refreshScenery() {
        let defaults = UserDefaults.standard
        let visible = defaults.bool(forKey: "desktopSnowSceneryEnabled") || defaults.bool(forKey: "desktopSnowSceneryPetEnabled")
        for state in displays.values {
            state.view.setScenery(theme: visible ? season.rawValue : nil, lowImpact: frameRate == 15)
        }
    }

    private func refreshUnlock() {
        unlockTask?.cancel()
        let attemptGeneration = generation
        unlockTask = Task { @MainActor [weak self] in
            for attempt in 0..<4 {
                guard let self, started, !Task.isCancelled, generation == attemptGeneration else { return }
                if consoleUnlocked { locked = false; reconcile(); return }
                if attempt < 3 { do { try await Task.sleep(for: .milliseconds(300)) } catch { return } }
            }
        }
    }

    private func reconcile() {
        pileLayouts = Defaults[.desktopSnowPileLayouts]
        if displayedSeason != season {
            displayedSeason = season
            if isEditing { endEditing() }
            clearSnow()
        }
        if isEditing && !eligibilityAllowsEditing { endEditing() }
        if captureSuppressed { suspend(); updateStatus("Paused while Notchscape is recording."); return }
        let eligibility = eligibility
        guard let fps = eligibility.framesPerSecond, options.intensity > 0 else {
            suspend()
            updateStatus(eligibility.framesPerSecond != nil ? "Paused · Intensity is zero." : eligibility.status)
            return
        }
        let available = NSScreen.screens.filter {
            guard let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return false }
            return (Defaults[.showOnExternalDisplays] || CGDisplayIsBuiltin(id) != 0) &&
                DesktopSnowPolicy.validSize($0.frame.size) && CGDisplayIsAsleep(id) == 0
        }
        // The first screen is the display with the primary menu bar, making
        // the single-display preference stable while another app is active.
        let selected = Array((Defaults[.desktopSnowAllDisplays] ? available : Array(available.prefix(1))).prefix(DesktopSnowPolicy.maximumDisplays))
        let desired = Set(selected.compactMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value })
        for id in displays.keys.filter({ !desired.contains($0) }) {
            if let state = displays.removeValue(forKey: id) {
                state.view.resetRenderer(); state.panel.contentView = nil; state.panel.close()
            }
        }
        for screen in selected {
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { continue }
            if let existing = displays[id], existing.frame == screen.frame, existing.usableFrame == screen.visibleFrame,
               existing.topSafeInset == screen.safeAreaInsets.top { continue }
            if let state = displays.removeValue(forKey: id) {
                state.view.resetRenderer(); state.panel.contentView = nil; state.panel.close()
            }
            guard var simulation = DesktopSnowSimulation(size: screen.frame.size, seed: UInt64(id) ^ 0x736e6f7766616c6c) else { continue }
            simulation.seedInitialSnow(options: options, lowImpact: fps == 15)
            let view = DesktopSnowView(frame: CGRect(origin: .zero, size: screen.frame.size), backingScale: screen.backingScaleFactor)
            let panel = DesktopSnowPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.ignoresMouseEvents = true; panel.hasShadow = false; panel.hidesOnDeactivate = false
            panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.sharingType = .none; panel.isExcludedFromWindowsMenu = true
            panel.title = "Notchscape Desktop Snow"; panel.contentView = view
            panel.onFinishEditing = { [weak self] in self?.endEditing() }
            view.onEditEvent = { [weak self] point, phase in self?.handleEdit(displayID: id, point: point, phase: phase) }
            displays[id] = DisplayState(frame: screen.frame, usableFrame: screen.visibleFrame,
                topSafeInset: screen.safeAreaInsets.top, panel: panel, view: view, simulation: simulation)
            view.update(simulation, options: options, season: season)
            panel.orderFrontRegardless()
        }
        guard !displays.isEmpty else { suspend(); updateStatus("Paused · No eligible display is available."); return }
        if !isRunning { isRunning = true; refreshSurfaces() }
        updateStatus(eligibility.status)
        if frameTimer == nil || frameRate != fps { startFrames(fps: fps) }
        refreshScenery()
    }

    /// Lock/sleep/Presentation removes the windows, physics, geometry and
    /// timer immediately. Passive system notification subscriptions remain.
    private func suspend() {
        endEditing()
        generation &+= 1
        unlockTask?.cancel(); unlockTask = nil
        frameTimer?.invalidate(); frameTimer = nil; frameRate = nil
        lastFrameTime = nil; lastGeometryTime = nil; lastSessionCheck = nil
        for state in displays.values {
            state.view.resetRenderer(); state.panel.orderOut(nil); state.panel.contentView = nil; state.panel.close()
        }
        displays = [:]; windowGeometry = []
        if isRunning { isRunning = false }
        if windowEdgesAvailable { windowEdgesAvailable = false }
        updateStatus(eligibility.status)
    }

    private func startFrames(fps: Int) {
        frameTimer?.invalidate()
        frameRate = fps; lastFrameTime = nil
        let timer = Timer(timeInterval: 1 / Double(fps), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceFrame() }
        }
        timer.tolerance = fps == 15 ? 0.012 : 0.005
        frameTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceFrame() {
        guard started, Defaults[.desktopSnowEnabled], isRunning else { suspend(); return }
        let now = ProcessInfo.processInfo.systemUptime
        // Event fences are primary; a sparse additional public-session check
        // prevents a missed notification leaving decoration in another session.
        if lastSessionCheck.map({ now - $0 >= 0.5 }) ?? true {
            lastSessionCheck = now
            guard eligibility.framesPerSecond != nil else { reconcile(); return }
        }
        let dt = lastFrameTime.map { now - $0 } ?? 1 / Double(frameRate ?? 30)
        lastFrameTime = now
        if DesktopSnowPolicy.shouldSampleGeometry(active: isRunning, windowEdges: Defaults[.desktopSnowWindowEdges],
            accumulation: options.accumulation, now: now, lastSample: lastGeometryTime) {
            lastGeometryTime = now
            readOptionalWindowGeometry()
            refreshSurfaces()
        }
        if isEditing && !editSession.validate(eligible: eligibilityAllowsEditing, now: now) { endEditing() }
        processEditStroke()
        let options = options
        let pointer = NSEvent.mouseLocation
        for state in displays.values {
            if isEditing { state.view.setEditing(true, radius: editBrushRadius) }
            let localPointer = CGPoint(x: pointer.x - state.frame.minX, y: pointer.y - state.frame.minY)
            state.simulation.step(seconds: dt, options: options, lowImpact: frameRate == 15,
                                  pointer: state.frame.insetBy(dx: -110, dy: -110).contains(pointer) ? localPointer : nil)
            state.view.update(state.simulation, options: options, season: season, frameInterval: 1 / Double(frameRate ?? 30))
        }
    }

    private func refreshSurfaces() {
        guard isRunning else { return }
        let ownDock = DockReplacementController.shared
        let ownDockFrame: CGRect? = ownDock.isVisible ? ownDock.barLayout.map {
            // The outer window reserves transparent magnification room. Use
            // its resting visible glass, never those invisible side ledges.
            CGRect(x: $0.frame.minX + $0.magnificationReserve / 2, y: $0.frame.minY,
                   width: $0.frame.width - $0.magnificationReserve, height: $0.surfaceHeight)
        } : nil
        let accumulating = options.accumulation
        for state in displays.values {
            let surfaces = DesktopSnowPolicy.surfaces(displayFrame: state.frame,
                windows: windowGeometry, includeWindows: Defaults[.desktopSnowWindowEdges], ownDockFrame: ownDockFrame,
                usableFrame: state.usableFrame, topSafeInset: state.topSafeInset)
            state.simulation.updateSurfaces(surfaces, accumulating: accumulating)
        }
    }

    private func readOptionalWindowGeometry() {
        guard isRunning, Defaults[.desktopSnowWindowEdges], options.accumulation,
              !locked, awake, activeSession, consoleUnlocked else { return }
        // This public metadata API is not a capture API. Read an explicit
        // allowlist only: bounds, identity, layer, alpha, owner PID. Never read
        // kCGWindowName/kCGWindowOwnerName or request pixels/TCC access.
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primaryTop = NSScreen.screens.first?.frame.maxY else {
            windowGeometry = []; windowEdgesAvailable = false; return
        }
        let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        let widgetPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").map(\.processIdentifier))
        let ownNormalWindows = Set(NSApp.windows.filter { $0.isVisible && $0.level == .normal && $0.canBecomeMain && $0.windowNumber > 0 }
            .map { UInt32($0.windowNumber) })
        var geometry: [DesktopSnowWindowGeometry] = []
        for item in list.prefix(512) {
            guard let owner = item[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = item[kCGWindowLayer as String] as? NSNumber,
                  let alpha = item[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue > 0.1,
                  let id = item[kCGWindowNumber as String] as? NSNumber,
                  let bounds = item[kCGWindowBounds as String] as? [String: Any],
                  let quartz = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  let frame = DesktopSnowPolicy.appKitFrame(quartz: quartz, primaryTop: primaryTop) else { continue }
            if owner.int32Value == ProcessInfo.processInfo.processIdentifier && !ownNormalWindows.contains(id.uint32Value) { continue }
            let isDock = owner.int32Value == dockPID && layer.intValue != 0
            // Only include widget-sized surfaces exposed by the system host.
            // A desktop/notification panel spanning the screen is not a widget.
            let isWidget = widgetPIDs.contains(owner.int32Value) && (60...420).contains(frame.width) && (60...420).contains(frame.height)
            guard layer.intValue == 0 || isDock || isWidget else { continue }
            // Exclude the Dock's screen-sized backdrop and tiny support
            // windows: only a plausible horizontal Dock strip can collect.
            if isDock && (frame.height > 180 || frame.width < 100 || frame.width < frame.height * 2) { continue }
            geometry.append(.init(id: id.uint32Value, frame: frame, isDock: isDock))
            if geometry.count == DesktopSnowPolicy.maximumWindowInputs { break }
        }
        windowGeometry = geometry
        let available = !geometry.isEmpty
        if windowEdgesAvailable != available { windowEdgesAvailable = available }
    }

    private func updateStatus(_ text: String) {
        let status = season.isSnow ? text : text.replacingOccurrences(of: "Snowing", with: "Weather active")
        if statusText != status { statusText = status }
    }
}

private enum DesktopSnowEditPhase { case began, dragged, ended }

@MainActor private final class DesktopSnowPanel: NSPanel {
    var isEditingCanvas = false
    var onFinishEditing: (() -> Void)?
    override var canBecomeKey: Bool { isEditingCanvas }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { if isEditingCanvas { onFinishEditing?() } }
    override func performClose(_ sender: Any?) { if isEditingCanvas { onFinishEditing?() } else { super.performClose(sender) } }
}

@MainActor private final class DesktopSnowEditorPanel: NSPanel {
    var onFinish: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onFinish?() }
    override func performClose(_ sender: Any?) { onFinish?() }
}

/// Bounded compositor-backed particles. Physics updates only at15/30Hz;
/// finite position animations bridge those samples at the display compositor's
/// cadence. Stable identities prevent array removals from moving another flake.
/// No per-frame full-screen drawRect or per-particle NSView is involved.
@MainActor private final class DesktopSnowSceneryHost: NSHostingView<DesktopSnowSceneLayer> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor private final class DesktopSnowView: NSView {
    private struct Style: Equatable {
        var opaque: Bool
        var contrast: Bool
        var season: DesktopSnowSeason
    }
    private final class ParticleEntry {
        let layer: CAShapeLayer
        var previous: DesktopSnowParticle?
        var style: Style?
        init(layer: CAShapeLayer) { self.layer = layer }
    }
    private final class BankEntry {
        let layer: CAShapeLayer
        let leaves = CAShapeLayer()
        var previous: DesktopSnowBank?
        var moundOptions: DesktopSnowOptions?
        var style: Style?
        init(layer: CAShapeLayer) {
            self.layer = layer
            layer.sublayers = [leaves]
        }
    }
    var onEditEvent: ((CGPoint, DesktopSnowEditPhase) -> Void)?
    private var isEditingCanvas = false
    private var brushRadius: Double = 30
    private var tracking: NSTrackingArea?
    private let brushRing = CAShapeLayer()
    private let particleContainer = CALayer()
    private let bankContainer = CALayer()
    private var particleEntries: [UInt64: ParticleEntry] = [:]
    private var freeParticles: [CAShapeLayer] = []
    private var bankEntries: [UInt64: BankEntry] = [:]
    private var freeBanks: [CAShapeLayer] = []
    private var exactBackingScale: CGFloat = 1
    private var sceneryHost: DesktopSnowSceneryHost?
    private var sceneryTheme: String?
    private var sceneryLowImpact = false

    func setScenery(theme: String?, lowImpact: Bool) {
        guard sceneryTheme != theme || sceneryLowImpact != lowImpact else { return }
        sceneryTheme = theme; sceneryLowImpact = lowImpact
        guard let theme else {
            sceneryHost?.removeFromSuperview(); sceneryHost = nil
            return
        }
        let scene = DesktopSnowSceneLayer(theme: theme, lowImpact: lowImpact)
        if let sceneryHost { sceneryHost.rootView = scene; return }
        let host = DesktopSnowSceneryHost(rootView: scene)
        host.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 78)
        host.autoresizingMask = [.width]
        addSubview(host)
        sceneryHost = host
    }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    init(frame frameRect: NSRect, backingScale: CGFloat) {
        exactBackingScale = CGFloat(DesktopSnowPolicy.backingScale(Double(backingScale)))
        super.init(frame: frameRect)
        setAccessibilityElement(false)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        layer?.isGeometryFlipped = false
        layer?.contentsScale = exactBackingScale
        layer?.shouldRasterize = false
        bankContainer.frame = bounds; particleContainer.frame = bounds
        bankContainer.contentsScale = exactBackingScale; particleContainer.contentsScale = exactBackingScale
        layer?.addSublayer(bankContainer); layer?.addSublayer(particleContainer)
        brushRing.isHidden = true; brushRing.fillColor = NSColor.white.withAlphaComponent(0.06).cgColor
        brushRing.strokeColor = NSColor.white.cgColor; brushRing.lineWidth = 1
        brushRing.shadowColor = NSColor.black.cgColor; brushRing.shadowOpacity = 0.7; brushRing.shadowRadius = 1
        brushRing.contentsScale = exactBackingScale; brushRing.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.addSublayer(brushRing)
    }
    required init?(coder: NSCoder) { nil }

    // The app-owned sublayers have all content. Avoid a backing bitmap redraw.
    func setEditing(_ active: Bool, radius: Double) {
        brushRadius = DesktopSnowPolicy.clamp(radius, 12...90, fallback: 30)
        guard isEditingCanvas != active else { return }
        isEditingCanvas = active
        if !active { brushRing.isHidden = true }
        setAccessibilityElement(active)
        if active {
            setAccessibilityRole(.group)
            setAccessibilityLabel("Snow editing canvas")
            setAccessibilityHelp("Drag along a snow edge to shape it. Press Escape to finish.")
        }
        updateTrackingAreas(); window?.invalidateCursorRects(for: self)
    }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking); self.tracking = nil }
        super.updateTrackingAreas()
        if isEditingCanvas {
            let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
            addTrackingArea(area); tracking = area
        }
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if isEditingCanvas { addCursorRect(bounds, cursor: .crosshair) }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { isEditingCanvas }
    override func mouseDown(with event: NSEvent) { edit(event, phase: .began) }
    override func mouseDragged(with event: NSEvent) { edit(event, phase: .dragged) }
    override func mouseUp(with event: NSEvent) { edit(event, phase: .ended) }
    override func mouseMoved(with event: NSEvent) {
        if isEditingCanvas { updateBrushRing(at: convert(event.locationInWindow, from: nil)) }
    }
    override func mouseExited(with event: NSEvent) { brushRing.isHidden = true }
    private func edit(_ event: NSEvent, phase: DesktopSnowEditPhase) {
        guard isEditingCanvas else { return }
        let point = convert(event.locationInWindow, from: nil)
        updateBrushRing(at: point); onEditEvent?(point, phase)
    }
    private func updateBrushRing(at point: CGPoint) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let diameter = brushRadius * 2
        if brushRing.bounds.width != diameter {
            brushRing.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            brushRing.path = CGPath(ellipseIn: brushRing.bounds, transform: nil)
        }
        brushRing.isHidden = false; brushRing.position = point
        CATransaction.commit()
    }

    override func updateLayer() {}

    func resetRenderer() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for entry in particleEntries.values { entry.layer.removeAllAnimations(); entry.layer.removeFromSuperlayer() }
        for value in freeParticles { value.removeAllAnimations(); value.removeFromSuperlayer() }
        for entry in bankEntries.values { entry.layer.removeAllAnimations(); entry.layer.removeFromSuperlayer() }
        for value in freeBanks { value.removeAllAnimations(); value.removeFromSuperlayer() }
        particleEntries = [:]; freeParticles = []; bankEntries = [:]; freeBanks = []
        particleContainer.removeAllAnimations(); particleContainer.sublayers = nil
        bankContainer.removeAllAnimations(); bankContainer.sublayers = nil
        CATransaction.commit()
    }

    func update(_ simulation: DesktopSnowSimulation, options: DesktopSnowOptions = .init(), season: DesktopSnowSeason = .winterDawn, frameInterval: TimeInterval = 0) {
        let style = Style(opaque: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                          contrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast, season: season)
        let scale = CGFloat(DesktopSnowPolicy.backingScale(Double(window?.backingScaleFactor ?? exactBackingScale)))
        let particles = Array(simulation.particles.prefix(DesktopSnowPolicy.maximumParticles))
        let particleIDs = Set(particles.map(\.id))
        let banks = Array(simulation.banks.prefix(DesktopSnowPolicy.maximumSurfaces))
        let bankIDs = Set(banks.map { $0.surface.id })
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if scale != exactBackingScale {
            exactBackingScale = scale; layer?.contentsScale = scale; brushRing.contentsScale = scale
            particleContainer.contentsScale = scale; bankContainer.contentsScale = scale
            for entry in bankEntries.values { entry.layer.contentsScale = scale }
        }
        particleContainer.frame = bounds; bankContainer.frame = bounds
        for id in particleEntries.keys.filter({ !particleIDs.contains($0) }) {
            guard let entry = particleEntries.removeValue(forKey: id) else { continue }
            entry.layer.removeAllAnimations(); entry.layer.removeFromSuperlayer()
            entry.layer.path = nil; entry.layer.isHidden = true
            freeParticles.append(entry.layer)
        }
        for particle in particles {
            let entry: ParticleEntry
            if let existing = particleEntries[particle.id] { entry = existing }
            else {
                guard particleEntries.count < DesktopSnowPolicy.maximumParticles else { break }
                let shape = freeParticles.popLast() ?? CAShapeLayer()
                shape.removeAllAnimations(); shape.isHidden = false
                shape.shouldRasterize = false; shape.allowsEdgeAntialiasing = true
                shape.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                particleContainer.addSublayer(shape)
                entry = ParticleEntry(layer: shape); particleEntries[particle.id] = entry
            }
            let shape = entry.layer
            // Sample presentation before changing the model. Replacing this
            // keyed linear animation stays C0-continuous under timer jitter.
            let displayedPosition = shape.presentation()?.position ?? shape.position
            let displayedOpacity = shape.presentation()?.opacity ?? shape.opacity
            let target = CGPoint(x: particle.x, y: particle.y)
            let alpha = style.opaque ? 1 : (particle.shedding
                ? min(0.8, max(0, (DesktopSnowPolicy.maximumSheddingLifetime - particle.age) * 0.35))
                : 0.55 + particle.radius * 0.1)
            let interpolate = DesktopSnowPolicy.shouldInterpolate(from: entry.previous, to: particle, frameInterval: frameInterval)
            if entry.previous?.radius != particle.radius || entry.style != style {
                let diameter = particle.radius * 2
                let width = season == .rainGarden ? max(1, diameter * 0.42) : diameter * (season.isSnow ? 1 : 1.45)
                let height = season == .rainGarden ? diameter * 3 : diameter
                shape.bounds = CGRect(x: 0, y: 0, width: width + 2, height: height + 2)
                shape.path = season.particlePath(in: CGRect(x: 1, y: 1, width: width, height: height), variant: Int(particle.id % 6))
                shape.fillColor = season.tint(variant: Int(particle.id % 6)).cgColor
                shape.strokeColor = style.contrast ? NSColor.black.withAlphaComponent(0.5).cgColor : nil
                shape.lineWidth = style.contrast ? 0.6 : 0
                entry.style = style
            }
            shape.contentsScale = scale
            shape.position = target; shape.opacity = Float(alpha)
            if interpolate {
                let duration = DesktopSnowPolicy.interpolationDuration(frameInterval: frameInterval)
                let movement = CABasicAnimation(keyPath: "position")
                movement.fromValue = NSValue(point: displayedPosition); movement.toValue = NSValue(point: target)
                movement.duration = duration; movement.timingFunction = CAMediaTimingFunction(name: .linear)
                shape.add(movement, forKey: "snow.position")
                if particle.shedding {
                    let fading = CABasicAnimation(keyPath: "opacity")
                    fading.fromValue = displayedOpacity; fading.toValue = Float(alpha)
                    fading.duration = duration; fading.timingFunction = CAMediaTimingFunction(name: .linear)
                    shape.add(fading, forKey: "snow.opacity")
                } else { shape.removeAnimation(forKey: "snow.opacity") }
            } else {
                // Births, wraps and teleports start exactly at their own new
                // location. A reused pool layer cannot sweep from an old flake.
                shape.removeAllAnimations()
            }
            entry.previous = particle
        }
        for id in bankEntries.keys.filter({ !bankIDs.contains($0) }) {
            guard let entry = bankEntries.removeValue(forKey: id) else { continue }
            entry.layer.removeAllAnimations(); entry.layer.removeFromSuperlayer(); entry.layer.path = nil
            freeBanks.append(entry.layer)
        }
        for bank in banks {
            let entry: BankEntry
            if let existing = bankEntries[bank.surface.id] { entry = existing }
            else {
                guard bankEntries.count < DesktopSnowPolicy.maximumSurfaces else { break }
                let shape = freeBanks.popLast() ?? CAShapeLayer()
                shape.removeAllAnimations(); shape.anchorPoint = .zero
                shape.shouldRasterize = false; shape.allowsEdgeAntialiasing = true
                bankContainer.addSublayer(shape)
                entry = BankEntry(layer: shape); bankEntries[bank.surface.id] = entry
            }
            if entry.previous != bank || entry.style != style || entry.moundOptions != options {
                let mounds = DesktopSnowPolicy.moundSilhouettes(for: bank, options: options)
                let shape = entry.layer
                let limit = bank.surface.kind == .bottom ? DesktopSnowPolicy.bottomRenderHeight(options: options) : 11 * options.moundHeight
                shape.position = CGPoint(x: bank.surface.left, y: bank.surface.y)
                shape.bounds = CGRect(x: 0, y: 0, width: bank.surface.right - bank.surface.left, height: limit + 1)
                shape.path = mounds.isEmpty ? nil : DesktopSnowMound.filledPath(for: mounds)
                shape.isHidden = mounds.isEmpty
                shape.fillColor = season.bankTint.cgColor; shape.opacity = style.opaque ? 1 : 0.94
                shape.strokeColor = style.contrast ? NSColor.black.withAlphaComponent(0.45).cgColor : nil
                shape.lineWidth = style.contrast ? 0.6 : 0
                shape.contentsScale = scale
                if season == .mapleAir {
                    let leaves = CGMutablePath()
                    for mound in mounds {
                        var nextX = mound.points.first?.x ?? 0
                        for (index, point) in mound.points.enumerated() where point.x >= nextX && point.y >= 2 {
                            let width = 3.5 + Double(index % 5) * 0.8
                            let height = min(point.y * 0.46, 3.4)
                            let y = point.y * (0.22 + Double(index % 7) * 0.055)
                            leaves.addPath(season.particlePath(in: CGRect(x: point.x - width / 2, y: y, width: width, height: height)))
                            nextX = point.x + 7 + Double(index % 5)
                        }
                    }
                    entry.leaves.path = leaves
                    entry.leaves.frame = shape.bounds
                    entry.leaves.fillColor = season.tint().withAlphaComponent(0.78).cgColor
                    entry.leaves.contentsScale = scale
                    entry.leaves.isHidden = false
                } else {
                    entry.leaves.path = nil
                    entry.leaves.isHidden = true
                }
                entry.previous = bank; entry.style = style; entry.moundOptions = options
            }
        }
        CATransaction.commit()
    }
}
