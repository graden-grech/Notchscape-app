import AppKit
import Combine

protocol ScreenBridgeTransport: AnyObject {
    var onReady: (() -> Void)? { get set }
    var onMessage: (([String: Any]) -> Void)? { get set }
    var onClose: ((String) -> Void)? { get set }
    func connect(host: String, code: String)
    func disconnect()
    func send(_ message: [String: Any])
}
extension SBLink: ScreenBridgeTransport {}
protocol ScreenBridgeInputRouting: AnyObject {
    var side: SBSide { get set }
    var displayID: String? { get set }
    var displays: [SBDisplayInfo] { get }
    var send: (([String: Any]) -> Void)? { get set }
    var status: ((String) -> Void)? { get set }
    func refreshDisplays()
    func start() -> Bool
    func stop()
    func returnLocal(notify: Bool, position: Double?)
    func receive(_ message: [String: Any])
}
extension SBInputBridge: ScreenBridgeInputRouting {}
extension ScreenBridgeInputRouting {
    func returnLocal(notify: Bool) { returnLocal(notify: notify, position: nil) }
}

/// Owns only an explicitly requested session. Opening Settings never captures input.
@MainActor
final class ScreenBridgeManager: ObservableObject {
    static let shared = ScreenBridgeManager()
    @Published var host: String
    @Published var code = ""
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published private(set) var status = "Not connected"
    @Published private(set) var side: SBSide
    @Published private(set) var macDisplays: [SBDisplayInfo] = []
    @Published private(set) var windowsDisplays: [SBDisplayInfo] = []
    @Published private(set) var macDisplay: String = ""
    @Published private(set) var windowsDisplay: String = ""
    private let link: ScreenBridgeTransport
    private let input: ScreenBridgeInputRouting
    private let defaults: UserDefaults
    private let isLocked: () -> Bool
    private let canCapture: () -> Bool
    private let otherClientRunning: () -> Bool
    private var screenObserver: NSObjectProtocol?
    private var sleepObservers: [NSObjectProtocol] = []

