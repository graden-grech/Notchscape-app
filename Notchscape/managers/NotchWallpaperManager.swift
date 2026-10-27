import AppKit
import Combine
import ImageIO

/// This integration intentionally imports neither MacScapes analytics nor its
/// updater. Notchscape keeps its own identity, preferences and update feed.
@MainActor
final class NotchWallpaperManager: ObservableObject {
    static let shared = NotchWallpaperManager()
    @Published private(set) var favorites: Set<String>
    @Published var platform: WallpaperPlatform { didSet { defaults.set(platform.rawValue, forKey: "wallpapers.collection") } }
    @Published var rotation: WallpaperRotation { didSet { defaults.set(rotation.rawValue, forKey: "wallpapers.rotation"); scheduleRotation() } }
    @Published var display: String { didSet { defaults.set(display, forKey: "wallpapers.display") } }
    @Published private(set) var busy = false
    @Published private(set) var status: String?
    @Published private(set) var failed = false
    @Published private(set) var lastApplied: String?
    @Published private(set) var canUndo = false
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var automaticRequest = false
    private var locked = false
    private var modeObservation: AnyCancellable?
    private var previous: [(String, URL, [NSWorkspace.DesktopImageOptionKey: Any])] = []
    private init() {
        let defaults = UserDefaults.standard
        favorites = Set(defaults.stringArray(forKey: "wallpapers.favorites") ?? [])
            .intersection(Set(WallpaperCatalog.everyWallpaper.map(\.id)))
        platform = WallpaperPlatform(rawValue: defaults.string(forKey: "wallpapers.collection") ?? "macOS") ?? .macOS
        rotation = WallpaperRotation(rawValue: defaults.string(forKey: "wallpapers.rotation") ?? "off") ?? .off
        display = defaults.string(forKey: "wallpapers.display") ?? "main"
        lastApplied = defaults.string(forKey: "wallpapers.lastApplied")
        modeObservation = WorkspaceModeManager.shared.$session.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] session in
                guard let self else { return }
                if session?.mode.pauseWallpapers == true && automaticRequest { task?.cancel() }
                scheduleRotation()
            }
    }
    func start(locked: Bool) { self.locked = locked; scheduleRotation() }
    func setLocked(_ value: Bool) {
        locked = value
        if value { task?.cancel(); NotchWallpaperWindowController.shared.close() }
        scheduleRotation()
    }
    func toggleFavorite(_ wallpaper: Wallpaper) {
        if favorites.contains(wallpaper.id) { favorites.remove(wallpaper.id) }
        else { favorites.insert(wallpaper.id) }
        defaults.set(favorites.sorted(), forKey: "wallpapers.favorites")
    }
    func importMacScapesFavorites() {
        let old = UserDefaults(suiteName: "com.gradengrech.macscapes")?.stringArray(forKey: "favoriteWallpaperIDs") ?? []
        let valid = Set(old).intersection(Set(WallpaperCatalog.everyWallpaper.map(\.id)))
        guard !valid.isEmpty else {
            failed = false; status = "No saved MacScapes favorites were available to import. Nothing was changed."
            return
        }
        let added = valid.subtracting(favorites).count
        favorites.formUnion(valid)
        defaults.set(favorites.sorted(), forKey: "wallpapers.favorites")
        failed = false; status = "Imported \(added) new \(added == 1 ? "favorite" : "favorites"). The original MacScapes settings were not changed."
    }
    private func rotate() {
        guard let wallpaper = WallpaperPolicy.pool(platform: platform, favorites: favorites, previous: lastApplied).randomElement() else { return }
        apply(wallpaper, automatic: true)
    }
    func apply(_ wallpaper: Wallpaper) { apply(wallpaper, automatic: false) }
    private func apply(_ wallpaper: Wallpaper, automatic: Bool) {
        guard !locked, !busy, WallpaperCatalog.everyWallpaper.contains(wallpaper),
              !automatic || WorkspaceModeManager.shared.active?.pauseWallpapers != true else { return }
        let target = display // Capture the user's choice for this request.
        busy = true; automaticRequest = automatic; failed = false; status = "Downloading \(wallpaper.name)…"
        task = Task {
            defer { busy = false; automaticRequest = false; task = nil }
            do {
                let file = try await WallpaperFileStore.shared.file(for: wallpaper)
                try Task.checkCancellation()
                guard !locked else { return }
                // A mode may have started while the automatic download awaited.
                // Explicit user Apply/Undo remains available; rotation stays paused.
                guard !automatic || WorkspaceModeManager.shared.active?.pauseWallpapers != true else { throw CancellationError() }
                let screens = target == "all" ? NSScreen.screens :
                    (target == "main" ? NSScreen.main.map { [$0] } ?? [] : NSScreen.screens.filter { $0.displayUUID == target })
                guard !screens.isEmpty else { throw WallpaperLoadError.displayUnavailable }
                let old = screens.compactMap { screen -> (String, URL, [NSWorkspace.DesktopImageOptionKey: Any])? in
                    guard let id = screen.displayUUID, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
                    return (id, url, NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:])
                }
                do {
                    for screen in screens {
                        try NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: [
                            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true])
                    }
                } catch {
                    restore(old)
                    throw error
                }
                previous = old; canUndo = !old.isEmpty
                lastApplied = wallpaper.id; defaults.set(wallpaper.id, forKey: "wallpapers.lastApplied")
                status = "\(wallpaper.name) applied."
            } catch is CancellationError { status = nil }
            catch { failed = true; status = error.localizedDescription }
        }
    }
    func undo() {
        guard !locked, !busy, canUndo else { return }
        do {
            guard previous.contains(where: { snapshot in NSScreen.screens.contains { $0.displayUUID == snapshot.0 } }) else {
                throw WallpaperLoadError.displayUnavailable
            }
            var restored: Set<String> = []
            for (id, url, options) in previous {
                guard let screen = NSScreen.screens.first(where: { $0.displayUUID == id }) else { continue }
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
                restored.insert(id)
            }
            previous.removeAll { restored.contains($0.0) }
            canUndo = !previous.isEmpty; failed = false
            status = previous.isEmpty ? "Previous wallpaper restored." : "Restored connected displays. Reconnect the remaining display to finish Undo."
            lastApplied = nil; defaults.removeObject(forKey: "wallpapers.lastApplied")
        } catch { failed = true; status = "The previous wallpaper could not be restored: \(error.localizedDescription)" }
    }
    private func restore(_ snapshots: [(String, URL, [NSWorkspace.DesktopImageOptionKey: Any])]) {
        for (id, url, options) in snapshots {
            if let screen = NSScreen.screens.first(where: { $0.displayUUID == id }) {
                try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
            }
        }
    }
    private func scheduleRotation() {
        timer?.invalidate(); timer = nil
        guard !locked, WorkspaceModeManager.shared.active?.pauseWallpapers != true,
              let seconds = rotation.seconds else { return }
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.busy, !self.locked,
                      WorkspaceModeManager.shared.active?.pauseWallpapers != true else { return }
                self.rotate()
            }
        }
        timer?.tolerance = min(60, seconds * 0.05)
    }
}

