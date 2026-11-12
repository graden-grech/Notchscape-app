import AppKit
import Combine
import Defaults
import Security

extension Defaults.Keys {
    static let dockWidgetEnabled = Key<Bool>("dockWidgetEnabled", default: false)
    static let dockWidgetKind = Key<String>("dockWidgetKind", default: "clock")
}

/// Owns only the optional child app's Dock tile. Never changes system Dock
/// preferences or the main app's independent activation policy.
@MainActor
final class DockWidgetManager: ObservableObject {
    static let shared = DockWidgetManager()
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?
    private let hostID = "com.graden-grech.Notchscape.DockWidget"
    private let controlName = Notification.Name("com.graden-grech.Notchscape.DockWidget.control")
    private let eventName = Notification.Name("com.graden-grech.Notchscape.DockWidget.event")
    private var subscriptions = Set<AnyCancellable>()
    private var application: NSRunningApplication?
    private var launchTask: Task<Void, Never>?
    private var token: String?
    private var generation: UInt64 = 0
    private var started = false
    private var stopping = false
    private var retryAfterTermination = false
    private var readyTimeout: Task<Void, Never>?

    private var requested: Bool { Defaults[.dockWidgetEnabled] && !Defaults[.dockReplacementEnabled] }

    private init() {}

    func start() {
        guard !started else { return }; started = true
        Defaults.publisher(.dockWidgetEnabled).receive(on: RunLoop.main).sink { [weak self] _ in
            self?.reconcile()
        }.store(in: &subscriptions)
        Defaults.publisher(.dockReplacementEnabled).receive(on: RunLoop.main).sink { [weak self] _ in
            self?.reconcile()
        }.store(in: &subscriptions)
        Defaults.publisher(.dockWidgetKind).receive(on: RunLoop.main).sink { [weak self] _ in
            self?.reconcile()
        }.store(in: &subscriptions)
        WorkspaceModeManager.shared.$session.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.configure()
        }.store(in: &subscriptions)
        DistributedNotificationCenter.default().publisher(for: eventName)
            .receive(on: RunLoop.main).sink { [weak self] note in self?.receive(note) }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .receive(on: RunLoop.main).sink { [weak self] note in
                guard let self, let ended = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      ended.processIdentifier == application?.processIdentifier else { return }
                application = nil; isRunning = false; token = nil
                readyTimeout?.cancel(); readyTimeout = nil
                let retry = retryAfterTermination || (stopping && requested)
                retryAfterTermination = false; stopping = false
                if retry { reconcile() }
                else if requested {
                    errorMessage = "The Dock widget closed. Choose Try Again to reopen it."
                }
            }.store(in: &subscriptions)
        reconcile()
    }

    func stop() {
        started = false; generation &+= 1
        launchTask?.cancel(); launchTask = nil
        readyTimeout?.cancel(); readyTimeout = nil
        retryAfterTermination = false; stopping = true
        send(["command": "quit"])
        application?.terminate()
        application = nil; token = nil; isRunning = false
        subscriptions.removeAll()
    }

    func restart() {
        guard requested else { return }
        errorMessage = nil
        if let application, !application.isTerminated {
            retryAfterTermination = true; stopping = true
            send(["command": "quit"])
            application.terminate()
        } else { reconcile() }
    }

    private func reconcile() {
        guard started else { return }
        guard requested else {
            // NSWorkspace's native launch can outlive Task cancellation. Keep
            // the in-flight slot occupied until its callback has drained.
            readyTimeout?.cancel(); readyTimeout = nil
            stopping = true; retryAfterTermination = false
            send(["command": "quit"]); application?.terminate()
            isRunning = false; errorMessage = nil
            return
        }
        guard ["clock", "battery", "calendar"].contains(Defaults[.dockWidgetKind]) else {
            errorMessage = "Choose Clock, Battery or Calendar for the Dock widget."; return
        }
        if let application, !application.isTerminated {
            if stopping { retryAfterTermination = true }
            else { configure() }
            return
        }
        guard launchTask == nil else { return }
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/NotchscapeDockWidget.app")
        guard verifiedHost(at: url) else {
            errorMessage = "The signed Dock widget is missing or invalid. Reinstall the complete Notchscape app."; return
        }
        // Do not attach to an unrelated or leftover instance using a new token.
        guard NSRunningApplication.runningApplications(withBundleIdentifier: hostID).isEmpty else {
            errorMessage = "Another Dock widget is already running. Quit that widget, then choose Try Again."; return
        }
        generation &+= 1; let attempt = generation
        let controlToken = UUID().uuidString
        token = controlToken; stopping = false; errorMessage = nil
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.arguments = ["--widget", Defaults[.dockWidgetKind], "--owner-pid", String(ProcessInfo.processInfo.processIdentifier), "--control-token", controlToken]
        launchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var retryAfterLaunch = false
            defer {
                if attempt == generation {
                    launchTask = nil
                    if retryAfterLaunch { reconcile() }
                }
            }
            do {
                let app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                guard !Task.isCancelled, started, attempt == generation else {
                    app.terminate(); return
                }
                application = app
                if app.isTerminated {
                    let wasStopping = stopping
                    application = nil; token = nil; stopping = false
                    retryAfterLaunch = requested && wasStopping
                    if !retryAfterLaunch, requested {
                        errorMessage = "The Dock widget closed during startup. Choose Try Again."
                    }
                    return
                }
                guard requested, !stopping else {
                    retryAfterTermination = requested
                    stopping = true; send(["command": "quit"]); app.terminate()
                    return
                }
                configure()
                if !isRunning {
                    readyTimeout = Task { @MainActor [weak self] in
                        do { try await Task.sleep(for: .seconds(8)) } catch { return }
                        guard let self, attempt == generation, !isRunning, requested else { return }
                        errorMessage = "The Dock widget did not finish starting. Choose Try Again."
                    }
                }
            } catch {
                guard attempt == generation else { return }
                token = nil; isRunning = false
                errorMessage = "macOS could not open the Dock widget. Choose Try Again."
            }
        }
    }

    private func configure() {
        guard started, requested, !stopping else { return }
        send(["command": "configure", "widget": Defaults[.dockWidgetKind],
              "presenting": WorkspaceModeManager.shared.active?.hidesPrivateContent == true])
    }

    private func send(_ payload: [String: Any]) {
        guard let token else { return }
        DistributedNotificationCenter.default().postNotificationName(controlName, object: token,
                                                                     userInfo: payload, deliverImmediately: true)
    }

    private func receive(_ note: Notification) {
        guard let token, note.object as? String == token, let event = note.userInfo?["event"] as? String else { return }
        switch event {
        case "ready":
            guard requested, !stopping else {
                stopping = true; send(["command": "quit"]); return
            }
            isRunning = true; errorMessage = nil; readyTimeout?.cancel(); readyTimeout = nil; configure()
        case "openWorkspace":
            guard requested, !stopping else { return }
            DockWorkspaceManager.shared.show()
        case "selectedWidget":
            guard !stopping, let kind = note.userInfo?["widget"] as? String,
                  ["clock", "battery", "calendar"].contains(kind) else { return }
            Defaults[.dockWidgetKind] = kind
        case "removed":
            guard !stopping else { return }
            Defaults[.dockWidgetEnabled] = false
        default: break
        }
    }

    private func verifiedHost(at url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        let text = "anchor apple generic and identifier \"\(hostID)\" and certificate leaf[subject.OU] = \"6H86CTRJCP\""
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }
}
