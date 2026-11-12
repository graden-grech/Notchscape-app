import Foundation
import ApplicationServices
import Security
import Darwin

/// Explicitly enabled, process-targeted convenience adapter. Initializing or
/// enabling it performs no input. No Keychain, camera, prompts or global events.
/// Call only from the vault's synchronous recognized-face credential closure.
final class ScreenUnlockAction: @unchecked Sendable {
    private let now: @Sendable () -> Double
    private let stateLock = NSLock()
    private let cancellation = ScreenUnlockCancellationGate()
    private var policy = ScreenUnlockPolicy()
    private var retainedTarget: Target?
    private var retainedAttemptID: UUID?
    private var retainedLease: ScreenUnlockCancellationGate.Lease?

    private struct Target {
        let field: AXUIElement
        let application: AXUIElement
        let window: AXUIElement
        let snapshot: ScreenUnlockTargetSnapshot
    }

    init(now: @escaping @Sendable () -> Double) { self.now = now }

    func setEnabled(_ enabled: Bool) {
        if !enabled { cancellation.revokeAll() }
        locked { policy.setEnabled(enabled); if !enabled { clearRetained() } }
    }

    func sessionLocked(generation: UInt64) {
        let timestamp = now()
        guard generation > 0, timestamp.isFinite, timestamp >= 0 else { invalidate(); return }
        guard cancellation.sessionLocked(generation: generation) else { return }
        locked {
            policy.sessionLocked(generation: generation, now: timestamp)
            clearRetained()
        }
    }

    func sessionUnlocked() {
        // Revoke before touching the state lock. An AX call may currently be
        // waiting on loginwindow, so a native/Watch unlock must not wait on it.
        cancellation.revokeAll()
        clearRevokedStateIfIdle()
    }

    func invalidate() {
        cancellation.revokeAll()
        clearRevokedStateIfIdle()
    }

    func cancel(_ attempt: ScreenUnlockAttempt) {
        cancellation.cancel(attemptID: attempt.id)
        locked {
            policy.cancel(attempt)
            if retainedAttemptID == attempt.id { clearRetained() }
        }
    }

    /// No credentials are retrieved here. OS readiness must be proven before a
    /// generation is consumed. Never cache this reservation beyond its deadline.
    func reserve(authorization: FaceUnlockAuthorizationSession,
                 proof: ScreenUnlockRecognitionProof) throws -> ScreenUnlockAttempt {
        try locked {
            guard policy.isEnabled else { throw ScreenUnlockFailure.disabled }
            let epoch = try cancellation.captureEpoch()
            _ = try verifiedSession()
            let target = try Self.focusedTarget()
            let session = try verifiedSession()
            let attempt = try policy.reserve(authorization: authorization, proof: proof,
                session: session, target: target.snapshot, now: now())
            let lease: ScreenUnlockCancellationGate.Lease
            do { lease = try cancellation.bind(attemptID: attempt.id, generation: attempt.lockGeneration, epoch: epoch) }
            catch { policy.cancel(attempt); throw error }
            retainedTarget = target
            retainedAttemptID = attempt.id
            retainedLease = lease
            return attempt
        }
    }

