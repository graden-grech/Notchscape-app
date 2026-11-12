import Foundation
import CryptoKit
import Security
import LocalAuthentication
import Darwin

enum FaceVaultError: Error {
    case invalidInput, authenticationUnavailable, authenticationDenied, cancelled
    case authorizationRequired, desktopLocked, sessionExpired, invalidated
    case alreadyExists, unfinishedSetup, notFound, credentialMissing, storageFailure, invalidCiphertext
    case systemFailure(FaceVaultFailure)
}

/// Diagnostics contain only an allowlisted operation/domain and numeric codes.
/// Never retain NSError.userInfo, descriptions, item queries, paths or secrets.
enum FaceVaultFailureStage: String, Sendable {
    case accessControlCreation, authenticationAvailability, authenticationEvaluation
    case brokerConnection
    case keychainCreate, keychainRead, keychainDelete
    case encryptedRead, encryptedWrite, encryptedDelete
}

enum FaceVaultFailureDomain: String, Sendable {
    case osStatus = "OSStatus"
    case localAuthentication = "LA"
    case cocoa = "Cocoa"
    case posix = "POSIX"
    case validation = "Validation"
    case broker = "Broker"
    case system = "System"
}

struct FaceVaultFailure: Equatable, Sendable, CustomStringConvertible {
    let stage: FaceVaultFailureStage
    let domain: FaceVaultFailureDomain
    let code: Int
    let rollbackStatus: OSStatus?

    init(stage: FaceVaultFailureStage, domain: FaceVaultFailureDomain, code: Int,
         rollbackStatus: OSStatus? = nil) {
        self.stage = stage
        self.domain = domain
        self.code = code
        self.rollbackStatus = rollbackStatus
    }

    var isMissingEntitlement: Bool { domain == .osStatus && code == Int(errSecMissingEntitlement) }
    var diagnosticCode: String {
        let base = "\(stage.rawValue):\(domain.rawValue):\(code)"
        return rollbackStatus.map { "\(base);rollback:OSStatus:\($0)" } ?? base
    }
    var description: String { diagnosticCode }

    static func capturing(_ error: Error, stage: FaceVaultFailureStage,
                          rollbackStatus: OSStatus? = nil) -> Self {
        if case let FaceVaultError.systemFailure(existing) = error {
            return .init(stage: existing.stage, domain: existing.domain, code: existing.code,
                         rollbackStatus: rollbackStatus ?? existing.rollbackStatus)
        }
        let failure = error as NSError
        let domain: FaceVaultFailureDomain
        switch failure.domain {
        case NSOSStatusErrorDomain: domain = .osStatus
        case LAError.errorDomain: domain = .localAuthentication
        case NSCocoaErrorDomain: domain = .cocoa
        case NSPOSIXErrorDomain: domain = .posix
        default: domain = .system
        }
        return .init(stage: stage, domain: domain, code: failure.code, rollbackStatus: rollbackStatus)
    }
}

/// Pure query construction is tested without contacting either Keychain. This
/// deliberately has no fallback to file-based storage or synchronizable items.
enum FaceVaultKeychainPolicy {
    static let service = "app.notchscape.face-vault.v1"
    static var accessibility: CFString { kSecAttrAccessibleWhenUnlockedThisDeviceOnly }
    static let accessControlFlags: SecAccessControlCreateFlags = .userPresence

    static func baseQuery(vaultID: UUID, ownerUserID: UInt32) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "\(ownerUserID).\(vaultID.uuidString)",
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: false]
    }

    static func makeAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, accessibility, accessControlFlags, &error) else {
            if let error {
                throw FaceVaultError.systemFailure(.capturing(error.takeRetainedValue() as Error,
                    stage: .accessControlCreation))
            }
            throw FaceVaultError.systemFailure(.init(stage: .accessControlCreation,
                domain: .validation, code: 1))
        }
        return access
    }
}

