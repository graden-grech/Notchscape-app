import Foundation
import Auth0
import SimpleKeychain

/// Uses synthetic in-memory data only. Never reads the developer's Keychain.
final class MemoryStorage: CredentialsStorage {
    var entries: [String: Data] = [:]
    var denied = false
    func getEntry(forKey key: String) throws -> Data {
        guard let value = entries[key] else { throw SimpleKeychainError.itemNotFound }
        return value
    }
    func setEntry(_ data: Data, forKey key: String) throws { entries[key] = data }
    func deleteEntry(forKey key: String) throws {
        if denied { throw SimpleKeychainError.interactionNotAllowed }
        guard entries.removeValue(forKey: key) != nil else { throw SimpleKeychainError.itemNotFound }
    }
}

@main struct StorageRegression {
    static func main() throws {
        let raw = MemoryStorage()
        let auth = Auth0.authentication(clientId: "unit-test-client", domain: "unit-test.example")
        let original = CredentialsManager(authentication: auth, storage: raw)
        do { try original.clear(); preconditionFailure("Expected SDK missing-item behavior") }
        catch SimpleKeychainError.itemNotFound { }

        let safe = AccountCredentialStorage(base: raw)
        let manager = CredentialsManager(authentication: auth, storage: safe)
        try manager.clear() // A new account must be able to reach the store step.
        try manager.clear() // Idempotent, including the SDK's session pin keys.
        try safe.setEntry(Data("synthetic fixture".utf8), forKey: "credentials")
        try safe.setEntry(Data("unrelated fixture".utf8), forKey: "unrelated")
        try manager.clear()
        precondition(raw.entries["credentials"] == nil)
        precondition(raw.entries["unrelated"] != nil)
        raw.denied = true
        do { try manager.clear(); preconditionFailure("Must not hide real Keychain errors") }
        catch SimpleKeychainError.interactionNotAllowed { }
        print("Passed account storage regressions: first login, repeated clear, isolation and denied access")
    }
}
