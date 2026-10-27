import AppKit
import SwiftUI
import Vision
import UniformTypeIdentifiers
import Combine

@MainActor
final class CaptureStudio: ObservableObject {
    static let shared = CaptureStudio()
    @Published var image: CGImage?
    @Published var marks: [CaptureMark] = []
    @Published var tool: CaptureMarkupTool = .redact
    @Published var text = ""
    @Published var message: String?
    @Published private(set) var files: [URL] = []
    @Published private(set) var indexing = false
    @Published private(set) var indexedCount = 0
    @Published private(set) var libraryName: String?
    private var index: [URL: String] = [:]
    private var generation = 0
    private var indexTask: Task<Void, Never>?
    private let bookmarkKey = "capture.libraryBookmark"
    func chooseImage() {
        guard WorkspaceAccess.privateToolsAllowed else { return }
        let token = generation
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        panel.message = "Edit a selected image locally. Your original is never changed."
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in guard let self, self.generation == token else { return }; self.open(url) }
        }
    }
    func open(_ url: URL) {
        guard WorkspaceAccess.privateToolsAllowed else { return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let loaded = CaptureImagePolicy.load(url) else { message = "Choose an image under 30 MB and 40 megapixels."; return }
        image = loaded; marks = []; message = nil
    }
    func export() {
        guard WorkspaceAccess.privateToolsAllowed, image != nil else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "Edited Capture.png"
        panel.message = "Export flattened PNG pixels. Original metadata and editable layers are not included."
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self, WorkspaceAccess.privateToolsAllowed, let image = self.image, let rendered = CaptureImagePolicy.render(image, marks: self.marks), let data = CaptureImagePolicy.png(rendered) else { return }
                do { try data.write(to: url, options: .atomic); self.message = "Exported a flattened PNG. Original kept unchanged." }
                catch { self.message = "The PNG couldn’t be saved." }
            }
        }
    }
    func chooseLibrary() {
        guard WorkspaceAccess.privateToolsAllowed else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.message = "Opt in to a local capture folder. Only images you explicitly save are added. OCR search stays in memory and clears when this window closes."
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self, WorkspaceAccess.privateToolsAllowed,
                      let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
                UserDefaults.standard.set(bookmark, forKey: self.bookmarkKey); self.reloadLibrary()
            }
        }
    }
    private func withLibrary<T>(_ body: (URL) throws -> T) rethrows -> T? {
        guard WorkspaceAccess.privateToolsAllowed, let data = UserDefaults.standard.data(forKey: bookmarkKey), data.count <= 100_000 else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale), !stale, url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }; return try body(url)
    }
    func reloadLibrary() {
        files = []; libraryName = nil
        _ = withLibrary { folder in
            libraryName = folder.lastPathComponent
            files = Array(((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []).filter {
                guard CaptureImagePolicy.isManagedFile($0.lastPathComponent), let v = try? $0.resourceValues(forKeys: [.isRegularFileKey,.isSymbolicLinkKey]) else { return false }
                return v.isRegularFile == true && v.isSymbolicLink != true
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(200))
        }
    }
    func saveInLibrary() {
        guard WorkspaceAccess.privateToolsAllowed, let image, let rendered = CaptureImagePolicy.render(image, marks: marks), let data = CaptureImagePolicy.png(rendered), data.count <= 30_000_000 else { message = "Choose a smaller image before saving to the library."; return }
        do {
            let saved: Void? = try withLibrary({ folder in
                let entries = (try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])).filter { CaptureImagePolicy.isManagedFile($0.lastPathComponent) }
                let bytes = entries.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
                guard entries.count < 200, bytes + data.count <= 500_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
                try data.write(to: folder.appendingPathComponent("Notchscape-Capture-\(UUID().uuidString).png"), options: .withoutOverwriting)
            })
            guard saved != nil else { message = "Choose a library folder first."; return }
            reloadLibrary(); message = "Saved only this flattened image in your library."
        } catch { message = "Library limit: 200 captures / 500 MB. Review cleanup or choose another folder." }
    }
    func startIndex() {
        guard WorkspaceAccess.privateToolsAllowed, !indexing else { return }
        indexTask?.cancel(); index = [:]; indexedCount = 0; indexing = true; generation += 1; let token = generation
        // Scoped access spans the bounded task and is always released.
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { indexing = false; return }
        var stale = false
        guard let folder = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale), !stale, folder.startAccessingSecurityScopedResource() else { indexing = false; return }
        let urls = Array(files.prefix(100))
        indexTask = Task { [weak self] in
            defer { folder.stopAccessingSecurityScopedResource(); if self?.generation == token { self?.indexing = false } }
            for url in urls {
                guard !Task.isCancelled, let self, generation == token, WorkspaceAccess.privateToolsAllowed else { return }
                let result = await Task.detached(priority: .utility) { () -> String in
                    guard let image = CaptureImagePolicy.load(url, thumbnail: 1600) else { return "" }
                    let request = VNRecognizeTextRequest(); request.recognitionLevel = .fast
                    try? VNImageRequestHandler(cgImage: image).perform([request])
                    return String((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").prefix(20_000))
                }.value
                guard !Task.isCancelled, generation == token, WorkspaceAccess.privateToolsAllowed else { return }
                index[url] = result; indexedCount += 1
            }
        }
    }
    func matches(_ url: URL, query: String) -> Bool { query.isEmpty || url.lastPathComponent.localizedCaseInsensitiveContains(query) || index[url]?.localizedCaseInsensitiveContains(query) == true }
    func cleanupCandidates(days: Int) -> [URL] {
        guard [7,30,90].contains(days) else { return [] }
        let cutoff = Date().addingTimeInterval(-Double(days)*86400)
        return files.filter { ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantFuture) < cutoff }
    }
    func cleanup(_ candidates: [URL]) {
        var removed = 0
        _ = withLibrary { folder in
            for url in candidates.prefix(200) where CaptureImagePolicy.isManagedFile(url.lastPathComponent) && url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL {
                if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil { removed += 1 }
            }
        }
        index = [:]; reloadLibrary(); message = "Moved \(removed) selected old capture(s) to Trash. Other files were kept."
    }
    func disconnectLibrary() { clearPrivate(); UserDefaults.standard.removeObject(forKey: bookmarkKey); libraryName = nil; files = []; message = "Library disconnected. Its images are kept." }
    func clearPrivate() { generation += 1; indexTask?.cancel(); indexTask = nil; index = [:]; indexedCount = 0; indexing = false; image = nil; marks = []; text = ""; files = [] }
}

