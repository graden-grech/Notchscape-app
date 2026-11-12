import Foundation
import CryptoKit
import ImageIO

enum AddOnCategory: String, CaseIterable, Identifiable {
    case features = "Features", themes = "Theme Packs", installed = "Installed"
    var id: Self { self }
}

struct AddOnCatalogueItem: Identifiable {
    enum Availability { case includedPreview, notPublished, localPreviewOnly }
    let id: String
    let title: String
    let symbol: String
    let description: String
    let isTheme: Bool
    let availability: Availability
    let plan: String
    let settingsID: String?
    var isIncluded: Bool { availability != .notPublished }
    var status: String {
        switch availability {
        case .includedPreview: id == "dock" ? "Included Dock preview" : id == "desktop-snow" ? "Included · Free" : "Included with app"
        case .notPublished: "Not published yet"
        case .localPreviewOnly: "Local preview only"
        }
    }
    var availabilityExplanation: String {
        switch availability {
        case .includedPreview:
            "These features are included in this app preview. Their files stay in the app when you turn them off. Separate downloads are not published yet."
        case .notPublished:
            "This add-on is planned. There is no download to install yet, and opening this page does not turn anything on."
        case .localPreviewOnly:
            "This Face Unlock preview is configured for local testing on this Mac. It is not available as a generally usable public download."
        }
    }
    var details: AddOnDetails { AddOnDetails.forItem(id) }
    func matches(_ query: String) -> Bool {
        let words = query.prefix(256).split(whereSeparator: \.isWhitespace).map(String.init)
        let searchable = ([title, description, plan] + details.highlights + [details.requirements]).joined(separator: " ")
        return words.allSatisfy { searchable.localizedStandardContains($0) }
    }
    func appears(in category: AddOnCategory) -> Bool {
        switch category { case .features: !isTheme; case .themes: isTheme; case .installed: isIncluded }
    }
}

