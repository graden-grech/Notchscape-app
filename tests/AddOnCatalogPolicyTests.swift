import Foundation
import CryptoKit
import CoreGraphics
import ImageIO

@main
@MainActor
struct AddOnCatalogPolicyTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ reason: String) {
        precondition(condition(), reason); checks += 1
    }
    static func rejects(_ expected: ContentPackValidationError, _ reason: String, _ operation: () throws -> Void) {
        do { try operation(); preconditionFailure(reason) }
        catch let error as ContentPackValidationError { check(error == expected, reason) }
        catch { preconditionFailure("Unexpected error: \(reason)") }
    }
    static func main() throws {
        check(AddOnCatalog.items.count == Set(AddOnCatalog.items.map(\.id)).count, "Catalog identifiers are stable and unique")
        for id in ["widgets", "developer"] {
            check(AddOnCatalog.items.first { $0.id == id }?.availability == .notPublished, "Unpublished features never pretend to be installed")
        }
        let dock = AddOnCatalog.items.first { $0.id == "dock" }!
        check(dock.availability == .includedPreview && dock.settingsID == "Dock", "Dock workspace preview routes to real settings, not a download")
        check(dock.status == "Included Dock preview", "Dock status names its actual preview boundary")
        check(dock.plan.contains("not included"), "A Dock workspace does not claim replacement-Dock parity")
        let snow = AddOnCatalog.items.first { $0.id == "desktop-snow" }!
        check(snow.availability == .includedPreview && snow.settingsID == "Appearance", "Desktop Snow is bundled and routes to real Appearance settings")
        check(!snow.isTheme && snow.status == "Included · Free", "Snow is an optional free feature rather than a theme or pretend download")
        check(snow.plan.contains("Off by default") && snow.plan.contains("separate download is not published"), "Snow declares explicit opt-in and the real packaging boundary without reading preferences")
        check(AddOnCatalog.items(in: .features, matching: "snow").map(\.id) == ["desktop-snow"], "Snow is discoverable as a feature")
        check(AddOnCatalog.items(in: .installed, matching: "snow").map(\.id) == ["desktop-snow"], "Bundled Snow appears among included features")
        check(AddOnCatalog.items(in: .themes, matching: "snow").isEmpty, "Snow does not masquerade as a separate theme pack")
        check(snow.details.highlights.contains { $0.contains("Music, Calendar, Weather and Quick Actions") }, "Snow details describe the four actual Home tiles")
        check(AddOnCatalog.items(in: .features, matching: "  DOCK  ").contains { $0.id == "dock" }, "Catalog search ignores whitespace and capitalization")
        check(AddOnCatalog.items(in: .features, matching: "folders cards").map(\.id) == ["dock"], "Search matches all query words across capability details")
        check(AddOnCatalog.items(in: .themes, matching: "Christmas").map(\.id) == ["holiday"], "Search remains scoped to the selected category")
        check(AddOnCatalog.items(in: .installed, matching: "WidgetKit").isEmpty, "Missing WidgetKit extension never appears as installed")
        check(AddOnCatalog.items(in: .features, matching: "noSuchFeatureXYZ").isEmpty, "Unknown catalog queries have an empty state")
        check(AddOnCatalog.items.allSatisfy { !$0.details.highlights.isEmpty && !$0.details.requirements.isEmpty && !$0.details.privacy.isEmpty }, "Every detail sheet explains capabilities, requirements and privacy")
        check(AddOnCatalog.items.filter { $0.availability == .notPublished }.allSatisfy { $0.settingsID == nil }, "Planned add-ons have no pretend settings activation route")
        check(AddOnCatalog.items.first { $0.id == "face" }?.availability == .localPreviewOnly, "Face distribution limitation remains explicit")
        check(AddOnCatalog.items.filter { $0.appears(in: .themes) }.map(\.id) == ["holiday", "civic"], "Theme collections have one coherent surface")
        check(AddOnCatalog.items.filter { $0.appears(in: .installed) }.allSatisfy(\.isIncluded), "Installed filter only contains the bundled preview subset")
        check(ContentPackTrust.official.publicKey == nil, "No fabricated publisher key makes downloads appear available")

        let pixels = Data([255, 0, 0, 255])
        let image = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: CGDataProvider(data: pixels as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let encoded = NSMutableData()
        let encoder = CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(encoder, image, nil)
        check(CGImageDestinationFinalize(encoder), "Generate an isolated one-pixel image fixture")
        let png = encoded as Data
        let archive = Data([80, 75, 3, 4]) + Data("synthetic archive bytes".utf8)
        let privateKey = Curve25519.Signing.PrivateKey()
        let trust = ContentPackTrust(publisherID: ContentPackTrust.officialPublisherID, publicKey: privateKey.publicKey.rawRepresentation)
        let file = ContentPackFile(path: "scenes/winter.png", role: .scene, byteCount: png.count, sha256: ContentPackPolicy.digest(png))
        let manifest = ContentPackManifest(schemaVersion: 1, publisherID: ContentPackTrust.officialPublisherID,
            packID: .holiday, version: "1.0.0", minimumCoreVersion: "2.9.5", minimumOSVersion: "14.0.0",
            archiveURL: URL(string: "https://github.com/graden-grech/Notchscape-app/releases/download/packs-1.0.0/holiday-1.0.0.zip")!,
            archiveBytes: archive.count, archiveSHA256: ContentPackPolicy.digest(archive), files: [file])
        let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest)) as! [String: Any]
        func envelope(_ object: [String: Any]) throws -> Data {
            let payload = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
            return try JSONEncoder().encode(SignedContentPackEnvelope(payloadBase64: payload.base64EncodedString(), signatureBase64: privateKey.signature(for: payload).base64EncodedString()))
        }
        func validate(_ object: [String: Any], core: String = "2.9.5", os: String = "26.0.0") throws -> ContentPackManifest {
            try ContentPackPolicy.validateEnvelope(envelope(object), coreVersion: core, osVersion: os, trust: trust)
        }
        let validEnvelope = try envelope(raw)
        let checked = try validate(raw)
        check(checked == manifest, "Signed exact payload validates with a pinned fixture key")
        try ContentPackPolicy.validateArchiveBytes(archive, manifest: checked)
        try ContentPackPolicy.validateStagedFiles([.init(path: file.path, kind: .regular, data: png)], manifest: checked)
        checks += 2
        rejects(.publisherNotConfigured, "Shipping trust fails closed until a key is pinned") {
            _ = try ContentPackPolicy.validateEnvelope(validEnvelope, coreVersion: "2.9.5", osVersion: "26.0.0")
        }
        let otherTrust = ContentPackTrust(publisherID: ContentPackTrust.officialPublisherID, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)
        rejects(.badSignature, "A different publisher key is rejected") {
            _ = try ContentPackPolicy.validateEnvelope(validEnvelope, coreVersion: "2.9.5", osVersion: "26.0.0", trust: otherTrust)
        }
        let decodedEnvelope = try JSONDecoder().decode(SignedContentPackEnvelope.self, from: validEnvelope)
        var payload = Data(base64Encoded: decodedEnvelope.payloadBase64)!; payload[payload.startIndex] ^= 1
        let tamperedEnvelope = try JSONEncoder().encode(SignedContentPackEnvelope(payloadBase64: payload.base64EncodedString(), signatureBase64: decodedEnvelope.signatureBase64))
        rejects(.badSignature, "Payload bytes cannot be changed after signing") {
            _ = try ContentPackPolicy.validateEnvelope(tamperedEnvelope, coreVersion: "2.9.5", osVersion: "26.0.0", trust: trust)
        }
        var untrustedEnvelope = try JSONSerialization.jsonObject(with: validEnvelope) as! [String: Any]
        untrustedEnvelope["publicKey"] = privateKey.publicKey.rawRepresentation.base64EncodedString()
        let injectedKeyEnvelope = try JSONSerialization.data(withJSONObject: untrustedEnvelope)
        rejects(.malformedEnvelope, "Downloaded envelopes cannot smuggle their own trusted key") {
            _ = try ContentPackPolicy.validateEnvelope(injectedKeyEnvelope, coreVersion: "2.9.5", osVersion: "26.0.0", trust: trust)
        }
        var extra = raw; extra["runScript"] = "not executable"
        rejects(.unsupportedManifest, "Unknown executable-style fields are not accepted") { _ = try validate(extra) }
        var publisher = raw; publisher["publisherID"] = "com.other.publisher"
        rejects(.unsupportedManifest, "Only the predefined publisher is accepted") { _ = try validate(publisher) }
        var unknownPack = raw; unknownPack["packID"] = "com.notchscape.pack.arbitrary"
        rejects(.unsupportedManifest, "Only predefined resource pack IDs are accepted") { _ = try validate(unknownPack) }
        rejects(.incompatibleVersion, "Core compatibility is checked before install") { _ = try validate(raw, core: "2.9.4") }
        rejects(.incompatibleVersion, "OS compatibility is checked before install") { _ = try validate(raw, os: "13.0.0") }
        var version = raw; version["version"] = "01.0.0"
        rejects(.incompatibleVersion, "Noncanonical versions are rejected") { _ = try validate(version) }
        for url in ["http://github.com/graden-grech/Notchscape-app/releases/download/packs-1.0.0/holiday-1.0.0.zip", "https://github.com/other/repo/releases/download/packs-1.0.0/holiday-1.0.0.zip", "https://github.com.evil.example/graden-grech/Notchscape-app/releases/download/packs-1.0.0/holiday-1.0.0.zip", manifest.archiveURL.absoluteString + "?token=secret", manifest.archiveURL.absoluteString + "#fragment", manifest.archiveURL.absoluteString.replacingOccurrences(of: "holiday-", with: "civic-")] {
            var object = raw; object["archiveURL"] = url
            rejects(.unsafeURL, "Only exact own-repository HTTPS artifact locations are allowed") { _ = try validate(object) }
        }
        for path in ["../scenes/a.png", "/scenes/a.png", "scenes/../a.png", "scenes\\a.png", "scenes/a.js", "scenes/a.png/evil", "scenes/%2e%2e.png", "icons/winter.png", "scenes/Upper.png", "scenes/.hidden.png", "scenes/a:stream.png"] {
            var object = raw; object["files"] = [["path": path, "role": "scene", "byteCount": png.count, "sha256": file.sha256]]
            rejects(.unsafePath, "Traversal, executable, hidden, alternate-stream and mismatched paths are rejected") { _ = try validate(object) }
        }
        var duplicate = raw; duplicate["files"] = [raw["files"] as! [[String: Any]]].flatMap { $0 + $0 }
        rejects(.unsafePath, "Duplicate output paths are rejected") { _ = try validate(duplicate) }
        var oversized = raw; oversized["archiveBytes"] = ContentPackPolicy.maximumArchiveBytes + 1
        rejects(.invalidSize, "Archive byte budget is enforced") { _ = try validate(oversized) }
        var tooMany = raw; tooMany["files"] = Array(repeating: (raw["files"] as! [[String: Any]])[0], count: 81)
        rejects(.invalidSize, "Manifest file count is bounded") { _ = try validate(tooMany) }
        var badHash = raw; badHash["archiveSHA256"] = String(repeating: "z", count: 64)
        rejects(.invalidHash, "Only canonical SHA256 digests are accepted") { _ = try validate(badHash) }
        rejects(.unexpectedContents, "Symlinks are never staged as images") {
            try ContentPackPolicy.validateStagedFiles([.init(path: file.path, kind: .symbolicLink, data: png)], manifest: checked)
        }
        rejects(.unexpectedContents, "An archive directory cannot impersonate a regular image") {
            try ContentPackPolicy.validateStagedFiles([.init(path: file.path, kind: .directory, data: png)], manifest: checked)
        }
        rejects(.invalidSize, "Truncated files are rejected before decoding") {
            try ContentPackPolicy.validateStagedFiles([.init(path: file.path, kind: .regular, data: png.dropLast())], manifest: checked)
        }
        rejects(.unexpectedContents, "Additional undeclared files are rejected") {
            try ContentPackPolicy.validateStagedFiles([.init(path: file.path, kind: .regular, data: png), .init(path: "scenes/extra.png", kind: .regular, data: png)], manifest: checked)
        }
        var changed = png; changed[changed.startIndex] ^= 1
        rejects(.invalidHash, "Changed image bytes are rejected before decoding") {
            try ContentPackPolicy.validateStagedFiles([.init(path: file.path, kind: .regular, data: changed)], manifest: checked)
        }
        rejects(.invalidHash, "Changed archive bytes are rejected") {
            try ContentPackPolicy.validateArchiveBytes(Data(repeating: 0, count: archive.count), manifest: checked)
        }
        let script = Data("#!/bin/sh\necho fixture".utf8)
        var disguised = raw; disguised["files"] = [["path": file.path, "role": "scene", "byteCount": script.count, "sha256": ContentPackPolicy.digest(script)]]
        let disguisedManifest = try validate(disguised)
        rejects(.invalidImage, "A script with an image extension and valid hash is still rejected") {
            try ContentPackPolicy.validateStagedFiles([.init(path: file.path, kind: .regular, data: script)], manifest: disguisedManifest)
        }
        print("PASS: \(checks) add-on catalog, signature, compatibility, path, size, hash and image policy checks (synthetic data only)")
    }
}
