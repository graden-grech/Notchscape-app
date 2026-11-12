import Foundation

/// Trusted in-process evidence, not an OS biometric attestation. All times use
/// the vault's injected monotonic clock, including camera frame timestamps.
struct ScreenUnlockRecognitionProof: Equatable, Sendable {
    let authorizationToken: UUID
    let lockGeneration: UInt64
    let match: FaceMatchOutcome
    let challengeID: UUID
    let challengeSatisfied: Bool
    let frameTimestamp: Double
    let consecutiveMatchCount: Int
}

struct ScreenUnlockSessionSnapshot: Equatable, Sendable {
    let userID: UInt32
    let effectiveUserID: UInt32
    let consoleUserID: UInt32?
    let securitySessionID: UInt32?
    let onConsole: Bool?
    let loginComplete: Bool?
    let screenLocked: Bool?
    let graphicalSession: Bool
    let remoteSession: Bool
    let rootSession: Bool
    let displayAwake: Bool
}

struct ScreenUnlockProcessIdentity: Equatable, Sendable {
    let processID: Int32
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}

enum ScreenUnlockRoute: Equatable, Sendable {
    case accessibilitySetAndConfirm
    case accessibilitySetAndTargetedReturn
}

struct ScreenUnlockTargetSnapshot: Equatable, Sendable {
    let process: ScreenUnlockProcessIdentity
    let accessibilityTrusted: Bool
    let appleLoginwindow: Bool
    let focusedSecureField: Bool
    let enabled: Bool
    let valueSettable: Bool
    let confirmAction: Bool
    let targetedEventAccess: Bool

    var route: ScreenUnlockRoute? {
        // Process-targeted keyboard events do not bind secret text to this AX
        // element. A writable secure value is mandatory, even with event access.
        guard valueSettable else { return nil }
        if confirmAction { return .accessibilitySetAndConfirm }
        if targetedEventAccess { return .accessibilitySetAndTargetedReturn }
        return nil
    }
}

enum ScreenUnlockFailure: String, Error, LocalizedError, Sendable {
    case disabled, noLockGeneration, alreadyAttempted, authorizationInvalid
    case recognitionInvalid, clockInvalid, sessionUnverified, accessibilityUnavailable
    case loginwindowUnverified, secureFieldUnavailable, submissionUnavailable
    case reservationInvalid, deadlineExpired, targetChanged, credentialInvalid, outputFailed

    var errorDescription: String? {
        switch self {
        case .disabled: return "Screen-unlock convenience is disabled."
        case .noLockGeneration: return "A new system lock has not been observed."
        case .alreadyAttempted: return "An attempt was already reserved for this lock. Unlock manually to try again."
        case .authorizationInvalid: return "The temporary vault authorization is unavailable or expired."
        case .recognitionInvalid: return "A fresh completed challenge and continuous face match are required."
        case .clockInvalid: return "The monotonic timing evidence is invalid."
        case .sessionUnverified: return "The current user's locked console session could not be verified."
        case .accessibilityUnavailable: return "Accessibility access is unavailable."
        case .loginwindowUnverified: return "The focused process could not be verified as Apple's loginwindow."
        case .secureFieldUnavailable: return "The focused loginwindow secure password field is unavailable."
        case .submissionUnavailable: return "macOS can't safely accept a password here. Unlock your Mac normally."
        case .reservationInvalid: return "The reserved attempt is no longer valid."
        case .deadlineExpired: return "The attempt expired before submission."
        case .targetChanged: return "The verified session or password field changed."
        case .credentialInvalid: return "The stored credential is unsupported."
        case .outputFailed: return "The targeted submission could not be completed. Unlock manually."
        }
    }
}

/// Opaque, non-secret reservation. An exact copy must be presented for output.
struct ScreenUnlockAttempt: Equatable, Sendable {
    let id: UUID
    let authorizationToken: UUID
    let lockGeneration: UInt64
    let deadline: Double
    let identityID: UUID
    let challengeID: UUID
    let route: ScreenUnlockRoute
    fileprivate let authorization: FaceUnlockAuthorizationSession
    fileprivate let session: ScreenUnlockSessionSnapshot
    fileprivate let target: ScreenUnlockTargetSnapshot
    fileprivate let reservedAt: Double
}

struct ScreenUnlockSubmission: Equatable, Sendable {
    enum Status: Equatable, Sendable { case submittedUnverified }
    let status: Status = .submittedUnverified
    let lockGeneration: UInt64
    let route: ScreenUnlockRoute
}

