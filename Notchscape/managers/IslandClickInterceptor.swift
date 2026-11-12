import AppKit
import ApplicationServices
import Combine
import CoreGraphics

enum IslandClickPauseReason: Equatable {
    case inactiveSession, lockedSession, displayAsleep, inactiveApp
    case windowUnavailable, geometryChanged, displayChanged, tapDisabled, tapUnavailable
    case nativeHardwareUnverified, menuTracking

    var message: String {
        switch self {
        case .inactiveSession: "Paused: this desktop session is inactive"
        case .lockedSession: "Paused while the Mac is locked"
        case .displayAsleep: "Paused while the display is asleep"
        case .inactiveApp: "Paused: activate the test window and start again"
        case .windowUnavailable: "Paused: the test window is no longer active"
        case .geometryChanged: "Paused: the test window moved or changed size"
        case .displayChanged: "Paused: display geometry changed; configure the test again"
        case .tapDisabled: "Paused: macOS disabled the input tap; start again to retry"
        case .tapUnavailable: "Paused: macOS could not create the input tap"
        case .nativeHardwareUnverified: "Native hardware routing is unverified and disabled"
        case .menuTracking: "Paused while a menu is open; start the test again"
        }
    }
}

enum IslandClickInterceptorStatus: Equatable {
    case off, permissionNeeded, unconfigured, runningTestWindow, runningNativeUnverified
    case paused(IslandClickPauseReason)

    var isRunning: Bool {
        self == .runningTestWindow || self == .runningNativeUnverified
    }
    var message: String {
        switch self {
        case .off: "Off"
        case .permissionNeeded: "Accessibility permission is needed; enable it in System Settings"
        case .unconfigured: "Choose a valid visible interaction area"
        case .runningTestWindow: "Active only inside the Notchscape test window"
        case .runningNativeUnverified: "Native prototype active; hardware routing remains unverified"
        case .paused(let reason): reason.message
        }
    }
}

/// Explicitly started, default-off public event-tap prototype. It does not
/// replace Apple's island, claim hardware compatibility, or request access.
@MainActor
final class IslandClickInterceptor: ObservableObject {
    @Published private(set) var status: IslandClickInterceptorStatus = .off

    private let onActivate: @MainActor () -> Void
    private var sessionIsActive = false
    private var sessionIsUnlocked = false
    private var displayIsAwake = false
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapContext: IslandClickTapContext?
    private weak var testWindow: NSWindow?
    private var profile: IslandClickProfile?
    private var generation: UInt64 = 0
    private var observationRemovers: [() -> Void] = []
    private var windowObservationRemovers: [() -> Void] = []

    init(onActivate: @escaping @MainActor () -> Void) {
        self.onActivate = onActivate
        observeLifecycle()
    }

    /// Root session security supplies the initial state. A missing/unknown
    /// state remains ineligible. Updating it never starts or resumes a tap.
    func updateSession(isActive: Bool, isUnlocked: Bool, isAwake: Bool) {
        sessionIsActive = isActive
        sessionIsUnlocked = isUnlocked
        displayIsAwake = isAwake
        if let reason = sessionPauseReason { pauseIfRunning(reason) }
    }

    /// Rectangles are in the actual window.contentView coordinate system,
    /// including its bounds origin and isFlipped value; never screen or pixels.
    /// Only a currently key, visible Notchscape-owned window may be configured.
    @discardableResult
    func startTestWindow(_ window: NSWindow, contentViewLocalRects: [CGRect],
                         coordinateSpace: DisplayCoordinateSpace,
                         protectedContentViewLocalRects: [CGRect] = []) -> Bool {
        prepareForStart()
        guard isEligibleTestWindow(window), let view = window.contentView,
              !contentViewLocalRects.isEmpty, contentViewLocalRects.count <= 16,
              protectedContentViewLocalRects.count <= 32,
              (contentViewLocalRects + protectedContentViewLocalRects)
                .allSatisfy({ view.bounds.contains($0) }) else {
            status = .unconfigured
            return false
        }
        let contentOnScreen = window.convertToScreen(view.convert(view.bounds, to: nil))
        guard let bounding = coordinateSpace.quartzRect(fromAppKit: contentOnScreen) else {
            status = .unconfigured
            return false
        }
        let regions = contentViewLocalRects.compactMap {
            coordinateSpace.quartzRect(fromAppKit: window.convertToScreen(view.convert($0, to: nil)))
        }
        let protected = protectedContentViewLocalRects.compactMap {
            coordinateSpace.quartzRect(fromAppKit: window.convertToScreen(view.convert($0, to: nil)))
        }
        guard regions.count == contentViewLocalRects.count,
              protected.count == protectedContentViewLocalRects.count,
              let geometry = IslandClickGeometry.validated(profile: .appOwnedTestWindow,
                  boundingRect: bounding, allowedRects: regions, protectedRects: protected) else {
            status = .unconfigured
            return false
        }
        testWindow = window
        observeTestWindow(window)
        return start(geometry: geometry)
    }