enum FaceVaultStatus: Equatable, Sendable {
    case locked
    case authenticating
    case authorized(mode: FaceUnlockAuthorizationMode, remainingSeconds: Double)
    case automaticAuthorized(pausedForSleep: Bool)
}

/// The entire structure, including labels, vectors and optional credential, is
/// encrypted. This is not a public password-reading API.
struct FaceVaultContents: Codable, Equatable, Sendable, CustomDebugStringConvertible {
    var manifest: FaceIdentityManifest
    var credentialData: Data?
    var debugDescription: String { "FaceVaultContents(<redacted>)" }

    init?(manifest: FaceIdentityManifest, credentialData: Data?) {
        guard credentialData.map({ !$0.isEmpty && $0.count <= 4096 }) ?? true else { return nil }
        self.manifest = manifest
        self.credentialData = credentialData
    }

    private enum CodingKeys: String, CodingKey { case manifest, credentialData }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let value = Self(manifest: try c.decode(FaceIdentityManifest.self, forKey: .manifest),
            credentialData: try c.decodeIfPresent(Data.self, forKey: .credentialData)) else {
            throw FaceVaultError.invalidInput
        }
        self = value
    }
}

/// Side-effect-free crypto boundary, also exercised with synthetic test data.
enum FaceVaultCipher {
    static let maximumFileBytes = 4 * 1024 * 1024
    private struct Envelope: Codable {
        let formatVersion: Int
        let vaultID: UUID
        let ownerUserID: UInt32
        let sealedData: Data
    }

    static func seal(_ contents: FaceVaultContents, key: SymmetricKey,
                     vaultID: UUID, ownerUserID: UInt32) throws -> Data {
        guard FaceVaultContents(manifest: contents.manifest, credentialData: contents.credentialData) != nil else {
            throw FaceVaultError.invalidInput
        }
        var plaintext = try JSONEncoder().encode(contents)
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        guard plaintext.count <= 2 * 1024 * 1024 else { throw FaceVaultError.invalidInput }
        let box = try AES.GCM.seal(plaintext, using: key,
            authenticating: associatedData(vaultID, ownerUserID))
        guard let combined = box.combined else { throw FaceVaultError.invalidCiphertext }
        let result = try JSONEncoder().encode(Envelope(formatVersion: 1, vaultID: vaultID,
            ownerUserID: ownerUserID, sealedData: combined))
        guard result.count <= maximumFileBytes else { throw FaceVaultError.invalidInput }
        return result
    }

    static func open(_ encrypted: Data, key: SymmetricKey,
                     vaultID: UUID, ownerUserID: UInt32) throws -> FaceVaultContents {
        guard !encrypted.isEmpty, encrypted.count <= maximumFileBytes else { throw FaceVaultError.invalidCiphertext }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: encrypted)
            guard envelope.formatVersion == 1, envelope.vaultID == vaultID,
                  envelope.ownerUserID == ownerUserID, envelope.sealedData.count >= 28 else {
                throw FaceVaultError.invalidCiphertext
            }
            var plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.sealedData),
                using: key, authenticating: associatedData(vaultID, ownerUserID))
            defer { plaintext.resetBytes(in: 0..<plaintext.count) }
            guard plaintext.count <= 2 * 1024 * 1024 else { throw FaceVaultError.invalidCiphertext }
            return try JSONDecoder().decode(FaceVaultContents.self, from: plaintext)
        } catch { throw FaceVaultError.invalidCiphertext }
    }

    private static func associatedData(_ vaultID: UUID, _ owner: UInt32) -> Data {
        Data("Notchscape.FaceVault.v1|\(vaultID.uuidString.lowercased())|\(owner)".utf8)
    }
}

