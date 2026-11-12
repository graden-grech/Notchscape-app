import AppKit
import Combine
import Darwin
import Defaults
import Foundation
import Security

extension Defaults.Keys {
    static let dockHideSystemDock = Key<Bool>("dockHideSystemDock", default: false)
}

/// Main-app adapter only. The separately running signed guardian owns all
/// preference writes and restores on parent exit even if this process crashes.
@MainActor final class DockVisibilityController: ObservableObject {
    static let shared = DockVisibilityController()
    @Published private(set) var statusText: String?
    private var started = false
    private var requested = false
    private var barVisible = false
    private var blocked = false
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var ready = false
    private var applying = false
    private var applied = false
    private var closing = false
    private var generation: UInt64 = 0
    private var readyDeadline: Task<Void, Never>?
    private var activationObserver: AnyCancellable?
    private var childStart: (UInt64, UInt64)?
    private var wantsHide: Bool { requested && barVisible && !blocked }

    private init() {}

    /// Only for the normal widget manager's duplicate-process check if direct
    /// CLI launch is nevertheless registered by a future Launch Services build.
    /// Never excludes an arbitrary process merely sharing the bundle ID.
    func ownsGuardianProcess(_ pid: pid_t) -> Bool {
        guard let process, process.isRunning, process.processIdentifier == pid, let childStart else { return false }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size &&
            info.pbi_uid == getuid() && info.pbi_ruid == getuid() &&
            info.pbi_start_tvsec == childStart.0 && info.pbi_start_tvusec == childStart.1
    }

