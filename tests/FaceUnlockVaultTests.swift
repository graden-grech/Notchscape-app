import Foundation
import CryptoKit
import Security
import LocalAuthentication

@main struct FaceUnlockVaultTests {
    static func main() async throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        func rejects(_ message: String, _ operation: () throws -> Void) {
            do { try operation(); preconditionFailure(message) } catch { checks += 1 }
        }
        func failsAt(_ stage: FaceVaultFailureStage, _ message: String, _ operation: () throws -> Void) {
            do { try operation(); preconditionFailure(message) }
            catch FaceVaultError.systemFailure(let details) {
                check(details.stage == stage, message)
            } catch { preconditionFailure("Failure stage was lost: \(message)") }
        }

        // Query/ACL construction is local only. No SecItem or authentication
        // evaluation is invoked anywhere in this suite.
        let queryID = UUID()
        let query = FaceVaultKeychainPolicy.baseQuery(vaultID: queryID, ownerUserID: 501)
        check(query[kSecUseDataProtectionKeychain as String] as? Bool == true, "always target the Data Protection Keychain")
        check(query[kSecAttrSynchronizable as String] as? Bool == false, "never opt in to iCloud synchronization")
        check(query[kSecClass as String] as? String == kSecClassGenericPassword as String, "master key uses a generic password item")
        check(query[kSecAttrService as String] as? String == "app.notchscape.face-vault.v1", "master key service remains stable")
        check(query[kSecAttrAccount as String] as? String == "501.\(queryID.uuidString)", "query binds the exact user and vault")
        check(query.count == 5 && query[kSecAttrAccessGroup as String] == nil, "use only the signed app's default access group")
        check(query[kSecValueData as String] == nil && query[kSecReturnData as String] == nil,
              "base query contains no value or broad data-return request")
        let otherUser = FaceVaultKeychainPolicy.baseQuery(vaultID: queryID, ownerUserID: 502)
        let otherVault = FaceVaultKeychainPolicy.baseQuery(vaultID: UUID(), ownerUserID: 501)
        check(otherUser[kSecAttrAccount as String] as? String != query[kSecAttrAccount as String] as? String,
              "another user's item is never selected")
        check(otherVault[kSecAttrAccount as String] as? String != query[kSecAttrAccount as String] as? String,
              "another vault's item is never selected")
        check(CFEqual(FaceVaultKeychainPolicy.accessibility, kSecAttrAccessibleWhenUnlockedThisDeviceOnly),
              "accessibility remains unlocked and device-only")
        check(FaceVaultKeychainPolicy.accessControlFlags == .userPresence,
              "user presence protection is not replaced by convenience authentication")
        let accessControl = try FaceVaultKeychainPolicy.makeAccessControl()
        check(CFGetTypeID(accessControl) == SecAccessControlGetTypeID(), "strict ACL constructs without Keychain or auth interaction")

