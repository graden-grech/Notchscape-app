@preconcurrency import Foundation
@preconcurrency import Security
@preconcurrency import LocalAuthentication

private enum FaceVaultBrokerClock {
    static let clock = ContinuousClock()
    static let origin = clock.now
    static var now: Double {
        let elapsed = origin.duration(to: clock.now).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }
}

/// Context configuration/evaluation/query use is serialized by its owning
/// worker. Only cancellation may invalidate concurrently. Never expose the
/// context or an auth boolean as a caller-controlled Keychain authorization.
private final class FaceVaultBrokerAuthentication: @unchecked Sendable {
    let access: SecAccessControl
    private let context = LAContext()
    private let lock = NSLock()
    private var cancelled = false

    init() throws {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence, &error) else { throw FaceVaultBrokerFailure(code: .configurationInvalid, stage: .acl) }
        self.access = access
        context.touchIDAuthenticationAllowableReuseDuration = 0
    }

    func evaluate(reason: String, creating: Bool) async throws {
        var availability: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availability) else {
            throw FaceVaultBrokerFailure(code: .authenticationUnavailable, stage: .auth)
        }
        let accepted: Bool
        do {
            // .createItem authorizes ACL creation; it is not proof of fresh
            // user presence. Every key operation first evaluates the owner's
            // real system policy using this new, helper-owned context.
            let ownerAccepted: Bool = try await withCheckedThrowingContinuation { continuation in
                context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { accepted, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: accepted) }
                }
            }
            guard ownerAccepted else { throw FaceVaultBrokerFailure(code: .authenticationDenied, stage: .auth) }
            accepted = try await withCheckedThrowingContinuation { continuation in
                context.evaluateAccessControl(access, operation: creating ? .createItem : .useItem,
                    localizedReason: reason) { accepted, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: accepted) }
                }
            }
        } catch {
            let value = error as NSError
            let wasCancelled = value.domain == LAError.errorDomain &&
                [LAError.userCancel.rawValue, LAError.appCancel.rawValue, LAError.systemCancel.rawValue].contains(value.code)
            throw FaceVaultBrokerFailure(code: wasCancelled ? .cancelled : .authenticationDenied, stage: .auth)
        }
        guard accepted else { throw FaceVaultBrokerFailure(code: .authenticationDenied, stage: .auth) }
    }

    func noninteractiveContext() -> LAContext { context.interactionNotAllowed = true; return context }
    func invalidate() {
        lock.lock(); let shouldInvalidate = !cancelled; cancelled = true; lock.unlock()
        if shouldInvalidate { context.invalidate() }
    }
    deinit { invalidate() }
}

