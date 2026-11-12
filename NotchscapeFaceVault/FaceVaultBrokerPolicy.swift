import Foundation

/// Fixed diagnostic labels only; never include peer/user/session identifiers.
enum FaceVaultBrokerValidationPoint: String, Sendable {
    case unknown, peerConnection, peerChanged, peerProcessHeader, peerProcessRead, peerProcessOwner
    case peerSessionLookup, peerConsoleLookup, peerUserPolicy, peerGroupPolicy, peerAuditPolicy
    case peerConsolePolicy, peerLockPolicy, peerGraphicalPolicy, peerRequirementParse, peerCodeLookup, peerCodeRequirement
    case ownCodeLookup, ownRequirementParse, ownCodeRequirement, ownStaticCodeLookup, ownSigningInformation
    case ownApplicationID, ownTeam, ownPrivateGroup, ownSandbox, ownDebugPrivilege, ownProfileExpiration, ownSessionConfiguration, lockMetadata
}

struct FaceVaultBrokerPeerIdentity: Equatable, Sendable {
    let processID: Int32
    let userID: UInt32
    let groupID: UInt32
    let auditSessionID: UInt32
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}

struct FaceVaultBrokerLocalSession: Sendable {
    let userID: UInt32
    let effectiveUserID: UInt32
    let groupID: UInt32
    let auditSessionID: UInt32
    let consoleUserID: UInt32?
    let onConsole: Bool?
    let loginComplete: Bool?
    let unlocked: Bool?
    let graphical: Bool
    let remote: Bool
    let root: Bool
}

enum FaceVaultBrokerPolicy {
    static let keyBytes = 32
    static let receiptLifetime = 30.0

    static func permits(_ peer: FaceVaultBrokerPeerIdentity, in session: FaceVaultBrokerLocalSession) -> Bool {
        peer.processID > 0 && peer.startSeconds > 0 && peer.startMicroseconds < 1_000_000 &&
        session.userID > 0 && session.userID == session.effectiveUserID &&
        peer.userID == session.userID && peer.groupID == session.groupID &&
        session.auditSessionID > 0 && session.auditSessionID < UInt32.max - 1 &&
        peer.auditSessionID == session.auditSessionID && session.consoleUserID == session.userID &&
        session.onConsole == true && session.loginComplete == true && session.unlocked != false &&
        session.graphical && !session.remote && !session.root
    }

    /// Called only after permits returns false. This classifies that refusal;
    /// it does not participate in authorization or change any policy predicate.
    static func refusalPoint(_ peer: FaceVaultBrokerPeerIdentity, in session: FaceVaultBrokerLocalSession) -> FaceVaultBrokerValidationPoint {
        if peer.processID <= 0 || peer.startSeconds == 0 || peer.startMicroseconds >= 1_000_000 { return .peerProcessHeader }
        if session.userID == 0 || session.userID != session.effectiveUserID || peer.userID != session.userID { return .peerUserPolicy }
        if peer.groupID != session.groupID { return .peerGroupPolicy }
        if session.auditSessionID == 0 || session.auditSessionID >= UInt32.max - 1 || peer.auditSessionID != session.auditSessionID { return .peerAuditPolicy }
        if session.consoleUserID != session.userID || session.onConsole != true || session.loginComplete != true { return .peerConsolePolicy }
        if session.unlocked == false { return .peerLockPolicy }
        return .peerGraphicalPolicy
    }

    static func validReason(_ reason: String) -> Bool {
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        reason.utf8.count <= 512 && reason.count <= 200 &&
        !reason.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    static func validExpiration(_ expiration: String, at now: Date) -> Bool {
        guard let date = ISO8601DateFormatter().date(from: expiration) else { return false }
        return now < date
    }
}

/// Bound to one accepted connection and one newly added item. Invalidating a
/// connection drops this receipt; it never implicitly deletes a Keychain item.
struct FaceVaultBrokerCreationReceipt: Sendable {
    let id: UUID
    let vaultID: UUID
    let peer: FaceVaultBrokerPeerIdentity
    let createdAt: TimeInterval
    private(set) var consumed = false

    mutating func consume(id: UUID, vaultID: UUID, peer: FaceVaultBrokerPeerIdentity, now: TimeInterval) -> Bool {
        guard !consumed, self.id == id, self.vaultID == vaultID, self.peer == peer,
              createdAt.isFinite, createdAt >= 0, now.isFinite, now >= createdAt,
              now - createdAt < FaceVaultBrokerPolicy.receiptLifetime else { return false }
        consumed = true
        return true
    }
}