/// This boundary accepts encrypted envelopes only. Tests use isolated temporary
/// fixtures, so permissions/error paths are exercised without opening a vault.
enum FaceVaultEncryptedFileStore {
    /// Install a complete staged envelope with an atomic, exclusive hard link.
    /// Unlike an atomic replacement, this cannot overwrite an existing vault
    /// if another setup completes while authentication is pending.
    static func create(_ encrypted: Data, to fileURL: URL, directory: URL) throws {
        guard fileURL.isFileURL,
              fileURL.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path else {
            throw FaceVaultError.systemFailure(.init(stage: .encryptedWrite, domain: .validation, code: 1))
        }
        let staged = directory.appendingPathComponent(".\(UUID().uuidString).vault-pending")
        defer { try? FileManager.default.removeItem(at: staged) }
        try write(encrypted, to: staged, directory: directory)
        let result = staged.withUnsafeFileSystemRepresentation { source in
            fileURL.withUnsafeFileSystemRepresentation { destination in
                guard let source, let destination else { return Int32(-1) }
                return Darwin.link(source, destination)
            }
        }
        guard result == 0 else {
            let failure = errno
            if failure == EEXIST { throw FaceVaultError.alreadyExists }
            throw FaceVaultError.systemFailure(.init(stage: .encryptedWrite, domain: .posix, code: Int(failure)))
        }
    }

    static func read(from fileURL: URL) throws -> Data {
        do {
            let properties = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard properties.isRegularFile == true, properties.isSymbolicLink != true,
                  let size = properties.fileSize, size > 0, size <= FaceVaultCipher.maximumFileBytes else {
                throw FaceVaultError.systemFailure(.init(stage: .encryptedRead, domain: .validation, code: 1))
            }
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: FaceVaultCipher.maximumFileBytes + 1) ?? Data()
            guard !data.isEmpty, data.count <= FaceVaultCipher.maximumFileBytes else {
                throw FaceVaultError.systemFailure(.init(stage: .encryptedRead, domain: .validation, code: 1))
            }
            return data
        } catch { throw FaceVaultError.systemFailure(.capturing(error, stage: .encryptedRead)) }
    }

    static func write(_ encrypted: Data, to fileURL: URL, directory: URL) throws {
        do {
            guard directory.isFileURL, fileURL.isFileURL,
                  !encrypted.isEmpty, encrypted.count <= FaceVaultCipher.maximumFileBytes,
                  fileURL.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path,
                  directory.resolvingSymlinksInPath().path == directory.path else {
                throw FaceVaultError.systemFailure(.init(stage: .encryptedWrite, domain: .validation, code: 1))
            }
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
            }
            let properties = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard properties.isDirectory == true, properties.isSymbolicLink != true else {
                throw FaceVaultError.systemFailure(.init(stage: .encryptedWrite, domain: .validation, code: 1))
            }
            if FileManager.default.fileExists(atPath: fileURL.path),
               try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw FaceVaultError.systemFailure(.init(stage: .encryptedWrite, domain: .validation, code: 1))
            }
            try encrypted.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch { throw FaceVaultError.systemFailure(.capturing(error, stage: .encryptedWrite)) }
    }
}

private enum FaceVaultMonotonicClock {
    static let clock = ContinuousClock()
    static let origin = clock.now
    static var now: Double {
        let elapsed = origin.duration(to: clock.now).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }
}

