import Foundation
import CryptoKit
import Security
import Darwin

/// Every key, template, credential and file in this suite is synthetic. The
/// production XPC adapter is never constructed; no service/auth/Keychain runs.
private final class SyntheticMasterKeyStore: @unchecked Sendable {
    enum Operation: Hashable { case availability, create, read, delete, rollback }
    private let lock = NSLock()
    private var keys: [UUID: Data] = [:]
    private var receipts: [UUID: (vaultID: UUID, connectionID: UUID)] = [:]
    private var counts: [Operation: Int] = [:]
    private var connections = 0
    private var invalidations = Set<UUID>()
    private var hooks: [Operation: @Sendable () async -> Void] = [:]
    private var readOverride: Data?
    private var createOverride: Data?
    private var failures: [Operation: FaceVaultError] = [:]
    private var loseCreateReply = false
    private var cancelAfterRead = false
    private var cancelAfterCreate = false
    private var deliveries = 0
    private var exactDelivery = true
    private var lastCreateConnection: UUID?
    private var lastRollbackConnection: UUID?

    func connect() -> SyntheticMasterKeyConnection {
        lock.withLock { connections += 1 }
        return SyntheticMasterKeyConnection(store: self)
    }
    func count(_ operation: Operation) -> Int { lock.withLock { counts[operation, default: 0] } }
    func connectionCount() -> Int { lock.withLock { connections } }
    func invalidationCount() -> Int { lock.withLock { invalidations.count } }
    func key(_ id: UUID) -> Data? { lock.withLock { keys[id] } }
    func seed(_ id: UUID, key: Data) { lock.withLock { keys[id] = key } }
    func setReadOverride(_ value: Data?) { lock.withLock { readOverride = value } }
    func setCreateOverride(_ value: Data?) { lock.withLock { createOverride = value } }
    func setFailure(_ value: FaceVaultError?, for operation: Operation) { lock.withLock { failures[operation] = value } }
    func setLostCreateReply(_ value: Bool) { lock.withLock { loseCreateReply = value } }
    func cancelNextRead() { lock.withLock { cancelAfterRead = true } }
    func cancelNextCreate() { lock.withLock { cancelAfterCreate = true } }
    func setHook(_ operation: Operation, hook: @escaping @Sendable () async -> Void) { lock.withLock { hooks[operation] = hook } }
    func takeHook(_ operation: Operation) -> (@Sendable () async -> Void)? { lock.withLock { hooks.removeValue(forKey: operation) } }
    func shouldCancel(_ operation: Operation) -> Bool {
        lock.withLock {
            if operation == .read { defer { cancelAfterRead = false }; return cancelAfterRead }
            if operation == .create { defer { cancelAfterCreate = false }; return cancelAfterCreate }
            return false
        }
    }
    func invalidate(_ id: UUID) {
        lock.withLock {
            invalidations.insert(id)
            receipts = receipts.filter { $0.value.connectionID != id }
        }
    }
    func sameConnectionRollback() -> Bool { lock.withLock { lastCreateConnection != nil && lastCreateConnection == lastRollbackConnection } }
    func recordDelivery(_ value: Data, expected: Data) { lock.withLock { deliveries += 1; exactDelivery = exactDelivery && value == expected } }
    func deliverySummary() -> (Int, Bool) { lock.withLock { (deliveries, exactDelivery) } }
    func availability() throws { try lock.withLock { counts[.availability, default: 0] += 1; if let failure = failures[.availability] { throw failure } } }
    func create(_ id: UUID, connectionID: UUID) throws -> FaceVaultCreatedMasterKey {
        try lock.withLock {
            counts[.create, default: 0] += 1
            if let failure = failures[.create] { throw failure }
            guard keys[id] == nil else { throw FaceVaultError.alreadyExists }
            let key = Data(repeating: 17, count: 32), receipt = UUID()
            keys[id] = key; receipts[receipt] = (id, connectionID); lastCreateConnection = connectionID
            if loseCreateReply {
                throw FaceVaultError.systemFailure(.init(stage: .brokerConnection, domain: .cocoa, code: NSXPCConnectionInterrupted))
            }
            return .init(keyData: createOverride ?? key, receipt: receipt)
        }
    }
    func read(_ id: UUID) throws -> Data {
        try lock.withLock {
            counts[.read, default: 0] += 1
            if let failure = failures[.read] { throw failure }
            guard let key = keys[id] else { throw FaceVaultError.notFound }
            return readOverride ?? key
        }
    }
    func delete(_ id: UUID) throws {
        try lock.withLock {
            counts[.delete, default: 0] += 1
            if let failure = failures[.delete] { throw failure }
            keys[id] = nil
        }
    }
    func rollback(_ id: UUID, receipt: UUID, connectionID: UUID) throws {
        try lock.withLock {
            counts[.rollback, default: 0] += 1; lastRollbackConnection = connectionID
            if let failure = failures[.rollback] { throw failure }
            guard let created = receipts.removeValue(forKey: receipt), created.vaultID == id,
                  created.connectionID == connectionID else { throw FaceVaultError.invalidated }
            keys[id] = nil
        }
    }
}