enum WallpaperLoadError: LocalizedError {
    case invalidSource, invalidImage, tooLarge, displayUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidSource: "This wallpaper source is unavailable. Please try a different image."
        case .invalidImage: "The downloaded file is not a supported image."
        case .tooLarge: "The wallpaper exceeds the safe download size."
        case .displayUnavailable: "That display is disconnected. Choose a connected display and try again."
        }
    }
}

/// Cancels oversized transfers and disallows redirects outside the catalog's
/// HTTPS hosts. No cookies, accounts, analytics or arbitrary URL downloads.
private final class WallpaperTransferGuard: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let limit: Int64
    init(limit: Int64) { self.limit = limit }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit { downloadTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(WallpaperPolicy.allowedURL) == true ? request : nil)
    }
}

actor WallpaperFileStore {
    static let shared = WallpaperFileStore()
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 120
        config.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: config)
    }()
    private let thumbnails = NSCache<NSString, NSImage>()
    init() { thumbnails.countLimit = 48; thumbnails.totalCostLimit = 16_000_000 }
    private func download(_ url: URL, limit: Int64) async throws -> URL {
        guard WallpaperPolicy.allowedURL(url) else { throw WallpaperLoadError.invalidSource }
        let (file, response) = try await session.download(from: url, delegate: WallpaperTransferGuard(limit: limit))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let finalURL = response.url, WallpaperPolicy.allowedURL(finalURL) else {
            try? FileManager.default.removeItem(at: file); throw WallpaperLoadError.invalidSource
        }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= limit else { try? FileManager.default.removeItem(at: file); throw WallpaperLoadError.tooLarge }
        return file
    }
    private func validImage(_ url: URL) -> CGImageSource? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 30_000, height <= 30_000,
              width * height <= 100_000_000 else { return nil }
        return source
    }
    func file(for wallpaper: Wallpaper) async throws -> URL {
        guard WallpaperPolicy.safeID(wallpaper.id), WallpaperCatalog.everyWallpaper.contains(wallpaper) else { throw WallpaperLoadError.invalidSource }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("theboringteam.boringnotch/Wallpapers", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = ["png", "bmp", "jpeg", "jpg"].contains(wallpaper.downloadURL.pathExtension.lowercased()) ? wallpaper.downloadURL.pathExtension.lowercased() : "jpg"
        let destination = directory.appendingPathComponent("\(wallpaper.id).\(ext)")
        if FileManager.default.fileExists(atPath: destination.path), validImage(destination) != nil { return destination }
        let downloaded = try await download(wallpaper.downloadURL, limit: WallpaperPolicy.maximumDownloadBytes)
        defer { try? FileManager.default.removeItem(at: downloaded) }
        try Task.checkCancellation()
        guard validImage(downloaded) != nil else { throw WallpaperLoadError.invalidImage }
        // Atomic replacement only within our own per-ID wallpaper cache.
        let staging = directory.appendingPathComponent(".\(UUID().uuidString).download")
        try FileManager.default.copyItem(at: downloaded, to: staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else { try FileManager.default.moveItem(at: staging, to: destination) }
        return destination
    }
    func thumbnail(_ url: URL, detail: Bool = false) async throws -> NSImage {
        let maximumPixels = detail ? 1600 : 640
        let cacheKey = "\(url.absoluteString)|\(maximumPixels)" as NSString
        if let cached = thumbnails.object(forKey: cacheKey) { return cached }
        let file = try await download(url, limit: 12_000_000)
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        guard let source = validImage(file), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary) else { throw WallpaperLoadError.invalidImage }
        let image = NSImage(cgImage: cg, size: .zero)
        thumbnails.setObject(image, forKey: cacheKey, cost: cg.bytesPerRow * cg.height)
        return image
    }
}