    init(link: ScreenBridgeTransport? = nil, input: ScreenBridgeInputRouting? = nil,
         defaults: UserDefaults = .standard,
         isLocked: @escaping () -> Bool = { ScreenBridgeManager.sessionLocked },
         canCapture: @escaping () -> Bool = { AXIsProcessTrusted() && CGPreflightListenEventAccess() },
         otherClientRunning: @escaping () -> Bool = {
            NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.graden.screenbridge" || $0.bundleURL?.lastPathComponent == "ScreenBridge.app" }
         }) {
        self.link = link ?? SBLink(); self.input = input ?? SBInputBridge()
        self.defaults = defaults; self.isLocked = isLocked; self.canCapture = canCapture
        self.otherClientRunning = otherClientRunning
        host = defaults.string(forKey: "screenBridgeHost") ?? ""
        side = SBSide(rawValue: defaults.string(forKey: "screenBridgeSide") ?? "") ?? .right
        self.input.side = side
        macDisplay = defaults.string(forKey: "screenBridgeMacDisplay") ?? ""
        windowsDisplay = defaults.string(forKey: "screenBridgeWindowsDisplay") ?? ""
        refreshDisplays()
        self.input.send = { [weak self] in self?.link.send($0) }
        self.input.status = { [weak self] in self?.status = $0 }
        self.link.onReady = { [weak self] in
            guard let self, self.connecting else { return }
            guard !self.isLocked() else { self.disconnect("Mac locked. Remote control stopped."); return }
            guard self.input.start() else {
                self.disconnect("Allow Accessibility and Input Monitoring for Notchscape, then try again.")
                return
            }
            self.connected = true; self.connecting = false; self.code = ""
            self.status = "Connected · controlling this Mac"
            self.refreshDisplays()
            self.link.send(["type": "displays", "displays": self.macDisplays.map(\.message)])
            self.syncLayout()
        }
        self.link.onClose = { [weak self] message in self?.finish(message) }
        self.link.onMessage = { [weak self] message in self?.receive(message) }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.input.returnLocal(notify: true); self.refreshDisplays()
                if self.connected {
                    self.link.send(["type": "displays", "displays": self.macDisplays.map(\.message)])
                    self.syncLayout()
                }
            }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            sleepObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.disconnect("Session ended. Connect again when you’re ready.") }
            })
        }
    }

    nonisolated static var sessionLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        return session["CGSSessionScreenIsLocked"] as? Bool == true
    }
    var permissionsReady: Bool { canCapture() }

    func connect() {
        guard !connected, !connecting else { return }
        guard !isLocked() else { status = "Unlock this Mac before connecting."; return }
        let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ScreenBridgeConnectionPolicy.validHost(address) else {
            status = "Enter the Windows computer’s address without a URL or port."; return
        }
        guard ScreenBridgeConnectionPolicy.validCode(code) else { status = "Enter the 10-character code shown on Windows."; return }
        guard permissionsReady else { status = "Allow Accessibility and Input Monitoring for Notchscape before connecting."; return }
        // A separate standalone client must not capture the same hardware twice.
        guard !otherClientRunning() else {
            status = "Quit the separate ScreenBridge app before connecting here."; return
        }
        host = address; defaults.set(address, forKey: "screenBridgeHost")
        connecting = true; status = "Connecting…"
        link.connect(host: address, code: code)
        code = ""
    }
    func disconnect(_ reason: String = "Not connected") {
        finish(reason); link.disconnect()
    }
    private func finish(_ reason: String) {
        input.stop(); connected = false; connecting = false; code = ""
        windowsDisplays = []; status = reason
    }
    func returnControl() { input.returnLocal(notify: true) }
    func setSide(_ value: SBSide) {
        input.returnLocal(notify: true); side = value; input.side = value
        defaults.set(value.rawValue, forKey: "screenBridgeSide")
        refreshDisplays(); syncLayout()
    }
    func selectMac(_ id: String) {
        guard macDisplays.contains(where: { $0.id == id }) else { return }
        input.returnLocal(notify: true); macDisplay = id; input.displayID = id
        defaults.set(id, forKey: "screenBridgeMacDisplay"); syncLayout()
    }
    func selectWindows(_ id: String) {
        guard windowsDisplays.contains(where: { $0.id == id }) else { return }
        input.returnLocal(notify: true); windowsDisplay = id
        defaults.set(id, forKey: "screenBridgeWindowsDisplay"); syncLayout()
    }
    private func refreshDisplays() {
        input.refreshDisplays(); macDisplays = input.displays
        if !macDisplays.contains(where: { $0.id == macDisplay }) { macDisplay = macDisplays.first?.id ?? "" }
        if !windowsDisplays.contains(where: { $0.id == windowsDisplay }) { windowsDisplay = windowsDisplays.first?.id ?? "" }
        input.displayID = macDisplay
    }
    private func syncLayout() {
        guard connected else { return }
        input.returnLocal(notify: true)
        link.send(["type": "layout", "side": side.rawValue, "macDisplay": macDisplay, "windowsDisplay": windowsDisplay])
    }
    private func receive(_ message: [String: Any]) {
        guard connected, !isLocked() else {
            if connected { disconnect("Mac locked. Remote control stopped.") }; return
        }
        if message["type"] as? String == "displays", let values = message["displays"] as? [[String: Any]], values.count <= 32 {
            windowsDisplays = values.compactMap(SBDisplayInfo.init); refreshDisplays(); syncLayout()
        } else if message["type"] as? String == "layout", let value = message["side"] as? String, let side = SBSide(rawValue: value) {
            input.returnLocal(notify: false); self.side = side; input.side = side
            if let id = message["macDisplay"] as? String { macDisplay = id }
            if let id = message["windowsDisplay"] as? String { windowsDisplay = id }
            refreshDisplays()
        } else { input.receive(message) }
    }
    func openPermissions(_ pane: String) {
        guard ["Privacy_Accessibility", "Privacy_ListenEvent"].contains(pane),
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