/// A small independently locked revocation fence. Its lock never surrounds AX
/// IPC or event posting: an OS unlock can revoke a lease while validation waits.
/// It contains only attempt IDs/epochs, never credentials or AX objects.
final class ScreenUnlockCancellationGate: @unchecked Sendable {
    struct Epoch: Equatable, Sendable {
        fileprivate let serial: UInt64
        fileprivate let lockGeneration: UInt64
    }
    struct Lease: Equatable, Sendable {
        fileprivate let epoch: Epoch
        fileprivate let attemptID: UUID
    }

    private let lock = NSLock()
    private var serial: UInt64
    private var highestLockGeneration: UInt64 = 0
    private var lockGeneration: UInt64?
    private var activeAttemptID: UUID?
    private var exhausted = false

    init(initialSerial: UInt64 = 0) { serial = initialSerial }

    @discardableResult
    func sessionLocked(generation: UInt64) -> Bool {
        synchronized {
            guard !exhausted, generation > highestLockGeneration else { return false }
            highestLockGeneration = generation
            advance()
            guard !exhausted else { return false }
            lockGeneration = generation
            return true
        }
    }

    func revokeAll() {
        synchronized { advance(); lockGeneration = nil }
    }

    func captureEpoch() throws -> Epoch {
        try synchronized {
            guard !exhausted, let lockGeneration else { throw ScreenUnlockFailure.noLockGeneration }
            return Epoch(serial: serial, lockGeneration: lockGeneration)
        }
    }

    func bind(attemptID: UUID, generation: UInt64, epoch: Epoch) throws -> Lease {
        try synchronized {
            guard !exhausted, activeAttemptID == nil, epoch.serial == serial,
                  epoch.lockGeneration == generation, lockGeneration == generation
            else { throw ScreenUnlockFailure.reservationInvalid }
            activeAttemptID = attemptID
            return Lease(epoch: epoch, attemptID: attemptID)
        }
    }

    func validate(_ lease: Lease) throws {
        try synchronized {
            guard !exhausted, lease.epoch.serial == serial,
                  lockGeneration == lease.epoch.lockGeneration, activeAttemptID == lease.attemptID
            else { throw ScreenUnlockFailure.reservationInvalid }
        }
    }

    func cancel(attemptID: UUID) {
        synchronized {
            // A delayed cancellation from an older lock cannot revoke a newer
            // attempt that already owns this fence.
            guard activeAttemptID == attemptID else { return }
            advance()
        }
    }

    var hasActiveLock: Bool { synchronized { !exhausted && lockGeneration != nil } }

    private func advance() {
        activeAttemptID = nil
        guard serial < UInt64.max else { exhausted = true; lockGeneration = nil; return }
        serial += 1
    }

    private func synchronized<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try operation()
    }
}

/// No input, AX, camera, Keychain or preferences calls. A generation is consumed
/// at reservation, even if the vault or subsequent OS operation refuses it.
struct ScreenUnlockPolicy: Sendable {
    static let maximumFrameAge = 2.0
    static let maximumReservationLifetime = 1.0
    static let minimumConsecutiveMatches = 3
    private(set) var isEnabled = false
    private(set) var lockGeneration: UInt64?
    private var highestGeneration: UInt64 = 0
    private var lockedAt: Double?
    private var attemptedGeneration: UInt64?
    private var pending: ScreenUnlockAttempt?
    private var submitting: ScreenUnlockAttempt?

