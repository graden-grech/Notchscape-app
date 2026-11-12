import AppKit
import Combine
import CoreGraphics
import Defaults
import QuartzCore

extension Defaults.Keys {
    static let desktopSnowEnabled = Key<Bool>("desktopSnowEnabled", default: false)
    static let desktopSnowIntensity = Key<Double>("desktopSnowIntensity", default: 0.5)
    static let desktopSnowSpeed = Key<Double>("desktopSnowSpeed", default: 1)
    static let desktopSnowWind = Key<Double>("desktopSnowWind", default: 0)
    static let desktopSnowAccumulation = Key<Bool>("desktopSnowAccumulation", default: true)
    static let desktopSnowWindowEdges = Key<Bool>("desktopSnowWindowEdges", default: false)
    static let desktopSnowAllDisplays = Key<Bool>("desktopSnowAllDisplays", default: true)
}

/// Optional app-owned decoration. It neither captures pixels nor manipulates
/// other apps. Window geometry is an explicit, separate opt-in; no Screen
/// Recording, Accessibility, camera, or credential API is requested here.
@MainActor
final class DesktopSnowManager: NSObject, ObservableObject {
    static let shared = DesktopSnowManager()
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

    private override init() { super.init() }

    func start() {
        guard !started else { return }
        started = true
        locked = !consoleUnlocked
        awake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
        observePreference(.desktopSnowEnabled)
        observePreference(.desktopSnowIntensity)
        observePreference(.desktopSnowSpeed)
        observePreference(.desktopSnowWind)
        observePreference(.desktopSnowAccumulation)
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
            state.view.update(state.simulation, frameInterval: 1 / Double(frameRate ?? 30))
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

    private var options: DesktopSnowOptions {
        .init(intensity: Defaults[.desktopSnowIntensity], speed: Defaults[.desktopSnowSpeed],
              wind: Defaults[.desktopSnowWind], accumulation: Defaults[.desktopSnowAccumulation]).bounded
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
            displays[id] = DisplayState(frame: screen.frame, usableFrame: screen.visibleFrame,
                topSafeInset: screen.safeAreaInsets.top, panel: panel, view: view, simulation: simulation)
            view.update(simulation)
            panel.orderFrontRegardless()
        }
        guard !displays.isEmpty else { suspend(); updateStatus("Paused · No eligible display is available."); return }
        if !isRunning { isRunning = true; refreshSurfaces() }
        updateStatus(eligibility.status)
        if frameTimer == nil || frameRate != fps { startFrames(fps: fps) }
    }

    /// Lock/sleep/Presentation removes the windows, physics, geometry and
    /// timer immediately. Passive system notification subscriptions remain.
    private func suspend() {
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
            accumulation: Defaults[.desktopSnowAccumulation], now: now, lastSample: lastGeometryTime) {
            lastGeometryTime = now
            readOptionalWindowGeometry()
            refreshSurfaces()
        }
        let options = options
        let pointer = NSEvent.mouseLocation
        for state in displays.values {
            let localPointer = CGPoint(x: pointer.x - state.frame.minX, y: pointer.y - state.frame.minY)
            state.simulation.step(seconds: dt, options: options, lowImpact: frameRate == 15,
                                  pointer: state.frame.insetBy(dx: -110, dy: -110).contains(pointer) ? localPointer : nil)
            state.view.update(state.simulation, frameInterval: 1 / Double(frameRate ?? 30))
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
        let accumulating = Defaults[.desktopSnowAccumulation]
        for state in displays.values {
            let surfaces = DesktopSnowPolicy.surfaces(displayFrame: state.frame,
                windows: windowGeometry, includeWindows: Defaults[.desktopSnowWindowEdges], ownDockFrame: ownDockFrame,
                usableFrame: state.usableFrame, topSafeInset: state.topSafeInset)
            state.simulation.updateSurfaces(surfaces, accumulating: accumulating)
        }
    }

