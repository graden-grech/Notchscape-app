@preconcurrency import Foundation
@preconcurrency import Security
import CoreGraphics
import Darwin

struct FaceVaultBrokerFailure: Error, Sendable {
    let code: FaceVaultBrokerErrorCode
    let stage: FaceVaultBrokerFailureStage
    var status: Int32? = nil
    var point: FaceVaultBrokerValidationPoint = .unknown
    var diagnosticStatus: Int32? = nil // non-Security numeric failures stay out of osStatus wire metadata

    var wireError: NSError {
        var metadata: [String: Any] = [FaceVaultBrokerIdentity.failureStageKey: stage.rawValue]
        if let status { metadata[FaceVaultBrokerIdentity.osStatusKey] = NSNumber(value: status) }
        return NSError(domain: FaceVaultBrokerIdentity.errorDomain, code: code.rawValue, userInfo: metadata)
    }
}

/// NSXPC's public per-message requirement authenticates the live sender, rather
/// than trusting a PID-only signature lookup. Public PID birth/session checks
/// additionally bind each operation and async completion to the accepted peer.
final class FaceVaultBrokerPeerVerifier: @unchecked Sendable {
    private weak var connection: NSXPCConnection?
    let acceptedPeer: FaceVaultBrokerPeerIdentity

    init(connection: NSXPCConnection) throws {
        self.connection = connection
        acceptedPeer = try Self.identity(connection)
        try validate()
    }

    func isCurrentCaller() -> Bool { NSXPCConnection.current() === connection }