    /// Intentionally unavailable until a manually measured, non-simulated
    /// DisplayGeometrySnapshot can validate exact bounds and camera exclusions.
    /// A boolean acknowledgement or arbitrary rectangle is not sufficient.
    @discardableResult
    func startNativePrototype() -> Bool {
        prepareForStart()
        status = .paused(.nativeHardwareUnverified)
        return false
    }

    func stop() {
        prepareForStart()
        status = .off
    }

    private var sessionPauseReason: IslandClickPauseReason? {
        if !sessionIsActive { return .inactiveSession }
        if !sessionIsUnlocked { return .lockedSession }
        if !displayIsAwake { return .displayAsleep }
        return nil
    }

    private func isEligibleTestWindow(_ window: NSWindow) -> Bool {
        NSApp.isActive && NSApp.windows.contains(where: { $0 === window })
            && window.isVisible && window.isKeyWindow && !window.isMiniaturized
            && window.alphaValue > 0.01 && window.occlusionState.contains(.visible)
    }

    private func start(geometry: IslandClickGeometry) -> Bool {
        guard geometry.profile == .appOwnedTestWindow else {
            status = .paused(.nativeHardwareUnverified)
            return false
        }
        if let reason = sessionPauseReason { status = .paused(reason); return false }
        guard AXIsProcessTrusted() else { status = .permissionNeeded; return false }
        var runtime = IslandClickRuntime()
        runtime.enabled = true
        runtime.sessionIsActive = sessionIsActive
        runtime.sessionIsUnlocked = sessionIsUnlocked
        runtime.displayIsAwake = displayIsAwake
        runtime.appIsActive = NSApp.isActive
        runtime.testWindowIsActive = testWindow.map(isEligibleTestWindow) ?? false
        runtime.geometry = geometry
        guard runtime.isEligible else { status = .unconfigured; return false }
        let token = generation
        let context = IslandClickTapContext(runtime: runtime, onActivate: { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.deliverActivation(generation: token) }
        }, onDisabled: { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.pauseIfRunning(.tapDisabled)
            }
        })
        // A claimed left gesture's drag remainder is consumed, with activation
        // cancelled. Unclaimed drags pass. No key, mouse-move, scroll,
        // right-button or system-activity mask exists.
        let mask = [CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: islandClickTapCallback,
            userInfo: Unmanaged.passUnretained(context).toOpaque()) else {
            status = .paused(.tapUnavailable)
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap)
            status = .paused(.tapUnavailable)
            return false
        }
        tapContext = context
        tap = newTap
        runLoopSource = source
        profile = geometry.profile
        // Retain context until this main-run-loop source is removed/invalidated.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        guard CGEvent.tapIsEnabled(tap: newTap) else {
            tearDownTap()
            status = .paused(.tapUnavailable)
            return false
        }
        status = .runningTestWindow
        return true
    }

    private func deliverActivation(generation token: UInt64) {
        guard generation == token, status.isRunning, sessionPauseReason == nil else { return }
        if profile == .appOwnedTestWindow {
            guard let testWindow, isEligibleTestWindow(testWindow) else { return }
        }
        onActivate()
    }

    private func prepareForStart() {
        generation &+= 1
        tearDownTap()
        windowObservationRemovers.forEach { $0() }
        windowObservationRemovers.removeAll()
        testWindow = nil
        profile = nil
    }

    private func tearDownTap() {
        // A stop/lock/sleep/invalidation must release the tap immediately. If
        // this interrupts an already claimed press, remaining physical events
        // fail open; we do not keep filtering or synthesize a replacement down.
        tapContext?.invalidate()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        runLoopSource = nil
        tap = nil
        tapContext = nil
    }

    private func pauseIfRunning(_ reason: IslandClickPauseReason) {
        guard status.isRunning else { return }
        prepareForStart()
        status = .paused(reason)
    }

    private func observe(_ center: NotificationCenter, name: Notification.Name,
                         object: Any? = nil, windowScoped: Bool = false,
                         action: @escaping @MainActor (IslandClickInterceptor) -> Void) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        let remove = { center.removeObserver(token) }
        if windowScoped { windowObservationRemovers.append(remove) }
        else { observationRemovers.append(remove) }
    }

    private func observeLifecycle() {
        let app = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observe(app, name: NSApplication.didResignActiveNotification) {
            if $0.profile == .appOwnedTestWindow { $0.pauseIfRunning(.inactiveApp) }
        }
        observe(app, name: NSApplication.didChangeScreenParametersNotification) { $0.pauseIfRunning(.displayChanged) }
        observe(app, name: NSMenu.didBeginTrackingNotification) { $0.pauseIfRunning(.menuTracking) }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observe(workspace, name: name) { $0.displayIsAwake = false; $0.pauseIfRunning(.displayAsleep) }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observe(workspace, name: name) { $0.displayIsAwake = true }
        }
        observe(workspace, name: NSWorkspace.sessionDidResignActiveNotification) {
            $0.sessionIsActive = false; $0.sessionIsUnlocked = false; $0.pauseIfRunning(.inactiveSession)
        }
        observe(workspace, name: NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionIsActive = true }
        // These session notifications are also used by the existing app lock
        // gate. They only tighten this prototype's state; they never restart it.
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, name: .init("com.apple.screenIsLocked")) {
            $0.sessionIsUnlocked = false; $0.pauseIfRunning(.lockedSession)
        }
        observe(distributed, name: .init("com.apple.screenIsUnlocked")) { $0.sessionIsUnlocked = true }
    }

    private func observeTestWindow(_ window: NSWindow) {
        let center = NotificationCenter.default
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didResignKeyNotification] {
            observe(center, name: name, object: window, windowScoped: true) { $0.pauseIfRunning(.windowUnavailable) }
        }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.didChangeScreenNotification] {
            observe(center, name: name, object: window, windowScoped: true) { $0.pauseIfRunning(.geometryChanged) }
        }
        observe(center, name: NSWindow.didChangeOcclusionStateNotification, object: window, windowScoped: true) {
            guard let window = $0.testWindow, $0.isEligibleTestWindow(window) else {
                $0.pauseIfRunning(.windowUnavailable)
                return
            }
        }
    }

    deinit {
        observationRemovers.forEach { $0() }
        windowObservationRemovers.forEach { $0() }
        tapContext?.invalidate()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
    }
}

