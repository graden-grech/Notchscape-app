import CryptoKit
import Foundation

// Verifies public bytes only. Private update keys are never exported/read here.
do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 3 else {
        throw NSError(domain: "Notchscape.Release", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Usage: verify_sparkle_archive.swift archive.zip signature trusted.app"])
    }
    let trustedInfo = URL(fileURLWithPath: arguments[2]).appendingPathComponent("Contents/Info.plist")
    let dictionary = try PropertyListSerialization.propertyList(from: Data(contentsOf: trustedInfo), format: nil) as? [String: Any]
    guard let encodedKey = dictionary?["SUPublicEDKey"] as? String,
          let publicKeyData = Data(base64Encoded: encodedKey),
          let signature = Data(base64Encoded: arguments[1]), signature.count == 64 else {
        throw NSError(domain: "Notchscape.Release", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Invalid public key/signature metadata"])
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    let bytes = try Data(contentsOf: URL(fileURLWithPath: arguments[0]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: bytes) else {
        throw NSError(domain: "Notchscape.Release", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Archive signature does not match the trusted app’s pinned update key"])
    }
    print("PASS: archive Ed25519 signature matches trusted app’s pinned public key")
    print("SHA256: " + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
} catch {
    FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
    exit(1)
}