        let privateFixture = "synthetic-secret-and-path-must-not-be-retained"
        let missingEntitlement = FaceVaultFailure.capturing(
            NSError(domain: NSOSStatusErrorDomain, code: Int(errSecMissingEntitlement),
                userInfo: [NSLocalizedDescriptionKey: privateFixture, NSFilePathErrorKey: privateFixture]),
            stage: .keychainCreate)
        check(missingEntitlement.isMissingEntitlement, "missing signing entitlement remains distinguishable")
        check(missingEntitlement.diagnosticCode == "keychainCreate:OSStatus:-34018", "safe numeric diagnostic names the failed stage")
        check(!String(reflecting: missingEntitlement).contains(privateFixture), "diagnostics do not retain localized text or paths")
        let denied = FaceVaultFailure.capturing(
            NSError(domain: LAError.errorDomain, code: LAError.Code.userCancel.rawValue,
                userInfo: [NSLocalizedDescriptionKey: privateFixture]), stage: .authenticationEvaluation)
        check(denied.domain == .localAuthentication && denied.code == LAError.Code.userCancel.rawValue,
              "system authentication code survives without the error payload")
        check(!denied.isMissingEntitlement, "authentication cancellation cannot look like a signing failure")
        let unknown = FaceVaultFailure.capturing(NSError(domain: privateFixture, code: 73,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: privateFixture, code: 74)]), stage: .encryptedWrite)
        check(unknown.domain == .system && unknown.code == 73 && !String(reflecting: unknown).contains(privateFixture),
              "unknown domains and nested error payloads are not retained")
        let wrapped = FaceVaultFailure.capturing(FaceVaultError.systemFailure(missingEntitlement),
            stage: .encryptedWrite, rollbackStatus: errSecInteractionNotAllowed)
        check(wrapped.stage == .keychainCreate && wrapped.domain == .osStatus && wrapped.code == Int(errSecMissingEntitlement),
              "nested handlers preserve the original failed stage")
        check(wrapped.rollbackStatus == errSecInteractionNotAllowed
            && wrapped.diagnosticCode.hasSuffix(";rollback:OSStatus:-25308"), "failed rollback status is visible without replacing the original failure")
        let cocoa = FaceVaultFailure.capturing(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError), stage: .encryptedWrite)
        let posix = FaceVaultFailure.capturing(NSError(domain: NSPOSIXErrorDomain, code: 13), stage: .encryptedRead)
        check(cocoa.domain == .cocoa && posix.domain == .posix, "file failures retain allowlisted numeric domains")
        let brokerError = NSError(domain: FaceVaultBrokerIdentity.errorDomain,
            code: FaceVaultBrokerErrorCode.storageFailure.rawValue,
            userInfo: [FaceVaultBrokerIdentity.failureStageKey: "keyCreate",
                FaceVaultBrokerIdentity.osStatusKey: NSNumber(value: errSecMissingEntitlement),
                NSLocalizedDescriptionKey: privateFixture])
        if case .systemFailure(let failure) = FaceVaultBrokerReplyPolicy.failure(brokerError, stage: .brokerConnection) {
            check(failure.stage == .keychainCreate && failure.isMissingEntitlement,
                  "broker preserves only allowlisted numeric Keychain failure details")
            check(!String(reflecting: failure).contains(privateFixture), "broker descriptions are never retained")
        } else { preconditionFailure("broker lost the Keychain failure stage") }
        let syntheticMasterKey = Data(repeating: 7, count: 32)
        let createdMasterKey = try FaceVaultBrokerReplyPolicy.created(key: syntheticMasterKey, receipt: NSUUID(), error: nil)
        check(createdMasterKey.keyData == syntheticMasterKey, "valid synthetic broker key/receipt decoded")
        check(!String(reflecting: createdMasterKey).contains(syntheticMasterKey.base64EncodedString()),
              "broker key debug output is redacted")
        rejects("missing creation receipt fails closed") {
            _ = try FaceVaultBrokerReplyPolicy.created(key: syntheticMasterKey, receipt: nil, error: nil)
        }
        rejects("wrong master key length fails closed") {
            _ = try FaceVaultBrokerReplyPolicy.read(key: Data(repeating: 7, count: 31), error: nil)
        }
        rejects("an error plus data cannot authorize") {
            _ = try FaceVaultBrokerReplyPolicy.read(key: syntheticMasterKey, error: brokerError)
        }
        let schema = FaceEmbeddingSchema(modelVersion: "synthetic-crypto-fixture-v1", dimension: 16)!
        let embedding = FaceNormalizedEmbedding(schema: schema, values: [1] + [Float](repeating: 0, count: 15))!
        let identity = FaceIdentityTemplate(label: "Harmless fixture label", samples: [embedding])!
        let manifest = FaceIdentityManifest(identities: [identity])!
        let credential = Data("synthetic-fixture-not-a-user-password".utf8)
        let contents = FaceVaultContents(manifest: manifest, credentialData: credential)!
        let key = SymmetricKey(size: .bits256)
        let vaultID = UUID()
        let sealed = try FaceVaultCipher.seal(contents, key: key, vaultID: vaultID, ownerUserID: 501)
        let opened = try FaceVaultCipher.open(sealed, key: key, vaultID: vaultID, ownerUserID: 501)
        check(opened == contents, "encrypted payload roundtrip")
        let sealedAgain = try FaceVaultCipher.seal(contents, key: key, vaultID: vaultID, ownerUserID: 501)
        check(sealed != sealedAgain, "each seal uses a fresh nonce")

        // Only this unique synthetic directory is touched. No user's vault,
        // Keychain item or real biometric/password information is opened.
        let fixtureDirectory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("notchscape-encrypted-file-fixture-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }
        let fixtureVaultDirectory = fixtureDirectory.appendingPathComponent("encrypted")
        let fixtureFile = fixtureVaultDirectory.appendingPathComponent("fixture.vault")
        try FaceVaultEncryptedFileStore.write(sealed, to: fixtureFile, directory: fixtureVaultDirectory)
        let firstStored = try FaceVaultEncryptedFileStore.read(from: fixtureFile)
        check(firstStored == sealed, "isolated encrypted envelope survives storage roundtrip")
        let directoryMode = try FileManager.default.attributesOfItem(atPath: fixtureVaultDirectory.path)[.posixPermissions] as? NSNumber
        let fileMode = try FileManager.default.attributesOfItem(atPath: fixtureFile.path)[.posixPermissions] as? NSNumber
        check(directoryMode?.intValue == 0o700 && fileMode?.intValue == 0o600, "encrypted directory and file are owner-only")
        try FaceVaultEncryptedFileStore.write(sealedAgain, to: fixtureFile, directory: fixtureVaultDirectory)
        let replacedStored = try FaceVaultEncryptedFileStore.read(from: fixtureFile)
        check(replacedStored == sealedAgain, "atomic replacement stores the new encrypted envelope")
        failsAt(.encryptedRead, "missing encrypted file preserves read stage") {
            _ = try FaceVaultEncryptedFileStore.read(from: fixtureVaultDirectory.appendingPathComponent("missing.vault"))
        }
        failsAt(.encryptedWrite, "empty envelopes are rejected before storage") {
            try FaceVaultEncryptedFileStore.write(Data(), to: fixtureFile, directory: fixtureVaultDirectory)
        }
        failsAt(.encryptedWrite, "oversize envelopes are rejected before storage") {
            try FaceVaultEncryptedFileStore.write(Data(count: FaceVaultCipher.maximumFileBytes + 1), to: fixtureFile, directory: fixtureVaultDirectory)
        }
        failsAt(.encryptedWrite, "file writes cannot escape the selected vault directory") {
            try FaceVaultEncryptedFileStore.write(sealed, to: fixtureDirectory.appendingPathComponent("outside.vault"), directory: fixtureVaultDirectory)
        }
        let symlinkFile = fixtureVaultDirectory.appendingPathComponent("symlink.vault")
        try FileManager.default.createSymbolicLink(at: symlinkFile, withDestinationURL: fixtureFile)
        failsAt(.encryptedRead, "a symlink cannot redirect an encrypted read") {
            _ = try FaceVaultEncryptedFileStore.read(from: symlinkFile)
        }
        failsAt(.encryptedWrite, "a symlink cannot redirect an encrypted write") {
            try FaceVaultEncryptedFileStore.write(sealed, to: symlinkFile, directory: fixtureVaultDirectory)
        }
        let symlinkDirectory = fixtureDirectory.appendingPathComponent("redirected")
        try FileManager.default.createSymbolicLink(at: symlinkDirectory, withDestinationURL: fixtureVaultDirectory)
        failsAt(.encryptedWrite, "a symlink parent cannot redirect vault storage") {
            try FaceVaultEncryptedFileStore.write(sealed, to: symlinkDirectory.appendingPathComponent("other.vault"), directory: symlinkDirectory)
        }
        let preservedStored = try FaceVaultEncryptedFileStore.read(from: fixtureFile)
        check(preservedStored == sealedAgain,
              "rejected writes preserve the existing encrypted envelope")
        let outer = String(decoding: sealed, as: UTF8.self)
        check(!outer.contains(identity.label), "identity labels are encrypted")
        check(!outer.contains(credential.base64EncodedString()), "credential data is encrypted")
        check(!String(reflecting: contents).contains("synthetic-fixture"), "debug description redacts credential")
        rejects("wrong key must fail authentication") {
            _ = try FaceVaultCipher.open(sealed, key: SymmetricKey(size: .bits256), vaultID: vaultID, ownerUserID: 501)
        }
        rejects("different vault cannot accept ciphertext") {
            _ = try FaceVaultCipher.open(sealed, key: key, vaultID: UUID(), ownerUserID: 501)
        }
        rejects("different user cannot accept ciphertext") {
            _ = try FaceVaultCipher.open(sealed, key: key, vaultID: vaultID, ownerUserID: 502)
        }
        var object = try JSONSerialization.jsonObject(with: sealed) as! [String: Any]
        var combined = Data(base64Encoded: object["sealedData"] as! String)!
        combined[combined.count - 1] ^= 1
        object["sealedData"] = combined.base64EncodedString()
        rejects("tampered authentication tag rejected") {
            _ = try FaceVaultCipher.open(JSONSerialization.data(withJSONObject: object), key: key, vaultID: vaultID, ownerUserID: 501)
        }
        object = try JSONSerialization.jsonObject(with: sealed) as! [String: Any]
        let substitutedID = UUID()
        object["vaultID"] = substitutedID.uuidString
        rejects("rewriting envelope identity cannot bypass associated-data binding") {
            _ = try FaceVaultCipher.open(JSONSerialization.data(withJSONObject: object), key: key, vaultID: substitutedID, ownerUserID: 501)
        }
        object = try JSONSerialization.jsonObject(with: sealed) as! [String: Any]
        object["ownerUserID"] = 502
        rejects("rewriting envelope user cannot bypass associated-data binding") {
            _ = try FaceVaultCipher.open(JSONSerialization.data(withJSONObject: object), key: key, vaultID: vaultID, ownerUserID: 502)
        }
        object = try JSONSerialization.jsonObject(with: sealed) as! [String: Any]
        object["formatVersion"] = 2
        rejects("unknown envelope version rejected") {
            _ = try FaceVaultCipher.open(JSONSerialization.data(withJSONObject: object), key: key, vaultID: vaultID, ownerUserID: 501)
        }
        rejects("truncated envelope rejected") {
            _ = try FaceVaultCipher.open(Data(sealed.prefix(20)), key: key, vaultID: vaultID, ownerUserID: 501)
        }
        rejects("oversize envelope rejected before decoding") {
            _ = try FaceVaultCipher.open(Data(count: FaceVaultCipher.maximumFileBytes + 1), key: key, vaultID: vaultID, ownerUserID: 501)
        }
        check(FaceVaultContents(manifest: manifest, credentialData: Data()) == nil, "empty credential rejected")
        check(FaceVaultContents(manifest: manifest, credentialData: Data(count: 4097)) == nil, "credential bounded")
        var mutated = contents; mutated.credentialData = Data(count: 4097)
        rejects("seal revalidates mutable payload") {
            _ = try FaceVaultCipher.seal(mutated, key: key, vaultID: vaultID, ownerUserID: 501)
        }

        // No setup/auth API is exercised with valid inputs. This block tests
        // default-deny preflights only: no Keychain item, auth prompt or file IO.
        let absentDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("notchscape-vault-no-io-\(UUID().uuidString)")
        let vault = try FaceUnlockVault(directory: absentDirectory, vaultID: UUID())
        let initialStatus = await vault.status()
        check(initialStatus == .locked, "construction defaults locked")
        let initialSession = await vault.authorizationSession()
        check(initialSession == nil, "construction does not authorize")
        do { _ = try await vault.manifest(); preconditionFailure("locked manifest must not be readable") }
        catch FaceVaultError.authorizationRequired { checks += 1 }
        do { _ = try await vault.hasCredential(); preconditionFailure("locked credential presence must require authorization") }
        catch FaceVaultError.authorizationRequired { checks += 1 }
        do { try await vault.deleteVault(); preconditionFailure("locked delete must fail before Keychain access") }
        catch FaceVaultError.authorizationRequired { checks += 1 }
        do { try await vault.authorizeScreenUnlockConvenience(lifetime: 60, reason: "Unused test reason"); preconditionFailure("unknown desktop must prevent auth") }
        catch FaceVaultError.desktopLocked { checks += 1 }
        do { try await vault.authorizeAutomaticUnlock(reason: "Unused automatic reason"); preconditionFailure("automatic authorization needs a verified unlocked desktop") }
        catch FaceVaultError.desktopLocked { checks += 1 }
        await vault.updateDesktopState(isActive: true, isUnlocked: true)
        do { try await vault.authorizeScreenUnlockConvenience(lifetime: .infinity, reason: "Unused test reason"); preconditionFailure("invalid lifetime must stop before auth") }
        catch FaceVaultError.invalidInput { checks += 1 }
        let thresholds = FaceMatchThresholds(minimumCosineSimilarity: 0.8, minimumRunnerUpMargin: 0.05)!
        let noChallenge = try await vault.withCredentialForRecognizedFace(embedding, thresholds: thresholds,
            challengeSatisfied: false, authorizationToken: UUID()) { _ in preconditionFailure("unauthorized credential closure") }
        check(noChallenge == .noMatch, "missing challenge cannot reach secret operation")
        do {
            _ = try await vault.withCredentialForRecognizedFace(embedding, thresholds: thresholds,
                challengeSatisfied: true, authorizationToken: UUID()) { _ in preconditionFailure("stale token closure") }
            preconditionFailure("stale token must be rejected")
        } catch FaceVaultError.invalidated { checks += 1 }
        await vault.handle(.screenLocked)
        await vault.stop()
        let finalStatus = await vault.status()
        check(finalStatus == .locked, "lock and stop cannot create authorization")
        check(!FileManager.default.fileExists(atPath: absentDirectory.path), "constructor and denied preflights never create vault files")
        let cancelledRead = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await vault.hasCredential()
        }
        do { _ = try await cancelledRead.value; preconditionFailure("cancelled callers must fail before reading") }
        catch FaceVaultError.cancelled { checks += 1 }
        check(FaceUnlockVault.monotonicNow().isFinite, "exported session clock is finite")
        print("PASS \(checks) face vault checks (synthetic crypto/files/query/diagnostics; no Keychain/auth/camera use)")
    }
}
