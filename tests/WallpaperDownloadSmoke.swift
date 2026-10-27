import AppKit
import Foundation
import Combine

// Compile alongside the real store and NSScreen+UUID.swift. The test never
// starts a window, changes a desktop, enables rotation, or reads private files.
@MainActor
final class NotchWallpaperWindowController {
    static let shared = NotchWallpaperWindowController()
    func close() {}
}

@MainActor
final class WorkspaceModeManager: ObservableObject {
    static let shared = WorkspaceModeManager()
    @Published var session: WorkspaceModeSession?
    var active: WorkspaceMode? { session?.mode }
}

@main
struct WallpaperDownloadSmoke {
    static func main() async throws {
        let cases = [WallpaperCatalog.all[0], WallpaperCatalog.all.first { $0.id == "sequoia-sunrise" }!,
                     WindowsWallpaperCatalog.all[0], SeasonalInternetCatalog.all[0], SpaceWallpaperCatalog.all[0]]
        for item in cases {
            let image = try await WallpaperFileStore.shared.thumbnail(item.previewURL)
            precondition(image.size.width > 0 && image.size.width <= 640)
            print("PASS: bounded image preview for \(item.id)")
        }
        if CommandLine.arguments.contains("--detail") {
            let image = try await WallpaperFileStore.shared.thumbnail(SpaceWallpaperCatalog.all[0].detailPreviewURL, detail: true)
            precondition(max(image.size.width, image.size.height) > 640 && max(image.size.width, image.size.height) <= 1600)
            print("PASS: bounded Retina detail preview; desktop untouched")
        }
        if CommandLine.arguments.contains("--download") {
            let file = try await WallpaperFileStore.shared.file(for: WallpaperCatalog.all[0])
            precondition(FileManager.default.fileExists(atPath: file.path))
            print("PASS: validated full-resolution wallpaper download; desktop untouched")
        }
    }
}
