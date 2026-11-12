import Foundation
import Security
import Darwin

struct FaceVaultCreatedMasterKey: Sendable, CustomDebugStringConvertible {
    let keyData: Data
    let receipt: UUID
    var debugDescription: String { "FaceVaultCreatedMasterKey(<redacted>)" }
}

/// Internal transport only. The vault owns authorization/session policy; the
/// separately provisioned broker owns every real Keychain/authentication call.
protocol FaceVaultKeyBrokerTransport: AnyObject, Sendable {
    func checkAvailability() async throws
    func createMasterKey(vaultID: UUID, reason: String) async throws -> FaceVaultCreatedMasterKey
    func readMasterKey(vaultID: UUID, reason: String) async throws -> Data
    func deleteMasterKey(vaultID: UUID, reason: String) async throws
    func rollbackCreatedMasterKey(vaultID: UUID, receipt: UUID) async throws
    func invalidate()
}

/// The production adapter alone constructs NSXPCConnection. Synthetic tests can
/// exercise client cancellation/error/reply routing without launching a service.
protocol FaceVaultBrokerConnectionTransport: AnyObject, Sendable {
    func resume()
    func invalidate()
    func proxy(errorHandler: @escaping @Sendable (any Error) -> Void) -> FaceVaultKeyBrokerProtocol?
}

private final class FaceVaultXPCConnectionTransport: FaceVaultBrokerConnectionTransport, @unchecked Sendable {
    private let connection: NSXPCConnection

    init(invalidated: @escaping @Sendable () -> Void, interrupted: @escaping @Sendable () -> Void) {
        connection = NSXPCConnection(serviceName: FaceVaultBrokerIdentity.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: FaceVaultKeyBrokerProtocol.self)
        connection.setCodeSigningRequirement(FaceVaultBrokerIdentity.brokerCodeRequirement)
        connection.invalidationHandler = invalidated
        connection.interruptionHandler = interrupted
    }

    func resume() { connection.resume() }
    func invalidate() { connection.invalidate() }
    func proxy(errorHandler: @escaping @Sendable (any Error) -> Void) -> FaceVaultKeyBrokerProtocol? {
        connection.remoteObjectProxyWithErrorHandler(errorHandler) as? FaceVaultKeyBrokerProtocol
    }
}

/// Pure reply validation/error translation. No arbitrary NSError content crosses
/// into diagnostics, and a malformed key/receipt never authorizes the vault.
enum FaceVaultBrokerReplyPolicy {
    static func failure(_ error: NSError, stage: FaceVaultFailureStage) -> FaceVaultError {
        guard error.domain == FaceVaultBrokerIdentity.errorDomain,
              let code = FaceVaultBrokerErrorCode(rawValue: error.code) else {
            return .systemFailure(.capturing(error, stage: stage))
        }
        switch code {
        case .invalidRequest: return .invalidInput
        case .authenticationUnavailable: return .authenticationUnavailable
        case .authenticationDenied: return .authenticationDenied
        case .cancelled: return .cancelled
        case .alreadyExists: return .alreadyExists
        case .notFound: return .notFound
        case .untrustedPeer, .storageFailure, .invalidReceipt, .busy, .configurationInvalid:
            let safeStage: FaceVaultFailureStage
            switch error.userInfo[FaceVaultBrokerIdentity.failureStageKey] as? String {
            case "acl": safeStage = .accessControlCreation
            case "auth": safeStage = .authenticationEvaluation
            case "keyCreate": safeStage = .keychainCreate
            case "keyRead": safeStage = .keychainRead
            case "keyDelete", "rollback": safeStage = .keychainDelete
            case "peerValidation", "configuration": safeStage = .brokerConnection
            default: safeStage = stage
            }
            if let numeric = error.userInfo[FaceVaultBrokerIdentity.osStatusKey] as? NSNumber,
               CFGetTypeID(numeric) != CFBooleanGetTypeID(),
               let status = Int32(exactly: numeric.int64Value),
               numeric.doubleValue == Double(status) {
                return .systemFailure(.init(stage: safeStage, domain: .osStatus, code: Int(status)))
            }
            return .systemFailure(.init(stage: safeStage, domain: .broker, code: error.code))
        }
    }

    static func created(key: Data?, receipt: NSUUID?, error: NSError?) throws -> FaceVaultCreatedMasterKey {
        if let error { throw failure(error, stage: .keychainCreate) }
        guard let key, key.count == 32, let receipt else { throw FaceVaultError.invalidCiphertext }
        return .init(keyData: key, receipt: receipt as UUID)
    }