@MainActor
final class CaptureStudioController: NSWindowController, NSWindowDelegate {
    static let shared = CaptureStudioController()
    private init() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 860, height: 650), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Capture Studio"; window.minSize = .init(width: 660, height: 500); window.isReleasedWhenClosed = false; window.sharingType = .none
        window.toolbar = NSToolbar(identifier: "CaptureStudio"); window.toolbarStyle = .unified; window.titlebarSeparatorStyle = .none
        window.contentView = NSHostingView(rootView: CaptureStudioView().background(LiquidGlassSettingsBackground()))
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }
    func show() { guard WorkspaceAccess.privateToolsAllowed else { return }; window?.center(); showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil); CaptureStudio.shared.reloadLibrary() }
    override func close() { CaptureStudio.shared.clearPrivate(); MediaToolsManager.shared.privacyStop(); super.close() }
    func windowWillClose(_ notification: Notification) { CaptureStudio.shared.clearPrivate(); MediaToolsManager.shared.privacyStop() }
}

private struct CaptureStudioView: View {
    @ObservedObject private var studio = CaptureStudio.shared
    @State private var page = 0
    @State private var query = ""
    @State private var retention = 30
    @State private var cleanup: [URL] = []
    @State private var placing = false
    @State private var x1 = 20.0
    @State private var y1 = 20.0
    @State private var x2 = 65.0
    @State private var y2 = 65.0
    var body: some View {
        VStack(spacing: 10) {
            Picker("Capture tool", selection: $page) { Text("Markup").tag(0); Text("Library").tag(1); Text("Recording & Conversion").tag(2) }.pickerStyle(.segmented).frame(maxWidth: 550).padding(.top, 12)
            if page == 0 {
                HStack {
                    Button("Choose Image…") { studio.chooseImage() }
                    Picker("Tool", selection: $studio.tool) { ForEach(CaptureMarkupTool.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 160)
                    if studio.tool == .text { TextField("Annotation text", text: $studio.text).frame(maxWidth: 160) }
                    Spacer(); Button("Undo Mark") { if !studio.marks.isEmpty { studio.marks.removeLast() } }.disabled(studio.marks.isEmpty)
                }
                if studio.image != nil { CaptureCanvas().background(.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 12)).clipped().accessibilityLabel("Image markup canvas. Choose a tool and drag across the image. Text is placed at the start of the drag.") }
                else { ContentUnavailableView("Choose an Image", systemImage: "photo.badge.plus", description: Text("Arrows, text, cropping, and opaque redaction. No background screen capture.")) }
                HStack { Button("Place Mark…") { placing = true }.disabled(studio.image == nil || studio.marks.count >= 200); Text("Drag or enter positions. Redactions are flattened.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Save in Library") { studio.saveInLibrary() }.disabled(studio.image == nil); Button("Export PNG…") { studio.export() }.disabled(studio.image == nil) }
            } else if page == 1 {
                HStack { Text(studio.libraryName ?? "Capture Library is off").font(.headline); Spacer(); Button("Choose Folder…") { studio.chooseLibrary() }; Button("Disconnect") { studio.disconnectLibrary() }.disabled(studio.libraryName == nil) }
                HStack { TextField("Search indexed text or filename", text: $query); Button(studio.indexing ? "Indexing \(studio.indexedCount)/100…" : "Index Up to 100 Captures") { studio.startIndex() }.disabled(studio.indexing || studio.files.isEmpty) }
                List(studio.files.filter { studio.matches($0, query: query) }, id: \.self) { url in
                    HStack { Label(url.lastPathComponent, systemImage: "photo").lineLimit(1); Spacer(); Button("Edit") { studio.open(url); page = 0 }; Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                }
                HStack { Picker("Review captures older than", selection: $retention) { ForEach([7,30,90], id: \.self) { Text("\($0) days").tag($0) } }.frame(width: 270); Button("Review Cleanup…") { cleanup = studio.cleanupCandidates(days: retention) }.disabled(studio.cleanupCandidates(days: retention).isEmpty); Spacer(); Text("\(studio.files.count)/200 captures · 500 MB maximum").font(.caption) }
                Text("Explicit saves only. Only Notchscape-created PNG files are indexed or cleaned up. OCR text stays in memory; closing this window clears it. Cleanup moves reviewed files to Trash, never other images.").font(.caption).foregroundStyle(.secondary)
            } else { MediaToolsView() }
            if let message = studio.message { Text(message).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(16).controlSize(.small)
            .sheet(isPresented: $placing) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Place \(studio.tool.rawValue)").font(.title2.bold())
                    Text("Positions are percentages from the image’s top-left. Keyboard-accessible alternative to dragging.").foregroundStyle(.secondary)
                    Grid(alignment: .leading) {
                        GridRow { Text("Start X %"); TextField("Start X percent", value: $x1, format: .number) }
                        GridRow { Text("Start Y %"); TextField("Start Y percent", value: $y1, format: .number) }
                        if studio.tool != .text {
                            GridRow { Text("End X %"); TextField("End X percent", value: $x2, format: .number) }
                            GridRow { Text("End Y %"); TextField("End Y percent", value: $y2, format: .number) }
                        } else { GridRow { Text("Text"); TextField("Annotation text", text: $studio.text) } }
                    }.textFieldStyle(.roundedBorder)
                    HStack { Button("Cancel") { placing = false }.keyboardShortcut(.cancelAction); Spacer(); Button("Place Mark") {
                        studio.marks.append(.init(tool: studio.tool, start: .init(x: x1/100,y: y1/100), end: .init(x: x2/100,y: y2/100), text: String(studio.text.prefix(1000)))); placing = false
                    }.disabled(![x1,y1,x2,y2].allSatisfy { $0.isFinite && (0...100).contains($0) } || (studio.tool == .text ? studio.text.isEmpty : x1 == x2 || y1 == y2)) }
                }.padding(24).frame(width: 430)
            }
            .confirmationDialog("Move \(cleanup.count) old captures to Trash?", isPresented: Binding(get: { !cleanup.isEmpty }, set: { if !$0 { cleanup = [] } })) {
                Button("Move to Trash", role: .destructive) { studio.cleanup(cleanup); cleanup = [] }
            } message: { Text("Only the listed \(cleanup.count) Notchscape-created captures older than \(retention) days will be moved. They can be restored from Trash.") }
    }
}

private struct CaptureCanvas: NSViewRepresentable {
    @ObservedObject private var studio = CaptureStudio.shared
    func makeNSView(context: Context) -> AnnotationCanvas { AnnotationCanvas() }
    func updateNSView(_ view: AnnotationCanvas, context: Context) { view.studio = studio; view.preparePreview(); view.needsDisplay = true }
}
private final class AnnotationCanvas: NSView {
    weak var studio: CaptureStudio?
    private var dragStart: CGPoint?
    private var source: CGImage?
    private var thumbnail: CGImage?
    private var cached: CGImage?
    private var cachedMarks: [CaptureMark] = []
    func preparePreview() {
        guard let studio, let image = studio.image else { source = nil; thumbnail = nil; cached = nil; return }
        let changed = source !== image
        if changed { source = image; thumbnail = CaptureImagePolicy.preview(image) }
        let marks = studio.marks.filter { $0.tool != .crop }
        if changed || cachedMarks != marks {
            cachedMarks = marks
            if let thumbnail { cached = CaptureImagePolicy.render(thumbnail, marks: marks) }
        }
    }
    override var isFlipped: Bool { true }
    private var imageRect: CGRect {
        guard let image = studio?.image else { return .zero }
        let scale = min(bounds.width/Double(image.width), bounds.height/Double(image.height))
        let size = CGSize(width: Double(image.width)*scale, height: Double(image.height)*scale)
        return CGRect(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2, width: size.width, height: size.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let studio, let image = studio.image else { return }
        let rect = imageRect
        _ = image
        if let rendered = cached {
            NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height)).draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        if let crop = studio.marks.last(where: { $0.tool == .crop }) {
            let r = crop.normalizedRect; let path = NSBezierPath(rect: CGRect(x: rect.minX+r.minX*rect.width, y: rect.minY+r.minY*rect.height, width: r.width*rect.width, height: r.height*rect.height)); path.setLineDash([4,4], count: 2, phase: 0); path.lineWidth = 2; NSColor.systemYellow.setStroke(); path.stroke()
        }
    }
    private func normalized(_ event: NSEvent) -> CGPoint? {
        let point = convert(event.locationInWindow, from: nil), rect = imageRect
        guard rect.width > 0, rect.height > 0 else { return nil }
        return CGPoint(x: min(1, max(0, (point.x-rect.minX)/rect.width)), y: min(1, max(0, (point.y-rect.minY)/rect.height)))
    }
    override func mouseDown(with event: NSEvent) { guard imageRect.contains(convert(event.locationInWindow, from: nil)) else { return }; dragStart = normalized(event) }
    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        guard WorkspaceAccess.privateToolsAllowed, let studio, studio.marks.count < 200, let start = dragStart, let end = normalized(event) else { return }
        if studio.tool == .text && studio.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        if studio.tool != .text && abs(start.x-end.x)+abs(start.y-end.y) < 0.002 { return }
        studio.marks.append(.init(tool: studio.tool, start: start, end: end, text: String(studio.text.prefix(1000)))); needsDisplay = true
    }
}