    mutating func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { invalidate() }
    }

    mutating func sessionLocked(generation: UInt64, now: Double) {
        guard generation > 0, now.isFinite, now >= 0 else { invalidate(); return }
        if lockGeneration == generation { return }
        // Replayed/stale lock notifications cannot reopen a consumed generation.
        guard generation > highestGeneration else { return }
        highestGeneration = generation
        lockGeneration = generation
        lockedAt = now
        invalidate()
    }

    mutating func sessionUnlocked() {
        lockGeneration = nil
        lockedAt = nil
        invalidate()
    }

    mutating func invalidate() { pending = nil; submitting = nil }

    mutating func cancel(_ attempt: ScreenUnlockAttempt) {
        if pending == attempt { pending = nil }
        if submitting == attempt { submitting = nil }
    }

    mutating func reserve(authorization: FaceUnlockAuthorizationSession,
                         proof: ScreenUnlockRecognitionProof,
                         session: ScreenUnlockSessionSnapshot,
                         target: ScreenUnlockTargetSnapshot,
                         now: Double) throws -> ScreenUnlockAttempt {
        guard isEnabled else { throw ScreenUnlockFailure.disabled }
        guard let generation = lockGeneration, let lockedAt,
              generation == proof.lockGeneration else { throw ScreenUnlockFailure.noLockGeneration }
        guard attemptedGeneration != generation else { throw ScreenUnlockFailure.alreadyAttempted }
        guard now.isFinite, now >= lockedAt else { throw ScreenUnlockFailure.clockInvalid }
        try Self.validateSession(session)
        try Self.validateTarget(target)
        guard authorization.permitsScreenUnlock,
              authorization.token == proof.authorizationToken,
              authorization.permitsRead(now: now, desktopIsActive: true, desktopIsUnlocked: false)
        else { throw ScreenUnlockFailure.authorizationInvalid }
        guard proof.challengeSatisfied, proof.consecutiveMatchCount >= Self.minimumConsecutiveMatches,
              proof.frameTimestamp.isFinite, proof.frameTimestamp >= lockedAt,
              proof.frameTimestamp >= authorization.issuedAt, proof.frameTimestamp <= now,
              now - proof.frameTimestamp <= Self.maximumFrameAge,
              case let .matched(identityID, similarity) = proof.match,
              similarity.isFinite, (0...1).contains(similarity)
        else { throw ScreenUnlockFailure.recognitionInvalid }
        let deadline = min(authorization.expiresAt,
                           proof.frameTimestamp + Self.maximumFrameAge,
                           now + Self.maximumReservationLifetime)
        guard deadline > now, let route = target.route else { throw ScreenUnlockFailure.deadlineExpired }
        let attempt = ScreenUnlockAttempt(id: UUID(), authorizationToken: authorization.token,
            lockGeneration: generation, deadline: deadline, identityID: identityID,
            challengeID: proof.challengeID, route: route, authorization: authorization,
            session: session, target: target, reservedAt: now)
        attemptedGeneration = generation
        pending = attempt
        submitting = nil
        return attempt
    }

    mutating func beginSubmission(_ attempt: ScreenUnlockAttempt,
                                 session: ScreenUnlockSessionSnapshot,
                                 target: ScreenUnlockTargetSnapshot, now: Double) throws {
        guard pending == attempt else { throw ScreenUnlockFailure.reservationInvalid }
        pending = nil
        do { try validate(attempt, session: session, target: target, now: now) }
        catch { revokeAfterValidationFailure(error); throw error }
        submitting = attempt
    }

    mutating func validateSubmission(_ attempt: ScreenUnlockAttempt,
                                     session: ScreenUnlockSessionSnapshot,
                                     target: ScreenUnlockTargetSnapshot, now: Double) throws {
        guard submitting == attempt else { throw ScreenUnlockFailure.reservationInvalid }
        do { try validate(attempt, session: session, target: target, now: now) }
        catch { revokeAfterValidationFailure(error); throw error }
    }

    private mutating func revokeAfterValidationFailure(_ error: Error) {
        // Failed output validation is terminal. Returning to the old focus or
        // receiving a stale locked snapshot cannot resurrect the reservation.
        if (error as? ScreenUnlockFailure) == .sessionUnverified { sessionUnlocked() }
        else { invalidate() }
    }

    private func validate(_ attempt: ScreenUnlockAttempt,
                          session: ScreenUnlockSessionSnapshot,
                          target: ScreenUnlockTargetSnapshot, now: Double) throws {
        guard isEnabled else { throw ScreenUnlockFailure.disabled }
        guard lockGeneration == attempt.lockGeneration else { throw ScreenUnlockFailure.noLockGeneration }
        guard now.isFinite, now >= attempt.reservedAt else { throw ScreenUnlockFailure.clockInvalid }
        guard now < attempt.deadline else { throw ScreenUnlockFailure.deadlineExpired }
        guard attempt.authorization.permitsRead(now: now, desktopIsActive: true, desktopIsUnlocked: false)
        else { throw ScreenUnlockFailure.authorizationInvalid }
        try Self.validateSession(session)
        try Self.validateTarget(target)
        guard session == attempt.session, target == attempt.target else { throw ScreenUnlockFailure.targetChanged }
    }

    static func validateSession(_ value: ScreenUnlockSessionSnapshot) throws {
        guard value.userID > 0, value.userID == value.effectiveUserID,
              value.consoleUserID == value.userID,
              let sessionID = value.securitySessionID, sessionID > 0, sessionID < UInt32.max - 1,
              value.onConsole == true, value.loginComplete == true, value.screenLocked == true,
              value.graphicalSession, !value.remoteSession, !value.rootSession, value.displayAwake
        else { throw ScreenUnlockFailure.sessionUnverified }
    }

    static func validateTarget(_ value: ScreenUnlockTargetSnapshot) throws {
        guard value.accessibilityTrusted else { throw ScreenUnlockFailure.accessibilityUnavailable }
        guard value.appleLoginwindow, value.process.processID > 0,
              value.process.startSeconds > 0, value.process.startMicroseconds < 1_000_000
        else { throw ScreenUnlockFailure.loginwindowUnverified }
        guard value.focusedSecureField, value.enabled else { throw ScreenUnlockFailure.secureFieldUnavailable }
        guard value.route != nil else { throw ScreenUnlockFailure.submissionUnavailable }
    }
}