    func start() {
        guard !started else { return }; started = true
        activationObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self, applied, !closing else { return }
                send("CHECK")
            }
        // Recovery is always allowed to run; it never implies enabling hide.
        launch()
    }

    func update(barVisible: Bool, requested: Bool) {
        if self.requested != requested || self.barVisible != barVisible {
            DockFocusDiagnostics.shared.record("nativeVisibilityRequest", state: barVisible && requested)
        }
        if !requested { blocked = false }
        self.requested = requested; self.barVisible = barVisible
        guard started else { return }
        reconcile()
    }

    func restoreNow() {
        requested = false; blocked = false
        if process == nil { launch() } else { requestRestore() }
    }

    private func reconcile() {
        if wantsHide {
            if process == nil { launch() }
            else if ready, !closing, !applied, !applying {
                applying = true; send("APPLY")
            }
        } else if process != nil { requestRestore() }
    }

    private func launch() {
        guard process == nil else { return }
        let bundle = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/NotchscapeDockWidget.app")
        guard verifiedHelper(bundle) else {
            blocked = true; statusText = "The signed Dock recovery helper is missing or invalid. Reinstall the complete Notchscape app."
            return
        }
        let incoming = Pipe(), outgoing = Pipe()
        let child = Process()
        child.executableURL = bundle.appendingPathComponent("Contents/MacOS/NotchscapeDockWidget")
        child.arguments = [DockVisibilityPolicy.guardianFlag, "--owner-pid", String(getpid())]
        child.standardInput = incoming; child.standardOutput = outgoing; child.standardError = FileHandle.nullDevice
        generation &+= 1; let attempt = generation
        process = child; input = incoming.fileHandleForWriting; output = outgoing.fileHandleForReading
        buffer.removeAll(keepingCapacity: true); ready = false; applying = false; applied = false; closing = false
        // Never block the UI or terminate it with SIGPIPE if the helper exits.
        _ = fcntl(incoming.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let flags = fcntl(incoming.fileHandleForWriting.fileDescriptor, F_GETFL)
        if flags >= 0 { _ = fcntl(incoming.fileHandleForWriting.fileDescriptor, F_SETFL, flags | O_NONBLOCK) }
        outgoing.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.receive(data, generation: attempt) }
        }
        child.terminationHandler = { [weak self] child in
            let status = child.terminationStatus
            Task { @MainActor in self?.terminated(status: status, generation: attempt) }
        }
        do {
            try child.run()
            try? incoming.fileHandleForReading.close(); try? outgoing.fileHandleForWriting.close()
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            if proc_pidinfo(child.processIdentifier, PROC_PIDTBSDINFO, 0, &info, size) == size {
                childStart = (info.pbi_start_tvsec, info.pbi_start_tvusec)
            }
            readyDeadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                guard let self, generation == attempt, !ready else { return }
                blocked = true; statusText = "Dock recovery did not finish starting. Choose Restore macOS Dock to retry."
                requestRestore()
            }
        } catch {
            try? incoming.fileHandleForReading.close(); try? outgoing.fileHandleForWriting.close()
            cleanup(); blocked = true
            statusText = "macOS could not start Dock recovery. Your Dock preferences were not changed by this attempt."
        }
    }

    private func receive(_ data: Data, generation attempt: UInt64) {
        guard generation == attempt, process != nil else { return }
        guard !data.isEmpty else { output?.readabilityHandler = nil; return }
        buffer.append(data)
        guard buffer.count <= 1_024 else { protocolFailure(); return }
        while let end = buffer.firstIndex(of: 10) {
            guard end <= 96, let message = String(data: buffer.prefix(upTo: end), encoding: .utf8) else {
                protocolFailure(); return
            }
            buffer.removeSubrange(...end)
            switch message {
            case "READY":
                DockFocusDiagnostics.shared.record("guardianReady")
                guard !ready else { protocolFailure(); return }
                ready = true; readyDeadline?.cancel(); readyDeadline = nil
                if closing { send("RESTORE") } else { reconcile() }
            case "APPLIED":
                DockFocusDiagnostics.shared.record("guardianApplied")
                applied = true; applying = false
                if wantsHide, !closing { statusText = "macOS Dock stays hidden while Dock Bar is on. System commands may still reveal it." }
                else { requestRestore() }
            case "RESTORED":
                DockFocusDiagnostics.shared.record("guardianRestored")
                applied = false; applying = false; closing = true
                if !blocked { statusText = nil }
            case "OVERRIDDEN":
                DockFocusDiagnostics.shared.record("guardianOverridden")
                applied = false; applying = false; closing = true; blocked = true
                statusText = "Dock settings changed outside Notchscape. Your changes were kept; turn this option off and on to apply it again."
            default:
                guard message.hasPrefix("ERROR:"),
                      let failure = DockVisibilityFailure(rawValue: String(message.dropFirst(6))) else {
                    protocolFailure(); return
                }
                blocked = true; closing = true; applying = false
                DockFocusDiagnostics.shared.record("guardianError_" + failure.rawValue)
                statusText = failure == .recovery
                    ? "Dock restoration could not be verified. Choose Restore macOS Dock to retry; your saved Dock settings are retained."
                    : "Dock recovery could not complete (\(failure.rawValue)). Choose Restore macOS Dock to retry."
            }
        }
    }

    private func requestRestore() {
        guard process != nil else { return }
        guard !closing else { return }; closing = true
        readyDeadline?.cancel(); readyDeadline = nil
        if ready { send("RESTORE") }
        else {
            // EOF is an independent restore signal, including before READY.
            try? input?.close(); input = nil
        }
    }

    private func send(_ command: String) {
        guard let input else { return }
        if command != "CHECK" { DockFocusDiagnostics.shared.record("guardianSend_" + command) }
        let bytes = Array((command + "\n").utf8)
        let count = bytes.withUnsafeBytes { Darwin.write(input.fileDescriptor, $0.baseAddress!, $0.count) }
        if count != bytes.count {
            if command == "CHECK", count < 0, errno == EAGAIN { return }
            blocked = true; closing = true
            statusText = "The Dock recovery connection closed. Previous Dock settings will be restored by the helper."
            try? input.close(); self.input = nil
        }
    }

    private func protocolFailure() {
        blocked = true
        statusText = "The Dock recovery response was invalid. Choose Restore macOS Dock to verify restoration."
        requestRestore()
    }

    private func terminated(status: Int32, generation attempt: UInt64) {
        guard generation == attempt else { return }
        DockFocusDiagnostics.shared.record("guardianExited", state: status == 0)
        let expected = closing && status == 0
        cleanup()
        if !expected {
            blocked = true
            statusText = status == 0
                ? "macOS Dock was restored. Turn this option off and on if you want to hide it again."
                : "Dock recovery stopped unexpectedly. Choose Restore macOS Dock to recover your saved settings."
        }
        if wantsHide { reconcile() }
    }

    private func cleanup() {
        readyDeadline?.cancel(); readyDeadline = nil
        output?.readabilityHandler = nil
        try? input?.close(); try? output?.close()
        input = nil; output = nil; process?.terminationHandler = nil; process = nil; childStart = nil
        ready = false; applying = false; applied = false; closing = false
    }

    private func verifiedHelper(_ url: URL) -> Bool {
        var code: SecStaticCode?; var requirement: SecRequirement?
        let text = #"anchor apple generic and identifier "com.graden-grech.Notchscape.DockWidget" and certificate leaf[subject.OU] = "6H86CTRJCP""#
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), requirement) == errSecSuccess
    }
}
