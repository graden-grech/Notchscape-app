import Foundation

/// Synthetic trace only. No credentials, AX calls, keyboard events or clipboard.
private final class ScreenUnlockSyntheticTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func append(_ entry: String) { lock.lock(); defer { lock.unlock() }; entries.append(entry) }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return entries }
}

@main struct ScreenUnlockPolicyTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        func rejects(_ expected: ScreenUnlockFailure, _ operation: () throws -> Void) {
            do { try operation(); preconditionFailure("Expected \(expected)") }
            catch let error as ScreenUnlockFailure { check(error == expected, "Expected \(expected), got \(error)") }
            catch { preconditionFailure("Unexpected error: \(error)") }
        }
        let identity = UUID(), token = UUID(), challenge = UUID()
        let authorization = FaceUnlockAuthorizationSession(mode: .screenUnlockConvenience,
            lifetime: 100, now: 90, token: token)!
        func session(uid: UInt32 = 501, effective: UInt32 = 501, console: UInt32? = 501,
                     security: UInt32? = 1001, onConsole: Bool? = true, login: Bool? = true,
                     locked: Bool? = true, graphical: Bool = true, remote: Bool = false,
                     root: Bool = false, awake: Bool = true) -> ScreenUnlockSessionSnapshot {
            ScreenUnlockSessionSnapshot(userID: uid, effectiveUserID: effective, consoleUserID: console,
                securitySessionID: security, onConsole: onConsole, loginComplete: login,
                screenLocked: locked, graphicalSession: graphical, remoteSession: remote,
                rootSession: root, displayAwake: awake)
        }
        func target(pid: Int32 = 321, seconds: UInt64 = 123456, micros: UInt64 = 123,
                    trusted: Bool = true, apple: Bool = true, focused: Bool = true,
                    enabled: Bool = true, settable: Bool = true, confirm: Bool = true,
                    post: Bool = true) -> ScreenUnlockTargetSnapshot {
            ScreenUnlockTargetSnapshot(process: ScreenUnlockProcessIdentity(processID: pid,
                startSeconds: seconds, startMicroseconds: micros), accessibilityTrusted: trusted,
                appleLoginwindow: apple, focusedSecureField: focused, enabled: enabled,
                valueSettable: settable, confirmAction: confirm, targetedEventAccess: post)
        }
        func proof(token selectedToken: UUID? = nil, generation: UInt64 = 1,
                   match: FaceMatchOutcome? = nil, satisfied: Bool = true,
                   timestamp: Double = 100.2, count: Int = 6) -> ScreenUnlockRecognitionProof {
            ScreenUnlockRecognitionProof(authorizationToken: selectedToken ?? token,
                lockGeneration: generation, match: match ?? .matched(identityID: identity, cosineSimilarity: 0.95),
                challengeID: challenge, challengeSatisfied: satisfied,
                frameTimestamp: timestamp, consecutiveMatchCount: count)
        }
        func policy() -> ScreenUnlockPolicy {
            var value = ScreenUnlockPolicy()
            value.setEnabled(true)
            value.sessionLocked(generation: 1, now: 100)
            return value
        }
        func reserve(_ value: inout ScreenUnlockPolicy,
                     auth: FaceUnlockAuthorizationSession? = nil,
                     evidence: ScreenUnlockRecognitionProof? = nil,
                     desktop: ScreenUnlockSessionSnapshot? = nil,
                     field: ScreenUnlockTargetSnapshot? = nil,
                     now: Double = 100.3) throws -> ScreenUnlockAttempt {
            try value.reserve(authorization: auth ?? authorization, proof: evidence ?? proof(),
                session: desktop ?? session(), target: field ?? target(), now: now)
        }

        var disabled = ScreenUnlockPolicy()
        disabled.sessionLocked(generation: 1, now: 100)
        rejects(.disabled) { _ = try reserve(&disabled) }
        var noLock = ScreenUnlockPolicy(); noLock.setEnabled(true)
        rejects(.noLockGeneration) { _ = try reserve(&noLock) }
        for generation in [UInt64(0), 2, UInt64.max] {
            var value = policy()
            rejects(.noLockGeneration) { _ = try reserve(&value, evidence: proof(generation: generation)) }
        }

        let invalidSessions = [
            session(uid: 0, effective: 0, console: 0), session(effective: 0), session(console: nil),
            session(console: 502), session(security: nil), session(security: 0), session(security: UInt32.max),
            session(security: UInt32.max - 1), session(onConsole: nil), session(onConsole: false),
            session(login: nil), session(login: false), session(locked: nil), session(locked: false),
            session(graphical: false), session(remote: true), session(root: true), session(awake: false)
        ]
        for desktop in invalidSessions {
            var value = policy()
            rejects(.sessionUnverified) { _ = try reserve(&value, desktop: desktop) }
            check((try? reserve(&value)) != nil, "A preflight refusal has not submitted or consumed a valid attempt")
        }
        let invalidTargets: [(ScreenUnlockTargetSnapshot, ScreenUnlockFailure)] = [
            (target(trusted: false), .accessibilityUnavailable), (target(apple: false), .loginwindowUnverified),
            (target(pid: 0), .loginwindowUnverified), (target(pid: -1), .loginwindowUnverified),
            (target(seconds: 0), .loginwindowUnverified), (target(micros: 1_000_000), .loginwindowUnverified),
            (target(focused: false), .secureFieldUnavailable), (target(enabled: false), .secureFieldUnavailable),
            (target(settable: false), .submissionUnavailable),
            (target(settable: false, confirm: false), .submissionUnavailable),
            (target(settable: false, post: false), .submissionUnavailable),
            (target(confirm: false, post: false), .submissionUnavailable)
        ]
        for (field, error) in invalidTargets {
            var value = policy()
            rejects(error) { _ = try reserve(&value, field: field) }
        }

        var invalidated = authorization; invalidated.handle(.stop, now: 100)
        let invalidAuthorizations = [
            FaceUnlockAuthorizationSession(mode: .unlockedOnly, lifetime: 100, now: 90, token: token)!,
            FaceUnlockAuthorizationSession(mode: .screenUnlockConvenience, lifetime: 1, now: 90, token: token)!,
            FaceUnlockAuthorizationSession(mode: .screenUnlockConvenience, lifetime: 100, now: 101, token: token)!,
            FaceUnlockAuthorizationSession(mode: .screenUnlockConvenience, lifetime: 100, now: 90)!, invalidated
        ]
        for auth in invalidAuthorizations {
            var value = policy()
            rejects(.authorizationInvalid) { _ = try reserve(&value, auth: auth) }
        }
        var wrongToken = policy()
        rejects(.authorizationInvalid) { _ = try reserve(&wrongToken, evidence: proof(token: UUID())) }
        let invalidProofs = [proof(satisfied: false), proof(count: 0), proof(count: 2),
            proof(timestamp: 99), proof(timestamp: 100.4), proof(timestamp: .nan), proof(timestamp: .infinity),
            proof(match: .noMatch), proof(match: .ambiguous), proof(match: .noCompatibleEnrollment),
            proof(match: .matched(identityID: identity, cosineSimilarity: .nan)),
            proof(match: .matched(identityID: identity, cosineSimilarity: -0.1)),
            proof(match: .matched(identityID: identity, cosineSimilarity: 1.01))]
        for evidence in invalidProofs {
            var value = policy()
            rejects(.recognitionInvalid) { _ = try reserve(&value, evidence: evidence) }
        }
        var stale = policy()
        rejects(.recognitionInvalid) { _ = try reserve(&stale, now: 102.3) }
        for time in [99.0, Double.nan, .infinity] {
            var value = policy()
            rejects(.clockInvalid) { _ = try reserve(&value, now: time) }
        }

        for (field, expectedRoute) in [
            (target(post: false), ScreenUnlockRoute.accessibilitySetAndConfirm),
            (target(confirm: false), .accessibilitySetAndTargetedReturn)
        ] {
            var value = policy()
            let attempt = try reserve(&value, field: field)
            check(attempt.route == expectedRoute, "Available direct AX route takes precedence")
            check(attempt.authorizationToken == token && attempt.lockGeneration == 1,
                  "Reservation binds authorization and lock generation")
            check(attempt.identityID == identity && attempt.challengeID == challenge,
                  "Reservation binds matched identity and challenge")
            check(abs(attempt.deadline - 101.3) < 1e-9, "Reservation has a short immutable deadline")
            rejects(.alreadyAttempted) { _ = try reserve(&value, field: field) }
            value.sessionLocked(generation: 1, now: 100.4)
            try value.beginSubmission(attempt, session: session(), target: field, now: 100.5)
            try value.validateSubmission(attempt, session: session(), target: field, now: 100.6)
            checks += 2
            rejects(.reservationInvalid) { try value.beginSubmission(attempt, session: session(), target: field, now: 100.7) }
            value.cancel(attempt)
            rejects(.reservationInvalid) { try value.validateSubmission(attempt, session: session(), target: field, now: 100.8) }
            rejects(.alreadyAttempted) { _ = try reserve(&value, field: field) }
        }

        // A race at any output boundary cancels rather than redirecting output.
        let changedTargets: [(ScreenUnlockTargetSnapshot, ScreenUnlockFailure)] = [
            (target(pid: 322), .targetChanged), (target(seconds: 123457), .targetChanged),
            (target(micros: 124), .targetChanged), (target(settable: false), .submissionUnavailable),
            (target(confirm: false), .targetChanged), (target(post: false), .targetChanged),
            (target(apple: false), .loginwindowUnverified), (target(focused: false), .secureFieldUnavailable)]
        for (changed, error) in changedTargets {
            var value = policy(); let attempt = try reserve(&value)
            try value.beginSubmission(attempt, session: session(), target: target(), now: 100.4)
            rejects(error) { try value.validateSubmission(attempt, session: session(), target: changed, now: 100.5) }
            rejects(.reservationInvalid) { try value.validateSubmission(attempt, session: session(), target: target(), now: 100.6) }
        }
        for desktop in [session(security: 1002), session(locked: false), session(locked: nil), session(console: 502)] {
            var value = policy(); let attempt = try reserve(&value)
            try value.beginSubmission(attempt, session: session(), target: target(), now: 100.4)
            let error: ScreenUnlockFailure = desktop.securitySessionID == 1002 ? .targetChanged : .sessionUnverified
            rejects(error) { try value.validateSubmission(attempt, session: desktop, target: target(), now: 100.5) }
            rejects(.reservationInvalid) { try value.validateSubmission(attempt, session: session(), target: target(), now: 100.6) }
            if error == .sessionUnverified {
                value.sessionLocked(generation: 1, now: 100.7)
                rejects(.noLockGeneration) { _ = try reserve(&value, now: 100.8) }
            }
        }
        for time in [101.3, 102.0, Double.infinity] {
            var value = policy(); let attempt = try reserve(&value)
            let error: ScreenUnlockFailure = time.isFinite ? .deadlineExpired : .clockInvalid
            rejects(error) { try value.beginSubmission(attempt, session: session(), target: target(), now: time) }
            rejects(.reservationInvalid) { try value.beginSubmission(attempt, session: session(), target: target(), now: 100.5) }
        }
        var rollback = policy(); let rollbackAttempt = try reserve(&rollback)
        rejects(.clockInvalid) { try rollback.beginSubmission(rollbackAttempt, session: session(), target: target(), now: 100.2) }

        for cancellation in 0..<4 {
            var value = policy(); let attempt = try reserve(&value)
            switch cancellation {
            case 0: value.cancel(attempt)
            case 1: value.invalidate()
            case 2: value.setEnabled(false); value.setEnabled(true)
            default: value.sessionUnlocked(); value.sessionLocked(generation: 1, now: 100.4)
            }
            rejects(.reservationInvalid) { try value.beginSubmission(attempt, session: session(), target: target(), now: 100.5) }
            let error: ScreenUnlockFailure = cancellation == 3 ? .noLockGeneration : .alreadyAttempted
            rejects(error) { _ = try reserve(&value) }
            value.sessionUnlocked(); value.sessionLocked(generation: 2, now: 101)
            let fresh = try reserve(&value, evidence: proof(generation: 2, timestamp: 101.1), now: 101.2)
            check(fresh.lockGeneration == 2, "Only a later real lock permits another attempt")
            value.cancel(attempt)
            try value.beginSubmission(fresh, session: session(), target: target(), now: 101.3)
            checks += 1
        }
        var nearExpiry = policy()
        let short = FaceUnlockAuthorizationSession(mode: .screenUnlockConvenience, lifetime: 10.5, now: 90, token: token)!
        let shortAttempt = try reserve(&nearExpiry, auth: short)
        check(shortAttempt.deadline == 100.5, "Vault expiry shortens action deadline")
        rejects(.deadlineExpired) { try nearExpiry.beginSubmission(shortAttempt, session: session(), target: target(), now: 100.5) }
        var ageBound = policy()
        let bounded = try reserve(&ageBound, now: 102.1)
        check(abs(bounded.deadline - 102.2) < 1e-9, "Evidence expiry also shortens action deadline")

        // Explicit app-lifetime authorization does not make an individual
        // recognition/reservation indefinite or survive a native-unlock race.
        let automatic = FaceUnlockAuthorizationSession.automaticWhileRunning(now: 90, token: token)!
        var automaticPolicy = policy()
        let automaticAttempt = try reserve(&automaticPolicy, auth: automatic)
        check(automaticAttempt.deadline.isFinite && abs(automaticAttempt.deadline - 101.3) < 1e-9,
              "Automatic authorization still has a finite one-second output reservation")
        try automaticPolicy.beginSubmission(automaticAttempt, session: session(), target: target(), now: 100.4)
        automaticPolicy.sessionUnlocked()
        rejects(.reservationInvalid) {
            try automaticPolicy.validateSubmission(automaticAttempt, session: session(), target: target(), now: 100.5)
        }
        var stillAutomatic = automatic
        stillAutomatic.handle(.screenUnlocked, now: 100.5)
        automaticPolicy.sessionLocked(generation: 2, now: 101)
        let nextAutomatic = try reserve(&automaticPolicy, auth: stillAutomatic,
            evidence: proof(generation: 2, timestamp: 101.1), now: 101.2)
        check(nextAutomatic.lockGeneration == 2 && nextAutomatic.authorizationToken == automatic.token,
              "A new real lock may reuse explicit app-lifetime authorization with fresh face evidence")
        var longRunning = policy()
        let later = try reserve(&longRunning, auth: automatic,
            evidence: proof(timestamp: 86_400.1), now: 86_400.2)
        check(later.deadline.isFinite && abs(later.deadline - 86_401.2) < 1e-9,
              "Long-running authorization never lengthens the output window")
        for event in [FaceUnlockInvalidationEvent.systemSleep, .stop, .logout, .sessionInactive, .privacyChanged, .appTerminated] {
            var stopped = automatic; stopped.handle(event, now: 100)
            var value = policy()
            rejects(.authorizationInvalid) { _ = try reserve(&value, auth: stopped) }
        }

        // Without a writable AX secure value, event-post permission must never
        // supply an alternative secret-text path. Confirmation access is not a
        // substitute for being able to address the password element itself.
        for confirm in [false, true] {
            for post in [false, true] {
                let field = target(settable: false, confirm: confirm, post: post)
                check(field.route == nil, "A read-only secure field has no keyboard-text fallback")
                var value = policy()
                rejects(.submissionUnavailable) { _ = try reserve(&value, field: field) }
            }
        }

        let preflightGate = ScreenUnlockCancellationGate()
        rejects(.noLockGeneration) { _ = try preflightGate.captureEpoch() }
        check(!preflightGate.sessionLocked(generation: 0), "A zero generation never arms output")
        check(preflightGate.sessionLocked(generation: 1), "A fresh lock arms an epoch")
        let preflightEpoch = try preflightGate.captureEpoch()
        preflightGate.revokeAll() // Native unlock while AX preflight is waiting.
        rejects(.reservationInvalid) {
            _ = try preflightGate.bind(attemptID: UUID(), generation: 1, epoch: preflightEpoch)
        }
        check(!preflightGate.sessionLocked(generation: 1), "Replayed lock notifications cannot rearm after native unlock")
        rejects(.noLockGeneration) { _ = try preflightGate.captureEpoch() }

        // Inject the native-unlock event at every gap from reservation through
        // confirmation. The values below are trace labels, never OS output.
        for boundary in 0..<4 {
            let gate = ScreenUnlockCancellationGate()
            check(gate.sessionLocked(generation: 1), "Fresh test generation")
            let epoch = try gate.captureEpoch()
            var value = policy()
            let attempt = try reserve(&value)
            let lease = try gate.bind(attemptID: attempt.id, generation: 1, epoch: epoch)
            var trace: [String] = []
            if boundary >= 1 {
                try value.beginSubmission(attempt, session: session(), target: target(), now: 100.4)
            }
            if boundary >= 2 {
                try gate.validate(lease)
                try value.validateSubmission(attempt, session: session(), target: target(), now: 100.5)
            }
            if boundary == 3 { trace.append("secure-value-only") }
            gate.revokeAll()
            // The action fence is already revoked even if stateLock prevents
            // the policy notification from being processed until AX returns.
            rejects(.reservationInvalid) { try gate.validate(lease) }
            value.sessionUnlocked()
            if boundary == 0 {
                rejects(.reservationInvalid) { try value.beginSubmission(attempt, session: session(), target: target(), now: 100.6) }
            } else {
                rejects(.reservationInvalid) { try value.validateSubmission(attempt, session: session(), target: target(), now: 100.6) }
            }
            if (try? gate.validate(lease)) != nil { trace.append("confirm-or-return") }
            check(trace == (boundary == 3 ? ["secure-value-only"] : []),
                  "Native unlock prevents queued value or later confirmation at every boundary")
        }

        // A deterministic two-thread handoff reproduces the important race:
        // validation began with a valid lease, then blocks in mocked AX work.
        // Revocation must complete without waiting for that work to finish.
        let gate = ScreenUnlockCancellationGate()
        check(gate.sessionLocked(generation: 1), "Arm blocked-validation fixture")
        let blockedEpoch = try gate.captureEpoch()
        let blockedID = UUID()
        let blockedLease = try gate.bind(attemptID: blockedID, generation: 1, epoch: blockedEpoch)
        let entered = DispatchSemaphore(value: 0), resume = DispatchSemaphore(value: 0)
        let completed = DispatchSemaphore(value: 0), trace = ScreenUnlockSyntheticTrace()
        let outputStateLock = NSLock()
        DispatchQueue.global(qos: .userInitiated).async {
            outputStateLock.lock()
            defer { outputStateLock.unlock() }
            defer { completed.signal() }
            do {
                try gate.validate(blockedLease)
                trace.append("validation-began")
                entered.signal()
                guard resume.wait(timeout: .now() + 2) == .success else { trace.append("timeout"); return }
                try gate.validate(blockedLease)
                trace.append("would-set-secure-value")
            } catch { trace.append("cancelled") }
        }
        check(entered.wait(timeout: .now() + 2) == .success, "Mock AX validation is blocked")
        gate.revokeAll()
        resume.signal()
        check(completed.wait(timeout: .now() + 2) == .success, "Revoked validation completes promptly")
        check(trace.values == ["validation-began", "cancelled"], "Unlock during blocked validation produces no output")

        check(gate.sessionLocked(generation: 2), "Only a newer real lock rearms the fence")
        let nextEpoch = try gate.captureEpoch(), nextID = UUID()
        let nextLease = try gate.bind(attemptID: nextID, generation: 2, epoch: nextEpoch)
        gate.cancel(attemptID: blockedID)
        try gate.validate(nextLease); checks += 1
        check(!gate.sessionLocked(generation: 1), "Stale generation cannot replace a fresh lease")
        check(!gate.sessionLocked(generation: 2), "Duplicate notification preserves the current lease")
        try gate.validate(nextLease); checks += 1
        rejects(.reservationInvalid) { _ = try gate.bind(attemptID: UUID(), generation: 1, epoch: blockedEpoch) }
        gate.cancel(attemptID: nextID)
        rejects(.reservationInvalid) { try gate.validate(nextLease) }

        let exhausted = ScreenUnlockCancellationGate(initialSerial: UInt64.max - 1)
        check(exhausted.sessionLocked(generation: 1), "Last finite epoch is representable")
        let lastEpoch = try exhausted.captureEpoch()
        let lastLease = try exhausted.bind(attemptID: UUID(), generation: 1, epoch: lastEpoch)
        exhausted.revokeAll()
        check(!exhausted.hasActiveLock && !exhausted.sessionLocked(generation: 2), "Epoch exhaustion denies rather than wrapping")
        rejects(.reservationInvalid) { try exhausted.validate(lastLease) }
        rejects(.noLockGeneration) { _ = try exhausted.captureEpoch() }
        print("PASS \(checks) screen-unlock policy behavior checks (synthetic, no OS input)")
    }
}
