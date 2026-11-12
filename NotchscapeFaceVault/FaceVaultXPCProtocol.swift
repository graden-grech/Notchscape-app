import Foundation

/// Shared wire contract only. Neither importing this file nor creating a
/// connection performs authentication or accesses the Keychain.
@objc protocol FaceVaultKeyBrokerProtocol {
    func checkAvailability(withReply reply: @escaping (NSError?) -> Void)
    func createMasterKey(vaultID: NSUUID, reason: String,
        withReply reply: @escaping (Data?, NSUUID?, NSError?) -> Void)
    func readMasterKey(vaultID: NSUUID, reason: String,
        withReply reply: @escaping (Data?, NSError?) -> Void)
    func deleteMasterKey(vaultID: NSUUID, reason: String,
        withReply reply: @escaping (NSError?) -> Void)
    func rollbackCreatedMasterKey(vaultID: NSUUID, receipt: NSUUID,
        withReply reply: @escaping (NSError?) -> Void)
}

enum FaceVaultBrokerIdentity {
    static let serviceName = "com.graden-grech.Notchscape.FaceVault"
    static let teamIdentifier = "6H86CTRJCP"
    static let errorDomain = "app.notchscape.face-vault.broker"
    static let failureStageKey = "failureStage"
    static let osStatusKey = "osStatus"
    static let mainAppCodeRequirement = "identifier \"theboringteam.boringnotch\" and anchor apple generic and certificate leaf[subject.CN] = \"Apple Development: grechgraden@icloud.com (P45575RL23)\" and certificate leaf[subject.OU] = \"6H86CTRJCP\" and certificate 1[field.1.2.840.113635.100.6.2.1]"
    static let brokerCodeRequirement = "identifier \"com.graden-grech.Notchscape.FaceVault\" and anchor apple generic and certificate leaf[subject.CN] = \"Apple Development: grechgraden@icloud.com (P45575RL23)\" and certificate leaf[subject.OU] = \"6H86CTRJCP\" and certificate 1[field.1.2.840.113635.100.6.2.1]"
}

enum FaceVaultBrokerFailureStage: String, Sendable {
    case acl, auth, keyCreate, keyRead, keyDelete, rollback, peerValidation, configuration
}

enum FaceVaultBrokerErrorCode: Int, Sendable {
    case invalidRequest = 1, untrustedPeer, authenticationUnavailable, authenticationDenied
    case cancelled, alreadyExists, notFound, storageFailure, invalidReceipt, busy, configurationInvalid
}