private final class SyntheticMasterKeyConnection: FaceVaultKeyBrokerTransport, @unchecked Sendable {
    let id = UUID()
    private let store: SyntheticMasterKeyStore
    init(store: SyntheticMasterKeyStore) { self.store = store }
    func checkAvailability() async throws { try store.availability(); if let hook = store.takeHook(.availability) { await hook() } }
    func createMasterKey(vaultID: UUID, reason: String) async throws -> FaceVaultCreatedMasterKey {
        let result = try store.create(vaultID, connectionID: id)
        if let hook = store.takeHook(.create) { await hook() }
        if store.shouldCancel(.create) { withUnsafeCurrentTask { $0?.cancel() } }
        return result
    }
    func readMasterKey(vaultID: UUID, reason: String) async throws -> Data {
        let result = try store.read(vaultID)
        if let hook = store.takeHook(.read) { await hook() }
        if store.shouldCancel(.read) { withUnsafeCurrentTask { $0?.cancel() } }
        // Deliberately permit a late reply after invalidate: the vault must
        // independently reject stale/cancelled replies even from a bad transport.
        return result
    }
    func deleteMasterKey(vaultID: UUID, reason: String) async throws { try store.delete(vaultID) }
    func rollbackCreatedMasterKey(vaultID: UUID, receipt: UUID) async throws { try store.rollback(vaultID, receipt: receipt, connectionID: id) }
    func invalidate() { store.invalidate(id) }
}

private actor SyntheticReadSignal {
    private var entered = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func signal() { entered = true; let pending = waiters; waiters.removeAll(); for waiter in pending { waiter.resume() } }
    func wait() async { if entered { return }; await withCheckedContinuation { waiters.append($0) } }
}

/// Objective-C wire callbacks are stored under a lock and invoked sequentially
/// by these tests. This fake never touches NSXPCConnection or a real service.
private final class SyntheticWireProxy: NSObject, FaceVaultKeyBrokerProtocol, @unchecked Sendable {
    let readSignal = SyntheticReadSignal()
    private let lock = NSLock()
    private var pendingRead: ((Data?, NSError?) -> Void)?
    var deferRead = false
    func checkAvailability(withReply reply: @escaping (NSError?) -> Void) { reply(nil) }
    func createMasterKey(vaultID: NSUUID, reason: String, withReply reply: @escaping (Data?, NSUUID?, NSError?) -> Void) {
        reply(Data(repeating: 9, count: 32), NSUUID(), nil)
    }
    func readMasterKey(vaultID: NSUUID, reason: String, withReply reply: @escaping (Data?, NSError?) -> Void) {
        if deferRead { lock.withLock { pendingRead = reply }; Task { await readSignal.signal() } }
        else { reply(Data(repeating: 9, count: 32), nil) }
    }
    func deleteMasterKey(vaultID: NSUUID, reason: String, withReply reply: @escaping (NSError?) -> Void) { reply(nil) }
    func rollbackCreatedMasterKey(vaultID: NSUUID, receipt: NSUUID, withReply reply: @escaping (NSError?) -> Void) { reply(nil) }
    func replyToRead(repeatReply: Bool = false) {
        let reply = lock.withLock { let value = pendingRead; pendingRead = nil; return value }
        reply?(Data(repeating: 9, count: 32), nil)
        if repeatReply { reply?(Data(repeating: 9, count: 32), nil) }
    }
}