enum AddOnCatalog {
    // No fabricated release URLs. A future published artifact also needs the
    // signed manifest, pinned publisher key, verified payload and real installer.
    static let items: [AddOnCatalogueItem] = [
        .init(id: "core", title: "Notchscape Core", symbol: "app.connected.to.app.below.fill", description: "Basic Notch and Dynamic Island, music, calendar, shelf and HUDs, with updates and shared privacy controls.", isTheme: false, availability: .includedPreview, plan: "Always included with the app.", settingsID: "General"),
        .init(id: "island", title: "Island Extras", symbol: "capsule.portrait", description: "Notes, timers, AI status, sports and advanced dashboard pages.", isTheme: false, availability: .includedPreview, plan: "Bundled for this preview; planned as an optional add-on. The basic Notch and Island stay in Core.", settingsID: "General"),
        .init(id: "dock", title: "Dock", symbol: "dock.rectangle", description: "A live macOS Dock tile and a separate workspace for your chosen apps, folders and widget cards.", isTheme: false, availability: .includedPreview, plan: "Optional and off by default. Choose a Clock, Battery or Calendar Dock tile, or open Dock Workspace. A full replacement for the macOS Dock is not included.", settingsID: "Dock"),
        .init(id: "desktop-snow", title: "Desktop Snow", symbol: "snowflake", description: "Soft desktop snowfall, rounded snow drifts and optional snow caps on your Home tiles.", isTheme: false, availability: .includedPreview, plan: "Free. Off by default. Enable it here or in Appearance. Included in this app preview; a separate download is not published.", settingsID: "Appearance"),
        .init(id: "widgets", title: "Desktop Widgets", symbol: "rectangle.grid.2x2", description: "Planned native widgets for your desktop and Notification Center.", isTheme: false, availability: .notPublished, plan: "Priority add-on. Requires a real WidgetKit extension.", settingsID: nil),
        .init(id: "clipboard", title: "Clipboard", symbol: "doc.on.clipboard", description: "Optional encrypted copies, local boards, filters and text previews.", isTheme: false, availability: .includedPreview, plan: "Recording stays off until you enable it in Settings.", settingsID: "Tools"),
        .init(id: "windows", title: "Windows & Workspaces", symbol: "rectangle.split.2x2", description: "Position selected windows and review saved layouts with Undo.", isTheme: false, availability: .includedPreview, plan: "Window control requests Accessibility only when needed.", settingsID: "Tools"),
        .init(id: "system", title: "System & Menu Bar", symbol: "gauge.with.dots.needle.50percent", description: "System statistics with optional glanceable menu-bar items.", isTheme: false, availability: .includedPreview, plan: "Current system tools are bundled. Module downloads are not published.", settingsID: "System"),
        .init(id: "capture", title: "Capture & Tools", symbol: "viewfinder", description: "On-demand capture, OCR, notes, timers and personal tools.", isTheme: false, availability: .includedPreview, plan: "Downloading never enables recording or private-data access.", settingsID: "Tools"),
        .init(id: "wallpapers", title: "Wallpapers", symbol: "photo.on.rectangle.angled", description: "Browse scenes, favorites and optional desktop rotation.", isTheme: false, availability: .includedPreview, plan: "Wallpaper files download only for the existing explicit actions.", settingsID: "Wallpapers"),
        .init(id: "developer", title: "Developer Tools", symbol: "chevron.left.forwardslash.chevron.right", description: "Planned read-only project, server, container and workflow snapshots.", isTheme: false, availability: .notPublished, plan: "Existing AI status stays available. Broader adapters are not published.", settingsID: nil),
        .init(id: "advanced", title: "Advanced Controls", symbol: "slider.horizontal.3", description: "Detailed tuning and experimental preferences for people who want more control.", isTheme: false, availability: .includedPreview, plan: "Current advanced preferences are bundled. Common settings stay in Core; extra controls are planned as an optional add-on.", settingsID: "Advanced"),
        .init(id: "face", title: "Face Unlock", symbol: "person.crop.square", description: "Optional local face-recognition convenience at the lock screen.", isTheme: false, availability: .localPreviewOnly, plan: "Public distribution is unavailable with the current development broker.", settingsID: "FaceUnlock"),
        .init(id: "holiday", title: "Holiday Collection", symbol: "sparkles", description: "Christmas, Halloween, Easter, autumn and neutral winter scenes.", isTheme: true, availability: .includedPreview, plan: "Current scenes are bundled. A removable resource-pack download is not published yet.", settingsID: "Appearance"),
        .init(id: "civic", title: "Civic Collection", symbol: "building.columns", description: "White House, Capitol and Supreme Court scenes, with additional Treasury, Pentagon and Executive Office artwork prepared.", isTheme: true, availability: .includedPreview, plan: "Current scenes remain bundled. Additional scenes are prepared; pack downloads are not published yet.", settingsID: "Appearance")
    ]

    static func items(in category: AddOnCategory, matching query: String) -> [AddOnCatalogueItem] {
        items.filter { $0.appears(in: category) && $0.matches(query) }
    }
}

/// User-facing capabilities and access requirements, not executable module metadata.
/// Keeping this information with the catalog makes detail sheets and search agree.
struct AddOnDetails {
    let highlights: [String]
    let requirements: String
    let privacy: String