    static func read(key: Data?, error: NSError?) throws -> Data {
        if let error { throw failure(error, stage: .keychainRead) }
        guard let key, key.count == 32 else { throw FaceVaultError.invalidCiphertext }
        return key
    }
}

/// A one-shot checked continuation tolerates reply/error/cancel races. All state
/// is protected by this lock; continuation resume happens after releasing it.
private final class FaceVaultBrokerReply<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?
    private var result: Result<Value, FaceVaultError>?
    private var resolved = false

    var isResolved: Bool {
        lock.lock(); defer { lock.unlock() }
        return resolved
    }

    func attach(_ continuation: CheckedContinuation<Value, any Error>) {
        lock.lock()
        if let result {
            self.result = nil
            lock.unlock()
            continuation.resume(with: result.mapError { $0 as any Error })
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    @discardableResult func resolve(_ result: Result<Value, FaceVaultError>) -> Bool {
        lock.lock()
        guard !resolved else { lock.unlock(); return false }
        resolved = true
        let continuation = self.continuation
        self.continuation = nil
        if continuation == nil { self.result = result }
        lock.unlock()
        continuation?.resume(with: result.mapError { $0 as any Error })
        return true
    }
}

/// Construction is side-effect-free. An explicit request lazily connects to the
/// signed, provisioned service. One request at a time; no automatic reconnect or
/// fallback. A create receipt stays on this connection until write/rollback.
final class FaceVaultKeyBrokerClient: FaceVaultKeyBrokerTransport, @unchecked Sendable {
    private struct Pending {
        let id: UUID
        let fail: @Sendable (FaceVaultError) -> Void
    }
    private let lock = NSLock()
    private var connection: (any FaceVaultBrokerConnectionTransport)?
    private var connectionID: UUID?
    private var pending: Pending?
    private var timeout: Task<Void, Never>?
    private var invalidated = false
    private let connectionFactory: @Sendable (@escaping @Sendable () -> Void, @escaping @Sendable () -> Void) -> any FaceVaultBrokerConnectionTransport
    private let requestTimeout: Duration

    init(requestTimeout: Duration = .seconds(120),
         connectionFactory: @escaping @Sendable (@escaping @Sendable () -> Void, @escaping @Sendable () -> Void) -> any FaceVaultBrokerConnectionTransport = {
             FaceVaultXPCConnectionTransport(invalidated: $0, interrupted: $1)
         }) {
        self.requestTimeout = requestTimeout
        self.connectionFactory = connectionFactory
    }

    func checkAvailability() async throws {
        let _: Bool = try await perform(stage: .brokerConnection, timeout: min(requestTimeout, .seconds(10))) { proxy, finish in
            proxy.checkAvailability { error in
                if let error { finish(.failure(FaceVaultBrokerReplyPolicy.failure(error, stage: .brokerConnection))) }
                else { finish(.success(true)) }
            }
        }
    }

    func createMasterKey(vaultID: UUID, reason: String) async throws -> FaceVaultCreatedMasterKey {
        try await perform(stage: .keychainCreate) { proxy, finish in
            proxy.createMasterKey(vaultID: vaultID as NSUUID, reason: reason) { key, receipt, error in
                do { finish(.success(try FaceVaultBrokerReplyPolicy.created(key: key, receipt: receipt, error: error))) }
                catch let failure as FaceVaultError { finish(.failure(failure)) }
                catch { finish(.failure(.invalidCiphertext)) }
            }
        }
    }

    func readMasterKey(vaultID: UUID, reason: String) async throws -> Data {
        try await perform(stage: .keychainRead) { proxy, finish in
            proxy.readMasterKey(vaultID: vaultID as NSUUID, reason: reason) { key, error in
                do { finish(.success(try FaceVaultBrokerReplyPolicy.read(key: key, error: error))) }
                catch let failure as FaceVaultError { finish(.failure(failure)) }
                catch { finish(.failure(.invalidCiphertext)) }
            }
        }
    }

    func deleteMasterKey(vaultID: UUID, reason: String) async throws {
        let _: Bool = try await perform(stage: .keychainDelete) { proxy, finish in
            proxy.deleteMasterKey(vaultID: vaultID as NSUUID, reason: reason) { error in
                if let error { finish(.failure(FaceVaultBrokerReplyPolicy.failure(error, stage: .keychainDelete))) }
                else { finish(.success(true)) }
            }
        }
    }

    func rollbackCreatedMasterKey(vaultID: UUID, receipt: UUID) async throws {
        let _: Bool = try await perform(stage: .keychainDelete) { proxy, finish in
            proxy.rollbackCreatedMasterKey(vaultID: vaultID as NSUUID, receipt: receipt as NSUUID) { error in
                if let error { finish(.failure(FaceVaultBrokerReplyPolicy.failure(error, stage: .keychainDelete))) }
                else { finish(.success(true)) }
            }
        }
    }

    func invalidate() { disconnect(failure: .cancelled) }

    private func disconnect(failure: FaceVaultError, matching id: UUID? = nil) {
        lock.lock()
        if let id, connectionID != id { lock.unlock(); return }
        invalidated = true
        let connection = self.connection
        let pending = self.pending
        let timeout = self.timeout
        self.connection = nil; connectionID = nil; self.pending = nil; self.timeout = nil
        lock.unlock()
        timeout?.cancel()
        connection?.invalidate()
        pending?.fail(failure)
    }

    private func finishRequest(_ id: UUID) {
        lock.lock()
        guard pending?.id == id else { lock.unlock(); return }
        let timeout = self.timeout
        pending = nil; self.timeout = nil
        lock.unlock()
        timeout?.cancel()
    }

    private func prepare<Value: Sendable>(requestID: UUID, reply: FaceVaultBrokerReply<Value>, timeLimit: Duration) throws -> (any FaceVaultBrokerConnectionTransport, Bool) {
        lock.lock(); defer { lock.unlock() }
        guard !invalidated, !reply.isResolved else { throw FaceVaultError.cancelled }
        guard pending == nil else {
            throw FaceVaultError.systemFailure(.init(stage: .brokerConnection, domain: .broker,
                code: FaceVaultBrokerErrorCode.busy.rawValue))
        }
        var needsResume = false
        if connection == nil {
            let id = UUID()
            let newConnection = connectionFactory({ [weak self] in
                self?.disconnect(failure: .systemFailure(.init(stage: .brokerConnection, domain: .cocoa,
                    code: NSXPCConnectionInvalid)), matching: id)
            }, { [weak self] in
                self?.disconnect(failure: .systemFailure(.init(stage: .brokerConnection, domain: .cocoa,
                    code: NSXPCConnectionInterrupted)), matching: id)
            })
            connection = newConnection; connectionID = id; needsResume = true
        }
        guard let connection else { throw FaceVaultError.authenticationUnavailable }
        pending = .init(id: requestID, fail: { _ = reply.resolve(.failure($0)) })
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: timeLimit) } catch { return }
            guard reply.resolve(.failure(.systemFailure(.init(stage: .brokerConnection,
                domain: .posix, code: Int(ETIMEDOUT))))) else { return }
            self?.disconnect(failure: .cancelled)
        }
        return (connection, needsResume)
    }

    private func perform<Value: Sendable>(stage: FaceVaultFailureStage, timeout: Duration? = nil,
        invoke: (FaceVaultKeyBrokerProtocol, @escaping @Sendable (Result<Value, FaceVaultError>) -> Void) -> Void) async throws -> Value {
        let reply = FaceVaultBrokerReply<Value>()
        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                reply.attach(continuation)
                if Task.isCancelled { reply.resolve(.failure(.cancelled)); return }
                let finish: @Sendable (Result<Value, FaceVaultError>) -> Void = { [weak self] result in
                    self?.finishRequest(requestID)
                    reply.resolve(result)
                }
                do {
                    let (connection, needsResume) = try prepare(requestID: requestID, reply: reply, timeLimit: timeout ?? requestTimeout)
                    if needsResume { connection.resume() }
                    let object = connection.proxy { [weak self] error in
                        finish(.failure(.systemFailure(.capturing(error, stage: stage))))
                        self?.invalidate()
                    }
                    guard let proxy = object else {
                        finish(.failure(.authenticationUnavailable)); invalidate(); return
                    }
                    invoke(proxy, finish)
                } catch let failure as FaceVaultError { finish(.failure(failure)) }
                catch { finish(.failure(.systemFailure(.capturing(error, stage: stage)))) }
            }
        } onCancel: { [weak self] in
            reply.resolve(.failure(.cancelled))
            self?.invalidate()
        }
    }

    deinit { invalidate() }
}