private final class SyntheticWireConnection: FaceVaultBrokerConnectionTransport, @unchecked Sendable {
    let wire: SyntheticWireProxy
    private let lock = NSLock()
    private let invalidated: @Sendable () -> Void
    private let interrupted: @Sendable () -> Void
    private var proxyError: (@Sendable (any Error) -> Void)?
    private var resumes = 0
    private var invalidations = 0
    init(wire: SyntheticWireProxy, invalidated: @escaping @Sendable () -> Void, interrupted: @escaping @Sendable () -> Void) {
        self.wire = wire; self.invalidated = invalidated; self.interrupted = interrupted
    }
    func resume() { lock.withLock { resumes += 1 } }
    func invalidate() { lock.withLock { invalidations += 1 }; invalidated() }
    func proxy(errorHandler: @escaping @Sendable (any Error) -> Void) -> FaceVaultKeyBrokerProtocol? {
        lock.withLock { proxyError = errorHandler }; return wire
    }
    func interrupt() { interrupted() }
    func failProxy() { lock.withLock { proxyError }?(NSError(domain: NSCocoaErrorDomain, code: NSXPCConnectionInvalid)) }
    func counts() -> (Int, Int) { lock.withLock { (resumes, invalidations) } }
}

private final class SyntheticWireFactory: @unchecked Sendable {
    let wire = SyntheticWireProxy()
    private let lock = NSLock()
    private var connections: [SyntheticWireConnection] = []
    func connect(_ invalidated: @escaping @Sendable () -> Void, _ interrupted: @escaping @Sendable () -> Void) -> any FaceVaultBrokerConnectionTransport {
        let connection = SyntheticWireConnection(wire: wire, invalidated: invalidated, interrupted: interrupted)
        lock.withLock { connections.append(connection) }; return connection
    }
    func count() -> Int { lock.withLock { connections.count } }
    func latest() -> SyntheticWireConnection { lock.withLock { connections.last! } }
}

