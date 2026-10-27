import Auth0
import Foundation
import SimpleKeychain

/// Auth0 3's clear() throws when the main item doesn't exist. Deleting an absent
/// item must be idempotent for a first login; every other Keychain error still
/// propagates. This wrapper never touches another service's credentials.
struct AccountCredentialStorage: CredentialsStorage {
    let base: any CredentialsStorage
    func getEntry(forKey key: String) throws -> Data { try base.getEntry(forKey: key) }
    func setEntry(_ data: Data, forKey key: String) throws { try base.setEntry(data, forKey: key) }
    func deleteEntry(forKey key: String) throws {
        do { try base.deleteEntry(forKey: key) }
        catch SimpleKeychainError.itemNotFound { }
    }
}