    static func forItem(_ id: String) -> Self {
        switch id {
        case "core": .init(highlights: ["Notch and Dynamic Island", "Music, calendar, shelf and volume HUDs", "Privacy controls and app updates"], requirements: "Always included with Notchscape. Each feature explains the access it needs when you use it.", privacy: "No Notchscape account is required. Your existing settings stay on this Mac.")
        case "dock": .init(highlights: ["Show Clock, Battery or Calendar in the macOS Dock", "Pin apps and folders in a separate workspace", "Rearrange workspace cards"], requirements: "Enable the Dock Widget or Dock Workspace separately in Dock settings. The widget uses its own running Dock tile; it does not replace the system Dock.", privacy: "Off by default. Calendar shows the date without reading events. Adding an app or folder is your choice. It does not change macOS Dock settings.")
        case "island": .init(highlights: ["AI agent status and live scores", "Notes, timers and extra dashboard pages", "Shared display and privacy controls"], requirements: "Choose the activities you want in Settings. Basic Notch and Dynamic Island features stay in Core.", privacy: "Features keep their own access controls. Browsing Add-ons does not enable an activity or connect an account.")
        case "desktop-snow": .init(highlights: ["Gentle desktop snowfall and rounded settled drifts", "Optional snow caps on Music, Calendar, Weather and Quick Actions", "Independent controls for window edges, displays and snowfall"], requirements: "Off by default. Use the switch to enable Desktop Snow, then adjust its options in Appearance. Home caps have a separate switch. Reduce Motion pauses snowfall and the caps; low-impact mode limits animation.", privacy: "No account, camera, microphone or screen recording is needed. Optional window snow reads positions only, never window pictures or text. Clicks pass through decoration; snow pauses on lock, sleep, Presentation mode and Notchscape recording.")
        case "widgets": .init(highlights: ["Planned desktop widgets", "Planned Notification Center widgets", "Shared Notchscape appearance"], requirements: "A separate native WidgetKit extension is still needed. Dock cards are not desktop or Notification Center widgets.", privacy: "Not installed. Future widgets will need their own permission and lock-screen privacy behavior.")
        case "clipboard": .init(highlights: ["Encrypted local history and named boards", "Type, date and pinned filters", "Preview text transformations before copying"], requirements: "Turn on recording explicitly in Tools & Shortcuts. History stays off until you choose it.", privacy: "Copies stay local and encrypted. Best-effort sensitive-content detection hides matches; newly detected sensitive copies expire after ten minutes.")
        case "windows": .init(highlights: ["Halves, corners and precision placements", "Custom grids, gaps and display moves", "Undo and optional keyboard shortcuts"], requirements: "Accessibility permission is needed to move windows. Keyboard shortcuts have no default assignments.", privacy: "Window actions run when you request them. Browsing this page does not inspect or move your windows.")
        case "system": .init(highlights: ["CPU, memory, storage and network summaries", "Optional menu-bar readouts", "Power and battery information"], requirements: "Choose the menu-bar modules you want in General. Modules are off by default; supported metrics depend on the Mac.", privacy: "Shared sampling pauses with the app’s privacy and sleep controls. No writable fan control or private Screen Time database access is included.")
        case "capture": .init(highlights: ["On-demand capture and text recognition", "Notes and personal tools", "Timers, clocks and quick utilities"], requirements: "Capture and Apple Notes automation request their own macOS access when needed.", privacy: "Opening Add-ons does not record a screen, activate a camera or microphone, or export a note.")
        case "wallpapers": .init(highlights: ["Browse and favorite desktop scenes", "Choose the display to update", "Optional rotation and Undo"], requirements: "Wallpaper downloads and desktop changes follow your explicit selection. Rotation has a separate control.", privacy: "Browsing does not replace your wallpaper or enable rotation. Your own source images remain your files.")
        case "developer": .init(highlights: ["Planned project and server snapshots", "Planned container and workflow adapters", "Existing AI status stays in Island Extras"], requirements: "Broader developer adapters are not published. There is no download to activate yet.", privacy: "This catalog does not scan projects, run commands, read credentials or contact developer services.")
        case "advanced": .init(highlights: ["Detailed display and behavior tuning", "Optional experimental controls", "Common settings stay in Core"], requirements: "Advanced controls are currently bundled. Their separate add-on package is not published.", privacy: "Opening advanced settings does not grant extra macOS permissions or reset your existing preferences.")
        case "face": .init(highlights: ["Guided camera enrollment", "Multiple local face appearances", "Automatic convenience-unlock option"], requirements: "Local preview only, using a device-bound development broker. macOS authentication, camera enrollment and real unlock testing are manual steps.", privacy: "Not Apple Face ID. RGB recognition is uncalibrated. Do not rely on this preview for Face ID-level security or FileVault first login; enrollment is local and opt-in.")
        case "holiday": .init(highlights: ["Christmas and Halloween scenes", "Easter, autumn and neutral winter", "Coordinated accents and app-icon choices"], requirements: "Existing scenes are included with this preview. A separately removable resource-pack download is not published.", privacy: "Choosing a theme changes Notchscape appearance. Browsing does not change your theme, app icon or desktop wallpaper.")
        case "civic": .init(highlights: ["White House rooms and seasonal variations", "Capitol, Supreme Court and other landmarks", "Additional original building artwork prepared"], requirements: "Existing scenes are included. Treasury, Pentagon and Executive Office artwork is prepared, but not selectable or published as a pack yet.", privacy: "No affiliation or endorsement is implied. Theme selection is optional and does not connect an account or change your wallpaper.")
        default: .init(highlights: [], requirements: "Review this feature’s settings before enabling it.", privacy: "Browsing this page does not enable the feature.")
        }
    }
}