@main struct FaceUnlockVaultIntegrationTests {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) { precondition(condition, message); checks += 1 }
        func failure(_ operation: @MainActor () async throws -> Void) async -> FaceVaultError {
            do { try await operation(); preconditionFailure("expected a refused synthetic operation") }
            catch let error as FaceVaultError { checks += 1; return error }
            catch { preconditionFailure("unexpected synthetic failure type") }
        }
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("notchscape-vault-integration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let store = SyntheticMasterKeyStore(), id = UUID(), directory = root.appendingPathComponent("normal")
        let file = directory.appendingPathComponent(id.uuidString).appendingPathExtension("vault")
        let vault = try FaceUnlockVault(directory: directory, vaultID: id, brokerFactory: { store.connect() })
        check(store.connectionCount() == 0 && !FileManager.default.fileExists(atPath: file.path), "construction never connects or creates storage")
        await vault.updateDesktopState(isActive: true, isUnlocked: true)
        try await vault.checkAvailability()
        check(store.count(.availability) == 1 && store.count(.create) == 0 && store.count(.read) == 0,
              "availability preflight requests no key/authentication operation")
        check(await vault.status() == .locked && !FileManager.default.fileExists(atPath: file.path), "availability cannot create/authorize a vault")
        let schema = FaceEmbeddingSchema(modelVersion: "synthetic-integration-v1", dimension: 16)!
        let face = FaceNormalizedEmbedding(schema: schema, values: [1] + [Float](repeating: 0, count: 15))!
        let first = FaceIdentityTemplate(label: "Synthetic first", samples: [face])!
        let second = FaceIdentityTemplate(label: "Synthetic second", samples: [face])!
        let manifest = FaceIdentityManifest(identities: [first, second])!
        let credential = Data("synthetic-not-a-real-password".utf8)
        try await vault.setup(initialManifest: manifest, credentialData: credential, reason: "Synthetic setup")
        check(await vault.status() == .locked && store.count(.create) == 1, "create stores encrypted data but leaves authorization off")
        check(store.count(.rollback) == 0 && FileManager.default.fileExists(atPath: file.path), "successful create never rolls back its retained key")
        try await vault.authorizeAutomaticUnlock(reason: "Synthetic automatic authorization")
        let authorization = await vault.authorizationSession()!
        check(authorization.mode == .automaticWhileRunning && authorization.deadline == nil, "actual vault establishes explicit automatic mode")
        let storedManifest = try await vault.manifest(), hasCredential = try await vault.hasCredential()
        check(storedManifest == manifest && hasCredential, "multiple enabled faces and credential survive encrypted setup")
        let readsAfterAuth = store.count(.read)
        let thresholds = FaceMatchThresholds(minimumCosineSimilarity: 0.8, minimumRunnerUpMargin: 0.05)!
        for _ in 0..<3 {
            await vault.updateDesktopState(isActive: true, isUnlocked: false)
            let outcome = try await vault.withCredentialForRecognizedFace(face, thresholds: thresholds,
                challengeSatisfied: true, authorizationToken: authorization.token) { value in store.recordDelivery(value, expected: credential) }
            if case .matched = outcome { check(true, "synthetic face may invoke only the supplied harmless closure") }
            else { preconditionFailure("expected trusted synthetic appearance") }
            await vault.updateDesktopState(isActive: true, isUnlocked: true)
            check(await vault.authorizationSession()?.token == authorization.token, "ordinary locks do not require manual reauthorization")
        }
        check(store.count(.read) == readsAfterAuth && store.deliverySummary().0 == 3 && store.deliverySummary().1,
              "ordinary lock cycles use volatile key only and preserve exact synthetic delivery")
        try await vault.checkAvailability()
        check(await vault.authorizationSession()?.token == authorization.token, "availability never changes an active automatic grant")
        store.setFailure(.systemFailure(.init(stage: .brokerConnection, domain: .broker,
            code: FaceVaultBrokerErrorCode.configurationInvalid.rawValue)), for: .availability)
        _ = await failure { try await vault.checkAvailability() }
        check(await vault.authorizationSession()?.token == authorization.token, "harmless preflight failure cannot revoke an existing automatic grant")
        store.setFailure(nil, for: .availability)
        store.setHook(.availability) {
            await vault.updateDesktopState(isActive: true, isUnlocked: false)
            await vault.updateDesktopState(isActive: true, isUnlocked: true)
            try! await vault.checkAvailability()
        }
        let staleAvailability = await failure { try await vault.checkAvailability() }
        if case .invalidated = staleAvailability { check(true, "canceled availability reply cannot be accepted after another preflight") }
        else { preconditionFailure("expected invalidated availability") }
        check(await vault.authorizationSession()?.token == authorization.token, "availability cancellation across ordinary lock keeps the automatic grant")
        await vault.handle(.systemSleep)
        check(await vault.status() == .automaticAuthorized(pausedForSleep: true), "actual vault pauses instead of erasing automatic key on sleep")
        _ = await failure { _ = try await vault.manifest() }
        await vault.handle(.systemWake)
        let resumedManifest = try await vault.manifest(), resumedAuthorization = await vault.authorizationSession()
        check(resumedManifest == manifest && resumedAuthorization?.token == authorization.token,
              "wake resumes volatile authorization without broker read or timed restart")
        await vault.updateDesktopState(isActive: true, isUnlocked: true)
        let beforeRevocation = store.count(.read)
        await vault.stop()
        check(await vault.status() == .locked && store.count(.read) == beforeRevocation, "Off immediately drops authorization without broker access")
        let stale = await failure {
            _ = try await vault.withCredentialForRecognizedFace(face, thresholds: thresholds,
                challengeSatisfied: true, authorizationToken: authorization.token) { _ in preconditionFailure("stale grant leaked") }
        }
        if case .invalidated = stale { check(true, "stale token cannot deliver a credential") } else { preconditionFailure("expected stale token refusal") }
        for event in [FaceUnlockInvalidationEvent.logout, .sessionInactive, .privacyChanged, .appTerminated] {
            await vault.updateDesktopState(isActive: true, isUnlocked: true)
            try await vault.authorizeAutomaticUnlock(reason: "Synthetic lifecycle test")
            await vault.handle(event)
            await vault.updateDesktopState(isActive: true, isUnlocked: true)
            let revokedSession = await vault.authorizationSession(), revokedStatus = await vault.status()
            check(revokedSession == nil && revokedStatus == .locked, "revocation cannot revive after an unlock notification")
        }

        // Malformed/wrong/denied replies never establish authorization; a new
        // explicit request gets a fresh transport rather than reconnecting one.
        for wrong in [Data(repeating: 23, count: 31), Data(repeating: 23, count: 32)] {
            store.setReadOverride(wrong)
            _ = await failure { try await vault.authorizeAutomaticUnlock(reason: "Synthetic wrong key") }
            check(await vault.authorizationSession() == nil, "bad key or wrong ciphertext authentication remains locked")
        }
        store.setReadOverride(nil)
        store.setFailure(.authenticationDenied, for: .read)
        _ = await failure { try await vault.authorizeAutomaticUnlock(reason: "Synthetic denied auth") }
        check(await vault.status() == .locked, "denied auth does not create a grant")
        store.setFailure(nil, for: .read)
        store.cancelNextRead()
        let cancelled = Task { try await vault.authorizeAutomaticUnlock(reason: "Synthetic cancellation") }
        let cancellation = await failure { try await cancelled.value }
        if case .cancelled = cancellation { check(true, "cancelled read reply refused before accepting key") } else { preconditionFailure("expected cancellation") }
        check(await vault.authorizationSession() == nil, "cancelled broker reply never restores authorization")
        store.setHook(.read) { await vault.stop() }
        _ = await failure { try await vault.authorizeAutomaticUnlock(reason: "Synthetic stale reply") }
        check(await vault.authorizationSession() == nil, "stop during suspended broker read rejects late key")
        store.setHook(.read) {
            await vault.stop()
            try! await vault.authorizeAutomaticUnlock(reason: "Synthetic replacement grant")
        }
        _ = await failure { try await vault.authorizeAutomaticUnlock(reason: "Synthetic obsolete grant") }
        check(await vault.authorizationSession()?.mode == .automaticWhileRunning, "old response/defer cannot erase a newer explicit grant")

        // Delete is independently broker-authenticated and preserves both
        // encrypted file and key when that authentication is refused.
        store.setFailure(.authenticationDenied, for: .delete)
        _ = await failure { try await vault.deleteVault() }
        check(store.key(id) != nil && FileManager.default.fileExists(atPath: file.path), "denied delete preserves key and encrypted file")
        store.setFailure(nil, for: .delete)
        try await vault.deleteVault()
        check(store.key(id) == nil && !FileManager.default.fileExists(atPath: file.path), "authorized delete removes only selected synthetic vault")
        check(await vault.status() == .locked, "delete revokes volatile authorization")

        // A storage failure rolls back only the exact newly-created key, on
        // the same connection that holds its single-use creation receipt.
        let blocked = root.appendingPathComponent("regular-file-parent")
        try Data("preserve-this-synthetic-file".utf8).write(to: blocked)
        let rollbackStore = SyntheticMasterKeyStore(), rollbackID = UUID(), unrelated = UUID()
        rollbackStore.seed(unrelated, key: Data(repeating: 29, count: 32))
        let rollbackVault = try FaceUnlockVault(directory: blocked, vaultID: rollbackID, brokerFactory: { rollbackStore.connect() })
        await rollbackVault.updateDesktopState(isActive: true, isUnlocked: true)
        _ = await failure { try await rollbackVault.setup(initialManifest: .empty, credentialData: nil, reason: "Synthetic rollback") }
        check(rollbackStore.key(rollbackID) == nil && rollbackStore.key(unrelated) != nil && rollbackStore.sameConnectionRollback(),
              "failed setup rolls back only its own new item on the creating connection")
        let malformedStore = SyntheticMasterKeyStore(), malformedID = UUID()
        malformedStore.setCreateOverride(Data(repeating: 31, count: 31))
        let malformedVault = try FaceUnlockVault(directory: root.appendingPathComponent("malformed"), vaultID: malformedID, brokerFactory: { malformedStore.connect() })
        await malformedVault.updateDesktopState(isActive: true, isUnlocked: true)
        _ = await failure { try await malformedVault.setup(initialManifest: .empty, credentialData: nil, reason: "Synthetic malformed create") }
        check(malformedStore.key(malformedID) == nil && malformedStore.count(.rollback) == 1, "invalid create reply cannot leave a committed vault")
        let cancelledCreateStore = SyntheticMasterKeyStore(), cancelledCreateID = UUID()
        let cancelledCreateDirectory = root.appendingPathComponent("cancelled-create")
        let cancelledCreateVault = try FaceUnlockVault(directory: cancelledCreateDirectory, vaultID: cancelledCreateID,
            brokerFactory: { cancelledCreateStore.connect() })
        await cancelledCreateVault.updateDesktopState(isActive: true, isUnlocked: true)
        cancelledCreateStore.cancelNextCreate()
        let cancelledCreateTask = Task {
            try await cancelledCreateVault.setup(initialManifest: .empty, credentialData: nil, reason: "Synthetic cancelled create")
        }
        _ = await failure { try await cancelledCreateTask.value }
        check(cancelledCreateStore.key(cancelledCreateID) == nil && cancelledCreateStore.sameConnectionRollback()
            && !FileManager.default.fileExists(atPath: cancelledCreateDirectory.path),
              "canceled create with delivered receipt rolls back before any encrypted file is committed")
        let failedRollbackStore = SyntheticMasterKeyStore(), failedRollbackID = UUID()
        failedRollbackStore.setFailure(.systemFailure(.init(stage: .keychainDelete, domain: .osStatus,
            code: Int(errSecInteractionNotAllowed))), for: .rollback)
        let failedRollbackVault = try FaceUnlockVault(directory: blocked, vaultID: failedRollbackID,
            brokerFactory: { failedRollbackStore.connect() })
        await failedRollbackVault.updateDesktopState(isActive: true, isUnlocked: true)
        let failedRollback = await failure {
            try await failedRollbackVault.setup(initialManifest: .empty, credentialData: nil, reason: "Synthetic failed rollback")
        }
        if case .systemFailure(let details) = failedRollback {
            check(details.stage == .encryptedWrite && details.rollbackStatus == errSecInteractionNotAllowed,
                  "failed rollback preserves original write stage and numeric cleanup outcome")
        } else { preconditionFailure("expected preserved rollback failure") }
        check(failedRollbackStore.key(failedRollbackID) != nil && failedRollbackStore.count(.delete) == 0,
              "uncertain cleanup retains exact item for explicit recovery rather than guessing or deleting broadly")

        // Lost create reply retains the exact item. Recovery is separate,
        // freshly authenticated, empty, and cannot overwrite an existing file.
        let orphanStore = SyntheticMasterKeyStore(), orphanID = UUID(), orphanDirectory = root.appendingPathComponent("orphan")
        let orphanFile = orphanDirectory.appendingPathComponent(orphanID.uuidString).appendingPathExtension("vault")
        let orphanVault = try FaceUnlockVault(directory: orphanDirectory, vaultID: orphanID, brokerFactory: { orphanStore.connect() })
        await orphanVault.updateDesktopState(isActive: true, isUnlocked: true)
        orphanStore.setLostCreateReply(true)
        _ = await failure { try await orphanVault.setup(initialManifest: manifest, credentialData: credential, reason: "Synthetic lost reply") }
        let retainedKey = orphanStore.key(orphanID)
        check(retainedKey != nil && !FileManager.default.fileExists(atPath: orphanFile.path), "lost reply does not guess that creation failed or delete an unknown item")
        orphanStore.setLostCreateReply(false)
        let recoveryNeeded = await failure { try await orphanVault.setup(initialManifest: manifest, credentialData: credential, reason: "Synthetic duplicate retry") }
        if case .unfinishedSetup = recoveryNeeded { check(true, "duplicate plus absent envelope exposes explicit recovery") }
        else { preconditionFailure("expected explicit unfinished setup state") }
        check(orphanStore.count(.read) == 0 && orphanStore.key(orphanID) == retainedKey, "retry does not silently adopt or overwrite the orphan key")
        try await orphanVault.recoverUnfinishedSetup(reason: "Synthetic explicit recovery")
        check(orphanStore.count(.read) == 1 && orphanStore.key(orphanID) == retainedKey && orphanStore.count(.delete) == 0,
              "recovery uses fresh exact-key read without deletion/replacement")
        check(await orphanVault.status() == .locked, "recovery never silently enables Face Unlock")
        try await orphanVault.authorizeUnlockedSession(reason: "Inspect synthetic recovery")
        let recoveredManifest = try await orphanVault.manifest(), recoveredCredential = try await orphanVault.hasCredential()
        check(recoveredManifest == .empty && !recoveredCredential, "recovery is explicitly empty, not fabricated enrollment/credential restoration")
        let recoveredBytes = try Data(contentsOf: orphanFile)
        _ = await failure { try await orphanVault.recoverUnfinishedSetup(reason: "Refuse existing synthetic envelope") }
        check(try Data(contentsOf: orphanFile) == recoveredBytes && orphanStore.key(orphanID) == retainedKey, "recovery never overwrites existing encrypted storage")
        _ = await failure { try FaceVaultEncryptedFileStore.create(Data("different encrypted fixture".utf8), to: orphanFile, directory: orphanDirectory) }
        check(try Data(contentsOf: orphanFile) == recoveredBytes, "exclusive file installation also defeats a post-auth creation race")
        let raceStore = SyntheticMasterKeyStore(), raceID = UUID(), raceDirectory = root.appendingPathComponent("recovery-race")
        let raceFile = raceDirectory.appendingPathComponent(raceID.uuidString).appendingPathExtension("vault")
        let raceKey = Data(repeating: 41, count: 32)
        raceStore.seed(raceID, key: raceKey)
        let raceVault = try FaceUnlockVault(directory: raceDirectory, vaultID: raceID, brokerFactory: { raceStore.connect() })
        let competing = try FaceVaultCipher.seal(FaceVaultContents(manifest: manifest, credentialData: credential)!,
            key: SymmetricKey(data: raceKey), vaultID: raceID, ownerUserID: getuid())
        await raceVault.updateDesktopState(isActive: true, isUnlocked: true)
        raceStore.setHook(.read) { try! FaceVaultEncryptedFileStore.create(competing, to: raceFile, directory: raceDirectory) }
        _ = await failure { try await raceVault.recoverUnfinishedSetup(reason: "Synthetic recovery race") }
        check(try Data(contentsOf: raceFile) == competing && raceStore.key(raceID) == raceKey,
              "recovery refuses a file that appears during auth and preserves existing faces/credential")

        // Actual client state machine against a fake wire: one connection,
        // no hidden reconnect, finite requests, cancellation and duplicate reply.
        let factory = SyntheticWireFactory()
        let client = FaceVaultKeyBrokerClient(connectionFactory: { factory.connect($0, $1) })
        check(factory.count() == 0, "client construction never starts XPC")
        try await client.checkAvailability()
        let created = try await client.createMasterKey(vaultID: UUID(), reason: "Synthetic wire")
        try await client.rollbackCreatedMasterKey(vaultID: UUID(), receipt: created.receipt)
        check(factory.count() == 1 && factory.latest().counts().0 == 1, "availability/create/receipt calls share one explicitly resumed connection")
        client.invalidate()
        _ = await failure { _ = try await client.readMasterKey(vaultID: UUID(), reason: "Refuse reconnect") }
        check(factory.count() == 1, "invalidated clients never reconnect implicitly")

        let busyFactory = SyntheticWireFactory(); busyFactory.wire.deferRead = true
        let busyClient = FaceVaultKeyBrokerClient(connectionFactory: { busyFactory.connect($0, $1) })
        let firstRead = Task { try await busyClient.readMasterKey(vaultID: UUID(), reason: "Pending synthetic read") }
        await busyFactory.wire.readSignal.wait()
        _ = await failure { _ = try await busyClient.readMasterKey(vaultID: UUID(), reason: "Refuse overlapping read") }
        busyFactory.wire.replyToRead(repeatReply: true)
        check(try await firstRead.value.count == 32, "busy refusal and duplicate callback cannot cancel/resume the wrong request")
        busyClient.invalidate()

        for interrupt in [false, true] {
            let pendingFactory = SyntheticWireFactory(); pendingFactory.wire.deferRead = true
            let pendingClient = FaceVaultKeyBrokerClient(connectionFactory: { pendingFactory.connect($0, $1) })
            let pendingTask = Task { try await pendingClient.readMasterKey(vaultID: UUID(), reason: "Synthetic interruption") }
            await pendingFactory.wire.readSignal.wait()
            if interrupt { pendingFactory.latest().interrupt() } else { pendingTask.cancel() }
            _ = await failure { _ = try await pendingTask.value }
            pendingFactory.wire.replyToRead(repeatReply: true)
            _ = await failure { try await pendingClient.checkAvailability() }
            check(pendingFactory.count() == 1, "cancel/interruption reject late replies and forbid reconnect")
        }
        let failedFactory = SyntheticWireFactory(); failedFactory.wire.deferRead = true
        let failedClient = FaceVaultKeyBrokerClient(connectionFactory: { failedFactory.connect($0, $1) })
        let failedTask = Task { try await failedClient.readMasterKey(vaultID: UUID(), reason: "Synthetic proxy failure") }
        await failedFactory.wire.readSignal.wait()
        failedFactory.latest().failProxy()
        _ = await failure { _ = try await failedTask.value }
        _ = await failure { try await failedClient.checkAvailability() }
        check(failedFactory.count() == 1, "proxy error invalidates the channel instead of reusing an uncertain connection")
        let timeoutFactory = SyntheticWireFactory(); timeoutFactory.wire.deferRead = true
        let timedClient = FaceVaultKeyBrokerClient(requestTimeout: .milliseconds(20), connectionFactory: { timeoutFactory.connect($0, $1) })
        let timed = await failure { _ = try await timedClient.readMasterKey(vaultID: UUID(), reason: "Synthetic timeout") }
        if case .systemFailure(let details) = timed { check(details.domain == .posix && details.code == Int(ETIMEDOUT), "client request timeout is finite and explicit") }
        else { preconditionFailure("expected bounded synthetic timeout") }
        timeoutFactory.wire.replyToRead()
        check(timeoutFactory.count() == 1 && timeoutFactory.latest().counts().1 == 1, "timeout invalidates without hidden retry")
        print("PASS \(checks) vault/client integration checks (synthetic transports/files only; no XPC/auth/Keychain/camera)")
    }
}