/// Local, default-locked vault. Construction performs no IO, Keychain access,
/// authentication, camera capture or permission request.
actor FaceUnlockVault {
    private let directory: URL
    private let fileURL: URL
    private let vaultID: UUID
    private let ownerUserID: UInt32
    private let clock = ContinuousClock()
    private var desktopIsActive = false
    private var desktopIsUnlocked = false
    private var session: FaceUnlockAuthorizationSession?
    private var unwrappedKey: SymmetricKey?
    private var keyBroker: (any FaceVaultKeyBrokerTransport)?
    private var availabilityBroker: (any FaceVaultKeyBrokerTransport)?
    private let brokerFactory: @Sendable () -> any FaceVaultKeyBrokerTransport
    private var generation = UUID()
    private var expiryTask: Task<Void, Never>?

    init(directory: URL, vaultID: UUID,
         brokerFactory: @escaping @Sendable () -> any FaceVaultKeyBrokerTransport = { FaceVaultKeyBrokerClient() }) throws {
        guard directory.isFileURL, !directory.path.isEmpty else { throw FaceVaultError.invalidInput }
        self.directory = directory.standardizedFileURL
        self.fileURL = directory.standardizedFileURL.appendingPathComponent(vaultID.uuidString).appendingPathExtension("vault")
        self.vaultID = vaultID
        self.ownerUserID = getuid()
        self.brokerFactory = brokerFactory
    }

    /// Shared clock for consumers validating the exported authorization session.
    /// Its origin is process-local; never compare it with Date or systemUptime.
    nonisolated static func monotonicNow() -> Double { FaceVaultMonotonicClock.now }

    func updateDesktopState(isActive: Bool, isUnlocked: Bool) {
        desktopIsActive = isActive
        desktopIsUnlocked = isUnlocked
        if !isActive { handle(.sessionInactive) }
        else if !isUnlocked { handle(.screenLocked) }
        else { handle(.screenUnlocked) }
    }

    func handle(_ event: FaceUnlockInvalidationEvent) {
        switch event {
        case .screenLocked: desktopIsUnlocked = false
        case .screenUnlocked: desktopIsUnlocked = true
        case .logout, .sessionInactive, .appTerminated:
            desktopIsActive = false; desktopIsUnlocked = false
        case .systemSleep:
            desktopIsUnlocked = false
            if session?.mode != .automaticWhileRunning { desktopIsActive = false }
        case .stop, .timeout, .privacyChanged, .systemWake: break
        }
        if availabilityBroker != nil {
            switch event {
            case .screenUnlocked: break
            default: availabilityBroker?.invalidate(); availabilityBroker = nil
            }
        }
        if keyBroker != nil {
            switch event {
            case .screenUnlocked: break
            default: clearAuthorization()
            }
        }
        session?.handle(event, now: now)
        if session?.isInvalidated == true { clearAuthorization() }
        if case .stop = event { clearAuthorization() }
        if case .privacyChanged = event { clearAuthorization() }
    }

    func stop() { clearAuthorization() }

    func status() -> FaceVaultStatus {
        expireIfNeeded()
        if keyBroker != nil { return .authenticating }
        guard let session, unwrappedKey != nil else { return .locked }
        if session.mode == .automaticWhileRunning { return .automaticAuthorized(pausedForSleep: session.isPausedForSleep) }
        return .authorized(mode: session.mode, remainingSeconds: max(0, session.expiresAt - now))
    }

    func authorizationSession() -> FaceUnlockAuthorizationSession? {
        expireIfNeeded()
        return unwrappedKey == nil ? nil : session
    }

    /// Harmless broker configuration/peer preflight. It never requests a key,
    /// evaluates user presence, reads a vault file, or changes an existing grant.
    func checkAvailability() async throws {
        try requireUnlockedDesktop()
        guard keyBroker == nil, availabilityBroker == nil else {
            throw FaceVaultError.systemFailure(.init(stage: .brokerConnection,
                domain: .broker, code: FaceVaultBrokerErrorCode.busy.rawValue))
        }
        let token = generation
        let broker = brokerFactory()
        availabilityBroker = broker
        defer { broker.invalidate(); if availabilityBroker === broker { availabilityBroker = nil } }
        try await broker.checkAvailability()
        guard availabilityBroker === broker else { throw FaceVaultError.invalidated }
        try checkAuthenticationCompletion(token)
    }

    /// User-controlled setup only. It authenticates, creates one new protected
    /// master-key item and encrypted file, and leaves the vault locked afterward.
    func setup(initialManifest: FaceIdentityManifest, credentialData: Data?, reason: String) async throws {
        guard let contents = FaceVaultContents(manifest: initialManifest, credentialData: credentialData) else {
            throw FaceVaultError.invalidInput
        }
        try requireUnlockedDesktop()
        try validateReason(reason)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { throw FaceVaultError.alreadyExists }
        clearAuthorization()
        let token = generation
        let broker = brokerFactory()
        keyBroker = broker
        defer { broker.invalidate(); if keyBroker === broker { keyBroker = nil } }
        let created: FaceVaultCreatedMasterKey
        do { created = try await broker.createMasterKey(vaultID: vaultID, reason: reason) }
        catch FaceVaultError.alreadyExists {
            try checkAuthenticationCompletion(token)
            if FileManager.default.fileExists(atPath: fileURL.path) { throw FaceVaultError.alreadyExists }
            throw FaceVaultError.unfinishedSetup
        }
        var rawKey = created.keyData
        defer { rawKey.resetBytes(in: 0..<rawKey.count) }
        do {
            try checkAuthenticationCompletion(token)
            guard rawKey.count == 32 else { throw FaceVaultError.invalidCiphertext }
            guard !FileManager.default.fileExists(atPath: fileURL.path) else { throw FaceVaultError.alreadyExists }
            try create(contents, key: SymmetricKey(data: rawKey))
        } catch {
            var rollbackStatus: OSStatus?
            do { try await broker.rollbackCreatedMasterKey(vaultID: vaultID, receipt: created.receipt) }
            catch FaceVaultError.systemFailure(let details) {
                rollbackStatus = details.domain == .osStatus ? Int32(exactly: details.code) : errSecInternalError
            } catch { rollbackStatus = errSecInternalError }
            if let rollbackStatus {
                throw FaceVaultError.systemFailure(.capturing(error, stage: .encryptedWrite, rollbackStatus: rollbackStatus))
            }
            throw error
        }
    }

    /// Explicit recovery only: authenticate access to the exact pre-existing
    /// master key, then create a NEW EMPTY envelope only if it remains absent.
    /// It never replaces/deletes a key or an existing encrypted file, and it
    /// never pretends a missing enrollment/credential has been recovered.
    func recoverUnfinishedSetup(reason: String) async throws {
        try requireUnlockedDesktop()
        try validateReason(reason)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { throw FaceVaultError.alreadyExists }
        clearAuthorization()
        let token = generation
        let broker = brokerFactory()
        keyBroker = broker
        defer { broker.invalidate(); if keyBroker === broker { keyBroker = nil } }
        var raw = try await broker.readMasterKey(vaultID: vaultID, reason: reason)
        defer { raw.resetBytes(in: 0..<raw.count) }
        try checkAuthenticationCompletion(token)
        guard raw.count == 32 else { throw FaceVaultError.invalidCiphertext }
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { throw FaceVaultError.alreadyExists }
        guard let empty = FaceVaultContents(manifest: .empty, credentialData: nil) else { throw FaceVaultError.invalidInput }
        try create(empty, key: SymmetricKey(data: raw))
    }

    func authorizeUnlockedSession(lifetime: TimeInterval = 60, reason: String) async throws {
        try await authorize(mode: .unlockedOnly, lifetime: lifetime, reason: reason)
    }

    /// Explicit convenience capability: authenticates while unlocked, then
    /// retains the unwrapped key in RAM across screen lock for the chosen TTL.
    /// This does not make the Keychain item accessible while locked and is not
    /// Apple Face ID. The caller must present this tradeoff before invoking it.
    func authorizeScreenUnlockConvenience(lifetime: TimeInterval, reason: String) async throws {
        try await authorize(mode: .screenUnlockConvenience, lifetime: lifetime, reason: reason)
    }

    /// Requires fresh system authentication while unlocked. The explicit grant
    /// keeps only the unwrapped key in volatile memory until Off/revocation or
    /// app termination; no Keychain accessibility or protection is relaxed.
    func authorizeAutomaticUnlock(reason: String) async throws {
        try await authorize(mode: .automaticWhileRunning, lifetime: nil, reason: reason)
    }

    func manifest() throws -> FaceIdentityManifest {
        try read(key: requireKey()).manifest
    }

    func hasCredential() throws -> Bool {
        try read(key: requireKey()).credentialData != nil
    }

    func saveManifest(_ manifest: FaceIdentityManifest) throws {
        let key = try requireKey(requireUnlocked: true)
        var contents = try read(key: key)
        contents.manifest = manifest
        try write(contents, key: key)
    }

    func setCredentialData(_ data: Data?) throws {
        guard data.map({ !$0.isEmpty && $0.count <= 4096 }) ?? true else { throw FaceVaultError.invalidInput }
        let key = try requireKey(requireUnlocked: true)
        var contents = try read(key: key)
        contents.credentialData = data
        try write(contents, key: key)
    }

    /// No broad password getter. The trusted action must be synchronous, short,
    /// must not retain/log the data, and must perform its own targeted-action
    /// deadline/session checks. Camera challenge truth is supplied by the camera
    /// pipeline; this API does not attest liveness or treat it as Keychain auth.
    func withCredentialForRecognizedFace(_ embedding: FaceNormalizedEmbedding,
        thresholds: FaceMatchThresholds, challengeSatisfied: Bool,
        authorizationToken: UUID,
        operation: @Sendable (Data) throws -> Void) throws -> FaceMatchOutcome {
        guard challengeSatisfied else { return .noMatch }
        guard session?.token == authorizationToken else { throw FaceVaultError.invalidated }
        let key = try requireKey(requireConvenience: true)
        var contents = try read(key: key)
        let match = FaceIdentityMatcher.matchAuthorizedFace(embedding, manifest: contents.manifest, thresholds: thresholds)
        guard case .matched = match else { return match }
        guard var secret = contents.credentialData else { throw FaceVaultError.credentialMissing }
        contents.credentialData = nil
        defer { secret.resetBytes(in: 0..<secret.count) }
        _ = try requireKey(requireConvenience: true)
        guard session?.token == authorizationToken else { throw FaceVaultError.invalidated }
        try operation(secret)
        expireIfNeeded()
        return match
    }

    func deleteVault() async throws {
        _ = try requireKey(requireUnlocked: true)
        guard keyBroker == nil else {
            throw FaceVaultError.systemFailure(.init(stage: .brokerConnection,
                domain: .broker, code: FaceVaultBrokerErrorCode.busy.rawValue))
        }
        let token = generation
        let broker = brokerFactory()
        keyBroker = broker
        defer { broker.invalidate(); if keyBroker === broker { keyBroker = nil } }
        try await broker.deleteMasterKey(vaultID: vaultID, reason: "Delete the encrypted Face Unlock vault")
        try checkAuthenticationCompletion(token)
        defer { clearAuthorization() }
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
        } catch { throw FaceVaultError.systemFailure(.capturing(error, stage: .encryptedDelete)) }
    }

    private func authorization(mode: FaceUnlockAuthorizationMode, lifetime: Double?, token: UUID) -> FaceUnlockAuthorizationSession? {
        if mode == .automaticWhileRunning {
            guard lifetime == nil else { return nil }
            return .automaticWhileRunning(now: now, token: token)
        }
        guard let lifetime else { return nil }
        return .init(mode: mode, lifetime: lifetime, now: now, token: token)
    }

    private func authorize(mode: FaceUnlockAuthorizationMode, lifetime: Double?, reason: String) async throws {
        try requireUnlockedDesktop()
        guard authorization(mode: mode, lifetime: lifetime, token: UUID()) != nil else {
            throw FaceVaultError.invalidInput
        }
        clearAuthorization()
        let token = generation
        try validateReason(reason)
        let broker = brokerFactory()
        keyBroker = broker
        defer { broker.invalidate(); if keyBroker === broker { keyBroker = nil } }
        var raw = try await broker.readMasterKey(vaultID: vaultID, reason: reason)
        defer { raw.resetBytes(in: 0..<raw.count) }
        try checkAuthenticationCompletion(token)
        guard raw.count == 32 else { throw FaceVaultError.invalidCiphertext }
        let key = SymmetricKey(data: raw)
        _ = try read(key: key) // Authentication alone never accepts corrupt/other-user data.
        try checkAuthenticationCompletion(token)
        guard let policy = authorization(mode: mode, lifetime: lifetime, token: token) else {
            throw FaceVaultError.invalidInput
        }
        session = policy
        unwrappedKey = key
        if let deadline = policy.deadline {
            let instant = clock.now.advanced(by: .seconds(max(0, deadline - now)))
            expiryTask = Task { [weak self] in
                do { try await ContinuousClock().sleep(until: instant) } catch { return }
                await self?.expire(token: token)
            }
        }
    }

    private func validateReason(_ reason: String) throws {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              reason.count <= 200, !reason.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw FaceVaultError.invalidInput
        }
    }

    private func checkAuthenticationCompletion(_ token: UUID) throws {
        guard !Task.isCancelled else { throw FaceVaultError.cancelled }
        guard token == generation else { throw FaceVaultError.invalidated }
        try requireUnlockedDesktop()
    }

    private var now: Double { Self.monotonicNow() }

    private func requireUnlockedDesktop() throws {
        guard !Task.isCancelled else { throw FaceVaultError.cancelled }
        guard desktopIsActive, desktopIsUnlocked else { throw FaceVaultError.desktopLocked }
    }

    private func requireKey(requireUnlocked: Bool = false, requireConvenience: Bool = false) throws -> SymmetricKey {
        guard !Task.isCancelled else { throw FaceVaultError.cancelled }
        expireIfNeeded()
        guard let session, let key = unwrappedKey,
              session.permitsRead(now: now, desktopIsActive: desktopIsActive, desktopIsUnlocked: desktopIsUnlocked) else {
            throw FaceVaultError.authorizationRequired
        }
        if requireUnlocked { try requireUnlockedDesktop() }
        if requireConvenience, !session.permitsScreenUnlock { throw FaceVaultError.authorizationRequired }
        return key
    }

    private func expireIfNeeded() {
        guard let session else { return }
        if !session.retainsAuthorization(now: now, desktopIsActive: desktopIsActive) {
            clearAuthorization()
        }
    }

    private func expire(token: UUID) {
        if session?.token == token { clearAuthorization() }
    }

    private func clearAuthorization() {
        generation = UUID()
        keyBroker?.invalidate()
        keyBroker = nil
        availabilityBroker?.invalidate()
        availabilityBroker = nil
        expiryTask?.cancel()
        expiryTask = nil
        session = nil
        unwrappedKey = nil
    }

    private func read(key: SymmetricKey) throws -> FaceVaultContents {
        let data = try FaceVaultEncryptedFileStore.read(from: fileURL)
        return try FaceVaultCipher.open(data, key: key, vaultID: vaultID, ownerUserID: ownerUserID)
    }

    private func write(_ contents: FaceVaultContents, key: SymmetricKey) throws {
        let encrypted = try FaceVaultCipher.seal(contents, key: key, vaultID: vaultID, ownerUserID: ownerUserID)
        try FaceVaultEncryptedFileStore.write(encrypted, to: fileURL, directory: directory)
    }

    private func create(_ contents: FaceVaultContents, key: SymmetricKey) throws {
        let encrypted = try FaceVaultCipher.seal(contents, key: key, vaultID: vaultID, ownerUserID: ownerUserID)
        try FaceVaultEncryptedFileStore.create(encrypted, to: fileURL, directory: directory)
    }

    deinit {
        expiryTask?.cancel()
        keyBroker?.invalidate()
        availabilityBroker?.invalidate()
        // Swift/Data/CryptoKit reference release is not guaranteed RAM erasure.
    }
}
