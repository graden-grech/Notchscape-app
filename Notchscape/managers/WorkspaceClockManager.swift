import AppKit
import Combine
import IOKit.pwr_mgt

@MainActor
final class WorkspaceClockManager: ObservableObject {
    static let shared = WorkspaceClockManager()
    @Published private(set) var stopwatchRunning = false
    @Published private(set) var laps: [StopwatchLap] = []
    private var accumulated = 0.0
    private let monotonic = ContinuousClock()
    private var stopwatchStart: ContinuousClock.Instant?
    var elapsed: TimeInterval {
        guard let stopwatchStart else { return accumulated }
        let parts = stopwatchStart.duration(to: monotonic.now).components
        return accumulated + Double(parts.seconds) + Double(parts.attoseconds)/1e18
    }
    @Published private(set) var focusPhase: FocusPhase = .finished
    @Published private(set) var round = 0
    @Published private(set) var cycle = FocusCycle()
    @Published private(set) var focusEnd: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var keepAwakeEnd: Date?
    @Published private(set) var error: String?
    private var focusTask: Task<Void, Never>?
    private var awakeTask: Task<Void, Never>?
    private var assertion: IOPMAssertionID = 0
    private var observations = Set<AnyCancellable>()
    private init() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .merge(with: NotificationCenter.default.publisher(for: .NSSystemClockDidChange))
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.reconcile() }.store(in: &observations)
        WorkspaceModeManager.shared.$session.dropFirst().receive(on: RunLoop.main).sink { [weak self] session in
            if session?.mode.hidesPrivateContent == true || session?.mode == .travel { self?.stopKeepAwake() }
        }.store(in: &observations)
    }
    func toggleStopwatch() {
        if stopwatchRunning { accumulated = elapsed; stopwatchStart = nil }
        else { stopwatchStart = monotonic.now }
        stopwatchRunning.toggle()
    }
    func resetStopwatch() { stopwatchStart = nil; accumulated = 0; stopwatchRunning = false; laps = [] }
    func lap() { guard stopwatchRunning, laps.count < 500 else { return }; let value = elapsed; laps.append(.init(total: value, split: value-(laps.last?.total ?? 0))) }
    func startFocus(_ value: FocusCycle) {
        guard value.isValid else { return }; cancelFocus(); cycle = value; round = 1; focusPhase = .work
        focusEnd = Date().addingTimeInterval(Double(value.workMinutes*60)); scheduleFocus()
    }
    func toggleFocusPause() {
        if let end = focusEnd { pausedRemaining = max(0, end.timeIntervalSinceNow); focusEnd = nil; focusTask?.cancel() }
        else if let remaining = pausedRemaining { pausedRemaining = nil; focusEnd = Date().addingTimeInterval(remaining); scheduleFocus() }
    }
    func cancelFocus() { focusTask?.cancel(); focusTask = nil; focusPhase = .finished; focusEnd = nil; pausedRemaining = nil; round = 0 }
    private func scheduleFocus() {
        focusTask?.cancel(); guard let end = focusEnd else { return }
        focusTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow))) } catch { return }
            guard !Task.isCancelled, let self, focusEnd == end else { return }; reconcileFocus()
        }
    }
    private func reconcileFocus() {
        guard let end = focusEnd else { return }
        guard end <= Date() else { scheduleFocus(); return }
        // No replay of dozens of phases after sleep. One transition at most.
        if focusPhase == .work && round < cycle.rounds { focusPhase = .rest; focusEnd = Date().addingTimeInterval(Double(cycle.breakMinutes*60)) }
        else if focusPhase == .rest { round += 1; focusPhase = .work; focusEnd = Date().addingTimeInterval(Double(cycle.workMinutes*60)) }
        else { focusPhase = .finished; focusEnd = nil }
        scheduleFocus()
    }
    func startKeepAwake(minutes: Int) {
        guard WorkspaceAccess.privateToolsAllowed, [15,30,60,120].contains(minutes), WorkspaceModeManager.shared.active?.pauseWallpapers != true else { return }
        stopKeepAwake()
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), "Notchscape timed Keep Awake" as CFString, &assertion)
        guard result == kIOReturnSuccess else { assertion = 0; error = "macOS couldn’t start Keep Awake."; return }
        error = nil; keepAwakeEnd = Date().addingTimeInterval(Double(minutes*60)); scheduleAwake()
    }
    func stopKeepAwake() { awakeTask?.cancel(); awakeTask = nil; if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }; keepAwakeEnd = nil }
    private func scheduleAwake() {
        awakeTask?.cancel(); guard let end = keepAwakeEnd else { return }
        if end <= Date() { stopKeepAwake(); return }
        awakeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow))) } catch { return }
            guard !Task.isCancelled else { return }; self?.scheduleAwake()
        }
    }
    private func reconcile() { reconcileFocus(); scheduleAwake() }
}
