import AppKit

/// Native Finder Services. Only the files explicitly supplied by Finder enter
/// Shelf; conversions reuse Shelf's existing backend and create new temp output.
@MainActor
final class NotchscapeFinderServices: NSObject {
    static let shared = NotchscapeFinderServices()
    @objc func processFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard WorkspaceAccess.privateToolsAllowed else { error.pointee = "Unlock your Mac and end Presentation Mode before using private file tools."; return }
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []).filter(\.isFileURL)
        guard !urls.isEmpty, urls.count <= 20 else { error.pointee = "Select between 1 and 20 local files."; return }
        let operation = userData ?? "shelf"
        guard ["shelf", "png", "pdf"].contains(operation) else { return }
        if operation != "shelf" {
            guard urls.allSatisfy({ CaptureImagePolicy.load($0, thumbnail: 32) != nil }) else { error.pointee = "Image actions accept images under 30 MB and 40 megapixels only."; return }
        }
        Task {
            guard WorkspaceAccess.privateToolsAllowed else { return }
            var outputs: [URL] = []
            do {
                if operation == "png" {
                    for url in urls {
                        guard WorkspaceAccess.privateToolsAllowed else { return }
                        if let output = try await ImageProcessingService.shared.convertImage(from: url, options: .init(format: .png, compressionQuality: 1, maxDimension: 8192, removeMetadata: true)) { outputs.append(output) }
                    }
                } else if operation == "pdf" {
                    if let output = try await ImageProcessingService.shared.createPDF(from: urls) { outputs = [output] }
                } else { outputs = urls }
                guard WorkspaceAccess.privateToolsAllowed else { return }
                let items = outputs.compactMap { url -> ShelfItem? in
                    guard let bookmark = try? Bookmark(url: url) else { return nil }
                    return ShelfItem(kind: .file(bookmark: bookmark.data), isTemporary: operation != "shelf")
                }
                ShelfStateViewModel.shared.add(items)
                let alert = NSAlert(); alert.messageText = operation == "shelf" ? "Added \(items.count) file(s) to Shelf" : "Created \(items.count) output(s) in Shelf"
                alert.informativeText = "Your original files were not changed. Open Shelf to drag, reveal, or save the outputs."
                alert.addButton(withTitle: "OK"); alert.runModal()
            } catch {
                let alert = NSAlert(); alert.messageText = "The file action couldn’t finish"; alert.informativeText = "Your original files were kept. Try a smaller selection in Shelf."; alert.runModal()
            }
        }
    }
}