/// The callback never waits on a lock: contention passes the event through.
/// Manager/lifecycle updates use the same tiny state container outside callback.
private final class IslandClickTapContext: @unchecked Sendable {
    private let lock = NSLock()
    private var policy = IslandClickPolicy()
    private var runtime: IslandClickRuntime
    private let onActivate: @Sendable () -> Void
    private let onDisabled: @Sendable () -> Void

    init(runtime: IslandClickRuntime, onActivate: @escaping @Sendable () -> Void,
         onDisabled: @escaping @Sendable () -> Void) {
        self.runtime = runtime
        self.onActivate = onActivate
        self.onDisabled = onDisabled
    }

    func invalidate() {
        lock.lock()
        runtime.enabled = false
        policy.reset()
        lock.unlock()
    }

    func handle(type: CGEventType, event: CGEvent) -> IslandClickDecision {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // macOS already disabled the tap; never automatically re-enable it.
            onDisabled()
            return .passThrough
        }
        let kind: IslandClickEventKind
        switch type {
        case .leftMouseDown: kind = .leftDown
        case .leftMouseUp: kind = .leftUp
        case .leftMouseDragged: kind = .leftDragged
        default: return .passThrough
        }
        guard lock.try() else { return .passThrough }
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate,
                                      .maskShift, .maskSecondaryFn, .maskHelp]
        let input = IslandClickEvent(kind: kind, location: event.location,
            timestamp: Double(event.timestamp) / 1_000_000_000,
            hasConflictingModifiers: !event.flags.intersection(modifiers).isEmpty)
        let decision = policy.handle(input, runtime: runtime)
        lock.unlock()
        if decision == .consumeAndActivate { onActivate() }
        return decision
    }
}

private let islandClickTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<IslandClickTapContext>.fromOpaque(userInfo).takeUnretainedValue()
    return context.handle(type: type, event: event).consumesEvent ? nil : Unmanaged.passUnretained(event)
}
