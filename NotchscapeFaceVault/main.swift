import Foundation
import OSLog

final class FaceVaultListenerDelegate: NSObject, NSXPCListenerDelegate {
    private static let logger = Logger(subsystem: FaceVaultBrokerIdentity.serviceName, category: "availability")
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // .service listeners cannot use the listener-wide requirement setter.
        // This public connection API authenticates every incoming message.
        connection.setCodeSigningRequirement(FaceVaultBrokerIdentity.mainAppCodeRequirement)
        do {
            try FaceVaultBrokerPeerVerifier.validateOwnConfiguration()
            let verifier = try FaceVaultBrokerPeerVerifier(connection: connection)
            let service = FaceVaultBrokerService(verifier: verifier)
            connection.exportedInterface = NSXPCInterface(with: FaceVaultKeyBrokerProtocol.self)
            connection.exportedObject = service
            // The service holds only a weak connection reference, so retaining
            // it here is acyclic and guarantees cancellation even if Foundation
            // releases exportedObject before invoking the invalidation block.
            connection.invalidationHandler = { service.invalidate() }
            connection.interruptionHandler = { service.invalidate() }
            connection.activate()
            Self.logger.info("listener accepted after complete peer/config validation")
            return true
        } catch {
            let failure = error as? FaceVaultBrokerFailure ?? .init(code: .configurationInvalid, stage: .configuration)
            Self.logger.error("listener refused point=\(failure.point.rawValue, privacy: .public) stage=\(failure.stage.rawValue, privacy: .public) code=\(failure.code.rawValue, privacy: .public) status=\(failure.status ?? failure.diagnosticStatus ?? 0, privacy: .public)")
            connection.invalidate(); return false
        }
    }
}

let delegate = FaceVaultListenerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