    private func readOptionalWindowGeometry() {
        guard isRunning, Defaults[.desktopSnowWindowEdges], Defaults[.desktopSnowAccumulation],
              !locked, awake, activeSession, consoleUnlocked else { return }
        // This public metadata API is not a capture API. Read an explicit
        // allowlist only: bounds, identity, layer, alpha, owner PID. Never read
        // kCGWindowName/kCGWindowOwnerName or request pixels/TCC access.
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primaryTop = NSScreen.screens.first?.frame.maxY else {
            windowGeometry = []; windowEdgesAvailable = false; return
        }
        let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
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
            guard layer.intValue == 0 || isDock else { continue }
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

    private func updateStatus(_ text: String) { if statusText != text { statusText = text } }
}

@MainActor private final class DesktopSnowPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Bounded compositor-backed particles. Physics updates only at15/30Hz;
/// finite position animations bridge those samples at the display compositor's
/// cadence. Stable identities prevent array removals from moving another flake.
/// No per-frame full-screen drawRect or per-particle NSView is involved.
@MainActor private final class DesktopSnowView: NSView {
    private struct Style: Equatable {
        var opaque: Bool
        var contrast: Bool
    }
    private final class ParticleEntry {
        let layer: CAShapeLayer
        var previous: DesktopSnowParticle?
        var style: Style?
        init(layer: CAShapeLayer) { self.layer = layer }
    }
    private final class BankEntry {
        let layer: CAShapeLayer
        var previous: DesktopSnowBank?
        var style: Style?
        init(layer: CAShapeLayer) { self.layer = layer }
    }
    private let particleContainer = CALayer()
    private let bankContainer = CALayer()
    private var particleEntries: [UInt64: ParticleEntry] = [:]
    private var freeParticles: [CAShapeLayer] = []
    private var bankEntries: [UInt64: BankEntry] = [:]
    private var freeBanks: [CAShapeLayer] = []
    private var exactBackingScale: CGFloat = 1
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
    }
    required init?(coder: NSCoder) { nil }

    // The app-owned sublayers have all content. Avoid a backing bitmap redraw.
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

    func update(_ simulation: DesktopSnowSimulation, frameInterval: TimeInterval = 0) {
        let style = Style(opaque: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                          contrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
        let scale = CGFloat(DesktopSnowPolicy.backingScale(Double(window?.backingScaleFactor ?? exactBackingScale)))
        let particles = Array(simulation.particles.prefix(DesktopSnowPolicy.maximumParticles))
        let particleIDs = Set(particles.map(\.id))
        let banks = Array(simulation.banks.prefix(DesktopSnowPolicy.maximumSurfaces))
        let bankIDs = Set(banks.map { $0.surface.id })
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if scale != exactBackingScale {
            exactBackingScale = scale; layer?.contentsScale = scale
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
                shape.bounds = CGRect(x: 0, y: 0, width: diameter + 2, height: diameter + 2)
                shape.path = CGPath(ellipseIn: CGRect(x: 1, y: 1, width: diameter, height: diameter), transform: nil)
                shape.fillColor = NSColor.white.cgColor
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
            if entry.previous != bank || entry.style != style {
                let mounds = DesktopSnowPolicy.moundSilhouettes(for: bank)
                let shape = entry.layer
                let path = CGMutablePath()
                for mound in mounds {
                    guard let first = mound.points.first, let last = mound.points.last else { continue }
                    path.move(to: first)
                    for index in 1..<mound.points.count {
                        let previous = mound.points[index - 1], point = mound.points[index]
                        let middle = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
                        path.addQuadCurve(to: middle, control: previous)
                    }
                    path.addQuadCurve(to: last, control: last); path.closeSubpath()
                }
                let limit = bank.surface.kind == .bottom ? 18.0 : 11.0
                shape.position = CGPoint(x: bank.surface.left, y: bank.surface.y)
                shape.bounds = CGRect(x: 0, y: 0, width: bank.surface.right - bank.surface.left, height: limit + 1)
                shape.path = mounds.isEmpty ? nil : path
                shape.isHidden = mounds.isEmpty
                shape.fillColor = NSColor.white.cgColor; shape.opacity = style.opaque ? 1 : 0.94
                shape.strokeColor = style.contrast ? NSColor.black.withAlphaComponent(0.45).cgColor : nil
                shape.lineWidth = style.contrast ? 0.6 : 0
                shape.contentsScale = scale
                entry.previous = bank; entry.style = style
            }
        }
        CATransaction.commit()
    }
}