    func validate() throws {
        guard let connection else {
            throw FaceVaultBrokerFailure(code: .untrustedPeer, stage: .peerValidation, point: .peerConnection)
        }
        guard try Self.identity(connection) == acceptedPeer else {
            throw FaceVaultBrokerFailure(code: .untrustedPeer, stage: .peerValidation, point: .peerChanged)
        }
        let session = try Self.localSession()
        guard FaceVaultBrokerPolicy.permits(acceptedPeer, in: session) else {
            throw FaceVaultBrokerFailure(code: .untrustedPeer, stage: .peerValidation,
                point: FaceVaultBrokerPolicy.refusalPoint(acceptedPeer, in: session))
        }
        var requirement: SecRequirement?
        var guest: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: acceptedPeer.processID)] as CFDictionary
        let parsed = SecRequirementCreateWithString(FaceVaultBrokerIdentity.mainAppCodeRequirement as CFString, [], &requirement)
        guard parsed == errSecSuccess, let requirement else {
            throw FaceVaultBrokerFailure(code: .untrustedPeer, stage: .peerValidation, status: parsed, point: .peerRequirementParse)
        }
        let copied = SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest)
        guard copied == errSecSuccess, let guest else {
            throw FaceVaultBrokerFailure(code: .untrustedPeer, stage: .peerValidation, status: copied, point: .peerCodeLookup)
        }
        let verified = SecCodeCheckValidity(guest, [], requirement)
        guard verified == errSecSuccess else {
            throw FaceVaultBrokerFailure(code: .untrustedPeer, stage: .peerValidation, status: verified, point: .peerCodeRequirement)
        }
        guard try Self.identity(connection) == acceptedPeer else {
            throw FaceVaultBrokerFailure(code: .untrustedPeer, stage: .peerValidation, point: .peerChanged)
        }
    }

    static func validateSessionConfiguration(_ value: Any?) throws {
        // XPC defaults to a new audit session. This app-private Keychain broker
        // must instead join its caller's session; the peer's exact audit ID,
        // console ownership and completed GUI login are still checked below.
        guard let configuration = value as? [String: Any],
              configuration["ServiceType"] as? String == "Application",
              let joined = configuration["JoinExistingSession"] as? NSNumber,
              CFGetTypeID(joined) == CFBooleanGetTypeID(), joined.boolValue else {
            throw FaceVaultBrokerFailure(code: .configurationInvalid, stage: .configuration, point: .ownSessionConfiguration)
        }
    }

    static func validateOwnConfiguration() throws {
        try validateSessionConfiguration(Bundle.main.object(forInfoDictionaryKey: "XPCService"))
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        var information: CFDictionary?
        func checked(_ status: OSStatus, at point: FaceVaultBrokerValidationPoint) throws {
            guard status == errSecSuccess else { throw FaceVaultBrokerFailure(code: .configurationInvalid, stage: .configuration, status: status, point: point) }
        }
        func require(_ condition: Bool, at point: FaceVaultBrokerValidationPoint) throws {
            guard condition else { throw FaceVaultBrokerFailure(code: .configurationInvalid, stage: .configuration, point: point) }
        }
        try checked(SecCodeCopySelf([], &code), at: .ownCodeLookup)
        guard let code else { throw FaceVaultBrokerFailure(code: .configurationInvalid, stage: .configuration, point: .ownCodeLookup) }
        try checked(SecRequirementCreateWithString(FaceVaultBrokerIdentity.brokerCodeRequirement as CFString, [], &requirement), at: .ownRequirementParse)
        guard let requirement else { throw FaceVaultBrokerFailure(code: .configurationInvalid, stage: .configuration, point: .ownRequirementParse) }
        try checked(SecCodeCheckValidity(code, [], requirement), at: .ownCodeRequirement)
        try checked(SecCodeCopyStaticCode(code, [], &staticCode), at: .ownStaticCodeLookup)
        guard let staticCode else { throw FaceVaultBrokerFailure(code: .configurationInvalid, stage: .configuration, point: .ownStaticCodeLookup) }
        try checked(SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information), at: .ownSigningInformation)
        guard let info = information as? [String: Any],
              let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else {
            throw FaceVaultBrokerFailure(code: .configurationInvalid, stage: .configuration, point: .ownSigningInformation)
        }
        try require(entitlements["com.apple.application-identifier"] as? String == accessGroup, at: .ownApplicationID)
        try require(entitlements["com.apple.developer.team-identifier"] as? String == FaceVaultBrokerIdentity.teamIdentifier, at: .ownTeam)
        try require(entitlements["keychain-access-groups"] as? [String] == [accessGroup], at: .ownPrivateGroup)
        try require(entitlements["com.apple.security.app-sandbox"] as? Bool == true, at: .ownSandbox)
        try require(entitlements["com.apple.security.get-task-allow"] as? Bool != true, at: .ownDebugPrivilege)
        guard let expiration = Bundle.main.object(forInfoDictionaryKey: "FaceVaultProfileExpiration") as? String,
              FaceVaultBrokerPolicy.validExpiration(expiration, at: Date()) else {
            throw FaceVaultBrokerFailure(code: .configurationInvalid, stage: .configuration, point: .ownProfileExpiration)
        }
    }

    static var accessGroup: String { FaceVaultBrokerIdentity.teamIdentifier + "." + FaceVaultBrokerIdentity.serviceName }

    static func lockState(in dictionary: [String: Any]) throws -> Bool? {
        guard let value = dictionary["CGSSessionScreenIsLocked"] else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw FaceVaultBrokerFailure(code: .untrustedPeer, stage: .peerValidation, point: .lockMetadata)
        }
        return number.boolValue
    }

    private static func identity(_ connection: NSXPCConnection) throws -> FaceVaultBrokerPeerIdentity {
        var process = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let pid = connection.processIdentifier
        guard pid > 0, connection.auditSessionIdentifier > 0 else {
            throw FaceVaultBrokerFailure(code: .untrustedPeer, stage: .peerValidation, point: .peerProcessHeader)
        }
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &process, size) == size else {
            throw FaceVaultBrokerFailure(code: .untrustedPeer, stage: .peerValidation,
                point: .peerProcessRead, diagnosticStatus: errno)
        }
        guard process.pbi_pid == UInt32(pid), process.pbi_uid == connection.effectiveUserIdentifier else {
            throw FaceVaultBrokerFailure(code: .untrustedPeer, stage: .peerValidation, point: .peerProcessOwner)
        }
        return .init(processID: pid, userID: connection.effectiveUserIdentifier,
            groupID: connection.effectiveGroupIdentifier, auditSessionID: UInt32(connection.auditSessionIdentifier),
            startSeconds: process.pbi_start_tvsec, startMicroseconds: process.pbi_start_tvusec)
    }

    private static func localSession() throws -> FaceVaultBrokerLocalSession {
        var identifier: SecuritySessionId = 0
        var attributes: SessionAttributeBits = []
        let status = SessionGetInfo(callerSecuritySession, &identifier, &attributes)
        guard status == errSessionSuccess else {
            throw FaceVaultBrokerFailure(code: .untrustedPeer, stage: .peerValidation, status: status, point: .peerSessionLookup)
        }
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            throw FaceVaultBrokerFailure(code: .untrustedPeer, stage: .peerValidation, point: .peerConsoleLookup)
        }
        func boolean(_ value: Any?) -> Bool? {
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
            return number.boolValue
        }
        let console = dictionary[kCGSessionUserIDKey as String] as? NSNumber
        let consoleID = console.flatMap { CFGetTypeID($0) != CFBooleanGetTypeID() ? UInt32(exactly: $0.int64Value) : nil }
        let locked = try lockState(in: dictionary)
        // The public dictionary normally omits this undocumented key while
        // unlocked. Explicit true refuses requests; absence is not asserted as
        // an unlock. The DP WhenUnlocked/userPresence ACL independently gates
        // every key operation. All owned local-session fields remain mandatory.
        return .init(userID: getuid(), effectiveUserID: geteuid(), groupID: getegid(), auditSessionID: identifier,
            consoleUserID: consoleID, onConsole: boolean(dictionary[kCGSessionOnConsoleKey as String]),
            loginComplete: boolean(dictionary[kCGSessionLoginDoneKey as String]), unlocked: locked.map { !$0 },
            graphical: attributes.contains(.sessionHasGraphicAccess), remote: attributes.contains(.sessionIsRemote),
            root: attributes.contains(.sessionIsRoot))
    }
}