private actor FaceVaultBrokerWorker {
    private let verifier: FaceVaultBrokerPeerVerifier
    private var invalidated = false
    private var busy = false
    private var epoch = UUID()
    private var authentication: FaceVaultBrokerAuthentication?
    private var creation: (FaceVaultBrokerCreationReceipt, FaceVaultBrokerAuthentication, Data)?
    private var receiptTimeout: Task<Void, Never>?

    init(verifier: FaceVaultBrokerPeerVerifier) { self.verifier = verifier }

    func invalidate() {
        invalidated = true; epoch = UUID()
        authentication?.invalidate(); authentication = nil
        clearReceipt()
    }

    private func begin(reason: String) throws -> UUID {
        guard !invalidated else { throw FaceVaultBrokerFailure(code: .cancelled, stage: .auth) }
        guard !busy else { throw FaceVaultBrokerFailure(code: .busy, stage: .auth) }
        guard FaceVaultBrokerPolicy.validReason(reason) else { throw FaceVaultBrokerFailure(code: .invalidRequest, stage: .auth) }
        try validate()
        clearReceipt()
        busy = true
        return epoch
    }

    private func validate(epoch expected: UUID? = nil) throws {
        guard !invalidated, expected.map({ $0 == epoch }) ?? true else {
            throw FaceVaultBrokerFailure(code: .cancelled, stage: .auth)
        }
        try verifier.validate()
        try FaceVaultBrokerPeerVerifier.validateOwnConfiguration()
    }

    private func authenticate(reason: String, creating: Bool, epoch: UUID) async throws -> FaceVaultBrokerAuthentication {
        let attempt = try FaceVaultBrokerAuthentication()
        authentication = attempt
        do {
            try await attempt.evaluate(reason: reason, creating: creating)
            try validate(epoch: epoch)
            return attempt
        } catch { attempt.invalidate(); throw error }
    }

    private func finish() {
        authentication?.invalidate(); authentication = nil; busy = false
    }

    func create(vaultID: UUID, reason: String) async throws -> (Data, UUID) {
        let token = try begin(reason: reason)
        defer { finish() }
        let attempt = try await authenticate(reason: reason, creating: true, epoch: token)
        var raw = Data(count: FaceVaultBrokerPolicy.keyBytes)
        defer { raw.resetBytes(in: 0..<raw.count) }
        let random = raw.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
        guard random == errSecSuccess else { throw FaceVaultBrokerFailure(code: .storageFailure, stage: .keyCreate, status: random) }
        var query = baseQuery(vaultID)
        query[kSecAttrAccessControl as String] = attempt.access
        query[kSecValueData as String] = raw
        query[kSecReturnPersistentRef as String] = true
        query[kSecUseAuthenticationContext as String] = attempt.noninteractiveContext()
        try validate(epoch: token)
        var addedItem: CFTypeRef?
        let status = SecItemAdd(query as CFDictionary, &addedItem)
        guard status == errSecSuccess else {
            throw FaceVaultBrokerFailure(code: status == errSecDuplicateItem ? .alreadyExists : .storageFailure,
                stage: .keyCreate, status: status)
        }
        guard let persistentReference = addedItem as? Data, (1...4096).contains(persistentReference.count) else {
            throw FaceVaultBrokerFailure(code: .storageFailure, stage: .keyCreate)
        }
        // A lost reply can leave this exact item orphaned. Never overwrite or
        // automatically delete it: main may have successfully written its file.
        // Explicit recovery reads this exact item with fresh user presence.
        try validate(epoch: token)
        let receipt = FaceVaultBrokerCreationReceipt(id: UUID(), vaultID: vaultID,
            peer: verifier.acceptedPeer, createdAt: FaceVaultBrokerClock.now)
        creation = (receipt, attempt, persistentReference)
        authentication = nil // retain only for the bounded rollback capability
        receiptTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(FaceVaultBrokerPolicy.receiptLifetime)) } catch { return }
            await self?.expireReceipt(receipt.id)
        }
        return (raw, receipt.id)
    }

    func read(vaultID: UUID, reason: String) async throws -> Data {
        let token = try begin(reason: reason)
        defer { finish() }
        let attempt = try await authenticate(reason: reason, creating: false, epoch: token)
        var query = baseQuery(vaultID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = attempt.noninteractiveContext()
        try validate(epoch: token)
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        guard status == errSecSuccess else {
            throw FaceVaultBrokerFailure(code: status == errSecItemNotFound ? .notFound : .storageFailure,
                stage: .keyRead, status: status)
        }
        guard var raw = value as? Data, raw.count == FaceVaultBrokerPolicy.keyBytes else {
            throw FaceVaultBrokerFailure(code: .storageFailure, stage: .keyRead)
        }
        defer { raw.resetBytes(in: 0..<raw.count) }
        try validate(epoch: token)
        return raw
    }

    func delete(vaultID: UUID, reason: String) async throws {
        let token = try begin(reason: reason)
        defer { finish() }
        let attempt = try await authenticate(reason: reason, creating: false, epoch: token)
        var query = baseQuery(vaultID)
        query[kSecUseAuthenticationContext as String] = attempt.noninteractiveContext()
        try validate(epoch: token)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else {
            throw FaceVaultBrokerFailure(code: status == errSecItemNotFound ? .notFound : .storageFailure,
                stage: .keyDelete, status: status)
        }
        try validate(epoch: token)
    }

    func rollback(vaultID: UUID, receipt id: UUID) throws {
        guard !busy else { throw FaceVaultBrokerFailure(code: .busy, stage: .rollback) }
        try validate()
        guard let pending = creation else {
            throw FaceVaultBrokerFailure(code: .invalidReceipt, stage: .rollback)
        }
        var receipt = pending.0
        let attempt = pending.1
        guard receipt.consume(id: id, vaultID: vaultID, peer: verifier.acceptedPeer, now: FaceVaultBrokerClock.now) else {
            throw FaceVaultBrokerFailure(code: .invalidReceipt, stage: .rollback)
        }
        creation = nil; receiptTimeout?.cancel(); receiptTimeout = nil
        defer { attempt.invalidate() }
        var query = baseQuery(vaultID)
        // Bind rollback to this SecItemAdd result, so an old receipt cannot
        // delete a separately authenticated replacement at the same account.
        query[kSecValuePersistentRef as String] = pending.2
        query[kSecUseAuthenticationContext as String] = attempt.noninteractiveContext()
        // No fallback prompt, broad query or retry if this authorization cannot
        // delete the exact item. A failure needs an explicit fresh-auth action.
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else {
            throw FaceVaultBrokerFailure(code: .storageFailure, stage: .rollback, status: status)
        }
    }

    private func baseQuery(_ vaultID: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.notchscape.face-vault.masterkey.v1",
         kSecAttrAccount as String: "\(verifier.acceptedPeer.userID).\(vaultID.uuidString.lowercased())",
         kSecAttrAccessGroup as String: FaceVaultBrokerPeerVerifier.accessGroup,
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: false]
    }

    private func clearReceipt() {
        receiptTimeout?.cancel(); receiptTimeout = nil
        creation?.1.invalidate(); creation = nil
    }
    private func expireReceipt(_ id: UUID) { if creation?.0.id == id { clearReceipt() } }
    deinit { receiptTimeout?.cancel(); authentication?.invalidate(); creation?.1.invalidate() }
}