    /// Consumes the reservation before processing the secret. A refusal or
    /// partial submission is never retried within the same lock generation.
    /// The password is delivered only as an AX value for the verified secure
    /// element. It is never placed on a keyboard event or clipboard. The data
    /// and CFString are not retained on this object or logged.
    @discardableResult
    func submit(_ credential: Data, for attempt: ScreenUnlockAttempt) throws -> ScreenUnlockSubmission {
        defer { cancel(attempt) }
        let (target, lease): (Target, ScreenUnlockCancellationGate.Lease) = try locked {
            guard retainedAttemptID == attempt.id, let retainedTarget, let retainedLease
            else { throw ScreenUnlockFailure.reservationInvalid }
            try cancellation.validate(retainedLease)
            _ = try verifiedSession()
            let observed = try Self.focusedTarget()
            try Self.requireSameElements(retainedTarget, observed)
            let session = try verifiedSession()
            try policy.beginSubmission(attempt, session: session,
                                       target: observed.snapshot, now: now())
            try cancellation.validate(retainedLease)
            return (retainedTarget, retainedLease)
        }
        guard !credential.isEmpty, credential.count <= 4096 else { throw ScreenUnlockFailure.credentialInvalid }
        // Strict UTF-8 preserves the complete credential. Control characters are
        // refused instead of being interpreted as Return/Tab/shortcuts.
        guard let secret = credential.withUnsafeBytes({ bytes -> CFString? in
            CFStringCreateWithBytes(kCFAllocatorDefault, bytes.bindMemory(to: UInt8.self).baseAddress,
                bytes.count, CFStringBuiltInEncodings.UTF8.rawValue, false)
        }) else { throw ScreenUnlockFailure.credentialInvalid }
        let count = CFStringGetLength(secret)
        guard (1...1024).contains(count) else { throw ScreenUnlockFailure.credentialInvalid }
        var units = [UniChar](repeating: 0, count: count)
        defer { _ = units.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        CFStringGetCharacters(secret, CFRange(location: 0, length: count), &units)
        guard !units.contains(where: { $0 < 0x20 || (0x7f...0x9f).contains($0) || $0 == 0x2028 || $0 == 0x2029 })
        else { throw ScreenUnlockFailure.credentialInvalid }

        try output(attempt, target: target, lease: lease) {
            guard AXUIElementSetAttributeValue(target.field, kAXValueAttribute as CFString, secret) == .success
            else { throw ScreenUnlockFailure.outputFailed }
        }

        switch attempt.route {
        case .accessibilitySetAndConfirm:
            try output(attempt, target: target, lease: lease) {
                guard AXUIElementPerformAction(target.field, kAXConfirmAction as CFString) == .success
                else { throw ScreenUnlockFailure.outputFailed }
            }
        case .accessibilitySetAndTargetedReturn:
            try postReturn(attempt: attempt, target: target, lease: lease)
        }
        // CGEventPostToPid is void; AX success only means the request was
        // accepted. Root must observe a genuine system unlock independently.
        return ScreenUnlockSubmission(lockGeneration: attempt.lockGeneration, route: attempt.route)
    }

    /// Only a non-secret Return may use process-targeted events. No arbitrary
    /// key/flags/text argument exists that could become a credential fallback.
    private func postReturn(attempt: ScreenUnlockAttempt, target: Target,
                            lease: ScreenUnlockCancellationGate.Lease) throws {
        let source = try Self.eventSource()
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
        else { throw ScreenUnlockFailure.outputFailed }
        down.flags = []; up.flags = []
        try output(attempt, target: target, lease: lease) { down.postToPid(target.snapshot.process.processID) }
        try output(attempt, target: target, lease: lease) { up.postToPid(target.snapshot.process.processID) }
    }

    private static func eventSource() throws -> CGEventSource {
        guard let source = CGEventSource(stateID: .privateState) else { throw ScreenUnlockFailure.outputFailed }
        return source
    }

    private func output(_ attempt: ScreenUnlockAttempt, target: Target,
                        lease: ScreenUnlockCancellationGate.Lease, operation: () throws -> Void) throws {
        try locked {
            do {
                try cancellation.validate(lease)
                // Every individual output rechecks the actual OS session, exact
                // AX field/window/app, PID birth identity, signature and access.
                _ = try verifiedSession()
                let observed = try Self.focusedTarget()
                try Self.requireSameElements(target, observed)
                // Read lock/session state again after AX IPC, directly before
                // permitting output. A preflight locked snapshot may be stale.
                let session = try verifiedSession()
                try policy.validateSubmission(attempt, session: session, target: observed.snapshot, now: now())
                // A native unlock can revoke while the preceding AX checks
                // wait, independently of stateLock. Never resume their output.
                try cancellation.validate(lease)
                try operation()
                // An already dispatched AX request cannot be retracted. Its
                // exact loginwindow element remains the only secret recipient;
                // cancellation here prevents any later confirmation/Return.
                try cancellation.validate(lease)
            } catch {
                policy.cancel(attempt)
                cancellation.cancel(attemptID: attempt.id)
                if retainedAttemptID == attempt.id { clearRetained() }
                throw error
            }
        }
    }

    private func locked<T>(_ operation: () throws -> T) rethrows -> T {
        stateLock.lock()
        reconcileRevocation()
        defer { reconcileRevocation(); stateLock.unlock() }
        return try operation()
    }

    private func clearRevokedStateIfIdle() {
        guard stateLock.try() else { return }
        defer { stateLock.unlock() }
        reconcileRevocation()
    }

    /// Caller holds stateLock. Busy validation reconciles when it returns, so
    /// an unlock notification never blocks on another process's AX response.
    private func reconcileRevocation() {
        guard !cancellation.hasActiveLock else { return }
        policy.sessionUnlocked()
        clearRetained()
    }

    private func clearRetained() {
        retainedTarget = nil; retainedAttemptID = nil; retainedLease = nil
    }

    private func verifiedSession() throws -> ScreenUnlockSessionSnapshot {
        do { return try Self.currentSession() }
        catch {
            cancellation.revokeAll()
            policy.sessionUnlocked()
            clearRetained()
            throw error
        }
    }

    private static func currentSession() throws -> ScreenUnlockSessionSnapshot {
        guard let dictionary = CGSessionCopyCurrentDictionary() as NSDictionary? else {
            throw ScreenUnlockFailure.sessionUnverified
        }
        var securityID: SecuritySessionId = 0
        var attributes: SessionAttributeBits = []
        guard SessionGetInfo(callerSecuritySession, &securityID, &attributes) == errSessionSuccess else {
            throw ScreenUnlockFailure.sessionUnverified
        }
        let result = ScreenUnlockSessionSnapshot(userID: getuid(), effectiveUserID: geteuid(),
            consoleUserID: unsigned32(dictionary[kCGSessionUserIDKey as String]),
            securitySessionID: securityID,
            onConsole: boolean(dictionary[kCGSessionOnConsoleKey as String]),
            loginComplete: boolean(dictionary[kCGSessionLoginDoneKey as String]),
            // Public dictionary API, undocumented key: missing/non-Boolean is
            // UNKNOWN and refuses output. This is not a private API invocation.
            screenLocked: boolean(dictionary["CGSSessionScreenIsLocked"]),
            graphicalSession: attributes.contains(.sessionHasGraphicAccess),
            remoteSession: attributes.contains(.sessionIsRemote),
            rootSession: attributes.contains(.sessionIsRoot),
            displayAwake: CGDisplayIsAsleep(CGMainDisplayID()) == 0)
        try ScreenUnlockPolicy.validateSession(result)
        return result
    }

    private static func focusedTarget() throws -> Target {
        guard AXIsProcessTrusted() else { throw ScreenUnlockFailure.accessibilityUnavailable }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        let application = try element(system, kAXFocusedApplicationAttribute)
        let field = try element(system, kAXFocusedUIElementAttribute)
        AXUIElementSetMessagingTimeout(application, 0.2)
        AXUIElementSetMessagingTimeout(field, 0.2)
        var appPID: pid_t = 0, fieldPID: pid_t = 0
        guard AXUIElementGetPid(application, &appPID) == .success,
              AXUIElementGetPid(field, &fieldPID) == .success, appPID > 0, appPID == fieldPID
        else { throw ScreenUnlockFailure.loginwindowUnverified }
        let birth = try verifiedProcess(appPID)
        let appField = try element(application, kAXFocusedUIElementAttribute)
        let window = try element(field, kAXWindowAttribute)
        let focusedWindow = try element(application, kAXFocusedWindowAttribute)
        var windowPID: pid_t = 0
        guard CFEqual(field, appField), CFEqual(window, focusedWindow),
              AXUIElementGetPid(window, &windowPID) == .success, windowPID == appPID,
              string(attribute(field, kAXRoleAttribute)) == kAXTextFieldRole,
              string(attribute(field, kAXSubroleAttribute)) == kAXSecureTextFieldSubrole,
              boolean(attribute(field, kAXFocusedAttribute)) == true,
              boolean(attribute(field, kAXEnabledAttribute)) == true
        else { throw ScreenUnlockFailure.secureFieldUnavailable }
        var settable = DarwinBoolean(false)
        let canSet = AXUIElementIsAttributeSettable(field, kAXValueAttribute as CFString, &settable) == .success
            && settable.boolValue
        var actions: CFArray?
        let canConfirm = AXUIElementCopyActionNames(field, &actions) == .success
            && (actions as? [String])?.contains(kAXConfirmAction) == true
        let snapshot = ScreenUnlockTargetSnapshot(process: birth, accessibilityTrusted: true,
            appleLoginwindow: true, focusedSecureField: true, enabled: true,
            valueSettable: canSet, confirmAction: canConfirm, targetedEventAccess: CGPreflightPostEventAccess())
        try ScreenUnlockPolicy.validateTarget(snapshot)
        return Target(field: field, application: application, window: window, snapshot: snapshot)
    }

    private static func requireSameElements(_ original: Target, _ current: Target) throws {
        guard CFEqual(original.field, current.field), CFEqual(original.application, current.application),
              CFEqual(original.window, current.window), original.snapshot.process == current.snapshot.process
        else { throw ScreenUnlockFailure.targetChanged }
    }

    private static func verifiedProcess(_ pid: pid_t) throws -> ScreenUnlockProcessIdentity {
        let before = try processIdentity(pid)
        var code: SecCode?
        var requirement: SecRequirement?
        let guest = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, guest, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("anchor apple and identifier \"com.apple.loginwindow\"" as CFString,
                  [], &requirement) == errSecSuccess, let requirement,
              SecCodeCheckValidity(code, [], requirement) == errSecSuccess,
              try processIdentity(pid) == before
        else { throw ScreenUnlockFailure.loginwindowUnverified }
        return before
    }

    private static func processIdentity(_ pid: pid_t) throws -> ScreenUnlockProcessIdentity {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_pid == UInt32(pid), info.pbi_start_tvsec > 0
        else { throw ScreenUnlockFailure.loginwindowUnverified }
        return ScreenUnlockProcessIdentity(processID: pid, startSeconds: info.pbi_start_tvsec,
                                          startMicroseconds: info.pbi_start_tvusec)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func element(_ parent: AXUIElement, _ name: String) throws -> AXUIElement {
        guard let value = attribute(parent, name), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw ScreenUnlockFailure.secureFieldUnavailable
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func string(_ value: CFTypeRef?) -> String? {
        guard let value, CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return value as? String
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let value, CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue(unsafeBitCast(value as CFTypeRef, to: CFBoolean.self))
    }

    private static func unsigned32(_ value: Any?) -> UInt32? {
        guard let value, CFGetTypeID(value as CFTypeRef) == CFNumberGetTypeID(),
              let number = value as? NSNumber else { return nil }
        let integer = number.int64Value
        guard integer >= 0, integer <= Int64(UInt32.max), number.doubleValue == Double(integer) else { return nil }
        return UInt32(integer)
    }
}