enum ContentPackID: String, Codable, CaseIterable {
    case holiday = "com.notchscape.pack.holiday"
    case civic = "com.notchscape.pack.civic"
}

struct ContentPackVersion: Comparable, Equatable {
    let components: [Int]
    init?(_ value: String) {
        guard value.range(of: #"^(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})$"#, options: .regularExpression) != nil else { return nil }
        components = value.split(separator: ".").compactMap { Int($0) }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

struct ContentPackFile: Codable, Equatable {
    enum Role: String, Codable { case scene, icon, preview }
    let path: String
    let role: Role
    let byteCount: Int
    let sha256: String
}

struct ContentPackManifest: Codable, Equatable {
    let schemaVersion: Int
    let publisherID: String
    let packID: ContentPackID
    let version: String
    let minimumCoreVersion: String
    let minimumOSVersion: String
    let archiveURL: URL
    let archiveBytes: Int
    let archiveSHA256: String
    let files: [ContentPackFile]
}

struct SignedContentPackEnvelope: Codable {
    // Signature covers these exact decoded payload bytes, never a re-encoded JSON object.
    let payloadBase64: String
    let signatureBase64: String
}

struct ContentPackTrust {
    static let officialPublisherID = "com.notchscape.official"
    let publisherID: String
    let publicKey: Data?
    // Deliberately fail closed. Populate only from a publisher key pinned in a
    // reviewed signed-app release, never from the downloaded manifest/preferences.
    static let official = ContentPackTrust(publisherID: officialPublisherID, publicKey: nil)
}

enum ContentPackValidationError: Error, Equatable {
    case publisherNotConfigured, malformedEnvelope, badSignature, unsupportedManifest
    case incompatibleVersion, unsafeURL, unsafePath, invalidSize, invalidHash
    case unexpectedContents, unsupportedFile, invalidImage
}

struct ContentPackStagedFile {
    enum Kind { case regular, directory, symbolicLink }
    let path: String
    let kind: Kind
    let data: Data
}

enum ContentPackPolicy {
    static let maximumFiles = 80
    static let maximumFileBytes = 16_000_000
    static let maximumExpandedBytes = 96_000_000
    static let maximumArchiveBytes = 64_000_000
    static let maximumEnvelopeBytes = 180_000

    static func validateEnvelope(_ data: Data, coreVersion: String, osVersion: String,
                                 trust: ContentPackTrust = .official) throws -> ContentPackManifest {
        guard trust.publisherID == ContentPackTrust.officialPublisherID, let keyData = trust.publicKey,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { throw ContentPackValidationError.publisherNotConfigured }
        guard data.count <= maximumEnvelopeBytes,
              let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(outer.keys) == ["payloadBase64", "signatureBase64"],
              let envelope = try? JSONDecoder().decode(SignedContentPackEnvelope.self, from: data),
              let payload = Data(base64Encoded: envelope.payloadBase64), payload.count <= 120_000,
              let signature = Data(base64Encoded: envelope.signatureBase64), signature.count == 64 else { throw ContentPackValidationError.malformedEnvelope }
        guard key.isValidSignature(signature, for: payload) else { throw ContentPackValidationError.badSignature }
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              Set(object.keys) == ["schemaVersion", "publisherID", "packID", "version", "minimumCoreVersion", "minimumOSVersion", "archiveURL", "archiveBytes", "archiveSHA256", "files"],
              let manifest = try? JSONDecoder().decode(ContentPackManifest.self, from: payload), manifest.schemaVersion == 1,
              manifest.publisherID == trust.publisherID,
              let rawFiles = object["files"] as? [[String: Any]], rawFiles.allSatisfy({ Set($0.keys) == ["path", "role", "byteCount", "sha256"] }) else { throw ContentPackValidationError.unsupportedManifest }
        guard let version = ContentPackVersion(manifest.version), version >= ContentPackVersion("1.0.0")!,
              let requiredCore = ContentPackVersion(manifest.minimumCoreVersion), let core = ContentPackVersion(coreVersion), core >= requiredCore,
              let requiredOS = ContentPackVersion(manifest.minimumOSVersion), let os = ContentPackVersion(osVersion), os >= requiredOS,
              requiredOS >= ContentPackVersion("14.0.0")! else { throw ContentPackValidationError.incompatibleVersion }
        guard isAllowedArchiveURL(manifest.archiveURL, packID: manifest.packID, version: manifest.version) else { throw ContentPackValidationError.unsafeURL }
        guard (1...maximumArchiveBytes).contains(manifest.archiveBytes), !manifest.files.isEmpty,
              manifest.files.count <= maximumFiles else { throw ContentPackValidationError.invalidSize }
        guard isHash(manifest.archiveSHA256) else { throw ContentPackValidationError.invalidHash }
        var paths = Set<String>(), total = 0
        for file in manifest.files {
            guard isAllowedPath(file.path, role: file.role), paths.insert(file.path.lowercased()).inserted else { throw ContentPackValidationError.unsafePath }
            guard (1...maximumFileBytes).contains(file.byteCount), total <= maximumExpandedBytes - file.byteCount else { throw ContentPackValidationError.invalidSize }
            total += file.byteCount
            guard isHash(file.sha256) else { throw ContentPackValidationError.invalidHash }
        }
        return manifest
    }

    static func isAllowedArchiveURL(_ url: URL, packID: ContentPackID, version: String) -> Bool {
        guard ContentPackVersion(version) != nil, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == "github.com", parts.port == nil,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              !parts.percentEncodedPath.contains("%") else { return false }
        let slug = packID == .holiday ? "holiday" : "civic"
        return parts.path == "/graden-grech/Notchscape-app/releases/download/packs-\(version)/\(slug)-\(version).zip"
    }

    static func isAllowedPath(_ path: String, role: ContentPackFile.Role) -> Bool {
        guard path.utf8.count <= 160, path == path.lowercased(), path.unicodeScalars.allSatisfy({ $0.isASCII }),
              path.range(of: #"^[a-z0-9_-]+/[a-z0-9][a-z0-9_-]*\.(png|jpg|jpeg|webp)$"#, options: .regularExpression) != nil else { return false }
        let directory = role == .scene ? "scenes" : role == .icon ? "icons" : "previews"
        return path.hasPrefix(directory + "/")
    }

    static func isHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.unicodeScalars.allSatisfy { (48...57).contains($0.value) || (97...102).contains($0.value) }
    }

    static func validateArchiveBytes(_ data: Data, manifest: ContentPackManifest) throws {
        guard data.count == manifest.archiveBytes, data.count <= maximumArchiveBytes else { throw ContentPackValidationError.invalidSize }
        guard digest(data) == manifest.archiveSHA256 else { throw ContentPackValidationError.invalidHash }
    }

    /// Policy only: no extraction, network, storage writes or activation. A real
    /// installer must obtain Kind from no-follow filesystem metadata, enforce a
    /// streaming expansion limit, and never extract before path checks.
    static func validateStagedFiles(_ entries: [ContentPackStagedFile], manifest: ContentPackManifest) throws {
        guard entries.count == manifest.files.count, entries.count <= maximumFiles else { throw ContentPackValidationError.unexpectedContents }
        var seen = Set<String>(), total = 0
        for entry in entries {
            guard entry.kind == .regular, seen.insert(entry.path).inserted,
                  let file = manifest.files.first(where: { $0.path == entry.path }), isAllowedPath(entry.path, role: file.role) else { throw ContentPackValidationError.unexpectedContents }
            guard entry.data.count == file.byteCount, !entry.data.isEmpty, entry.data.count <= maximumFileBytes,
                  total <= maximumExpandedBytes - entry.data.count else { throw ContentPackValidationError.invalidSize }
            total += entry.data.count
            guard digest(entry.data) == file.sha256 else { throw ContentPackValidationError.invalidHash }
            guard let image = CGImageSourceCreateWithData(entry.data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetCount(image) == 1,
                  let type = CGImageSourceGetType(image) as String?,
                  ["public.png", "public.jpeg", "org.webmproject.webp"].contains(type),
                  let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  (1...8_192).contains(width), (1...8_192).contains(height), width <= 40_000_000 / height,
                  CGImageSourceCreateImageAtIndex(image, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil else { throw ContentPackValidationError.invalidImage }
            let suffix = (file.path as NSString).pathExtension
            guard (suffix == "png" && type == "public.png") || (["jpg", "jpeg"].contains(suffix) && type == "public.jpeg") || (suffix == "webp" && type == "org.webmproject.webp") else { throw ContentPackValidationError.unsupportedFile }
        }
    }

    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