/// Foundation's reply blocks may be called from another queue. This wrapper
/// owns the one callback and never exposes it to more than one completion.
private final class FaceVaultBrokerReply<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var reply: ((Value) -> Void)?
    init(_ reply: @escaping (Value) -> Void) { self.reply = reply }
    func finish(_ value: Value) {
        lock.lock(); let callback = reply; reply = nil; lock.unlock()
        callback?(value)
    }
}

final class FaceVaultBrokerService: NSObject, FaceVaultKeyBrokerProtocol, @unchecked Sendable {
    private let verifier: FaceVaultBrokerPeerVerifier
    private let worker: FaceVaultBrokerWorker
    init(verifier: FaceVaultBrokerPeerVerifier) { self.verifier = verifier; worker = .init(verifier: verifier) }
    func invalidate() { Task { [worker] in await worker.invalidate() } }

    private func callerError() -> NSError? {
        guard verifier.isCurrentCaller() else { return FaceVaultBrokerFailure(code: .untrustedPeer, stage: .peerValidation).wireError }
        do { try verifier.validate(); try FaceVaultBrokerPeerVerifier.validateOwnConfiguration(); return nil }
        catch { return Self.failure(error).wireError }
    }
    private static func failure(_ error: Error) -> FaceVaultBrokerFailure {
        error as? FaceVaultBrokerFailure ?? .init(code: .storageFailure, stage: .configuration)
    }

    func checkAvailability(withReply reply: @escaping (NSError?) -> Void) { reply(callerError()) }

    func createMasterKey(vaultID: NSUUID, reason: String, withReply reply: @escaping (Data?, NSUUID?, NSError?) -> Void) {
        if let error = callerError() { reply(nil, nil, error); return }
        let callback = FaceVaultBrokerReply<(Data?, NSUUID?, NSError?)> { reply($0.0, $0.1, $0.2) }
        let id = vaultID as UUID
        Task { [worker] in
            do { let (key, receipt) = try await worker.create(vaultID: id, reason: reason); callback.finish((key, receipt as NSUUID, nil)) }
            catch { callback.finish((nil, nil, Self.failure(error).wireError)) }
        }
    }
    func readMasterKey(vaultID: NSUUID, reason: String, withReply reply: @escaping (Data?, NSError?) -> Void) {
        if let error = callerError() { reply(nil, error); return }
        let callback = FaceVaultBrokerReply<(Data?, NSError?)> { reply($0.0, $0.1) }
        let id = vaultID as UUID
        Task { [worker] in
            do { callback.finish((try await worker.read(vaultID: id, reason: reason), nil)) }
            catch { callback.finish((nil, Self.failure(error).wireError)) }
        }
    }
    func deleteMasterKey(vaultID: NSUUID, reason: String, withReply reply: @escaping (NSError?) -> Void) {
        if let error = callerError() { reply(error); return }
        let callback = FaceVaultBrokerReply<NSError?>(reply)
        let id = vaultID as UUID
        Task { [worker] in
            do { try await worker.delete(vaultID: id, reason: reason); callback.finish(nil) }
            catch { callback.finish(Self.failure(error).wireError) }
        }
    }
    func rollbackCreatedMasterKey(vaultID: NSUUID, receipt: NSUUID, withReply reply: @escaping (NSError?) -> Void) {
        if let error = callerError() { reply(error); return }
        let callback = FaceVaultBrokerReply<NSError?>(reply)
        let id = vaultID as UUID, token = receipt as UUID
        Task { [worker] in
            do { try await worker.rollback(vaultID: id, receipt: token); callback.finish(nil) }
            catch { callback.finish(Self.failure(error).wireError) }
        }
    }
}
