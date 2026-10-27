import AppKit
import Combine
import CryptoKit
import Defaults
import Security
import Vision
import UniformTypeIdentifiers
import ImageIO
import KeyboardShortcuts

/// A separate, device-only key; never reuses or touches account credentials.
actor LocalToolsVault {
    private struct Snapshot: Codable {
        var clipboard: [ClipboardEntry]
        var notes: [QuickNote]
        var appleNotes: AppleNotesState?
        var workspace: PersonalWorkspace?
    }
    private var key: SymmetricKey?
    private var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("theboringteam.boringnotch/PrivateTools", isDirectory: true)
            .appendingPathComponent("contents.encrypted")
    }
    private func encryptionKey() throws -> SymmetricKey {
        if let key { return key }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "theboringteam.boringnotch.private-tools",
            kSecAttrAccount as String: "local-encryption-v1"]
        var result: CFTypeRef?
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            let value = SymmetricKey(data: data); key = value; return value
        }
        guard status == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        // Never replace a missing key over existing encrypted data.
        guard !FileManager.default.fileExists(atPath: file.path) else { throw CocoaError(.fileReadNoPermission) }
        let value = SymmetricKey(size: .bits256)
        var insert = query
        insert[kSecValueData as String] = value.withUnsafeBytes { Data($0) }
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(insert as CFDictionary, nil)
        guard added == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(added)) }
        key = value
        return value
    }
    func load() throws -> ([ClipboardEntry], [QuickNote], AppleNotesState, PersonalWorkspace) {
        let key = try encryptionKey()
        guard FileManager.default.fileExists(atPath: file.path) else { return ([], [], .init(), .init()) }
        let data = try Data(contentsOf: file)
        guard data.count < 64_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: clear)
        return (snapshot.clipboard, snapshot.notes, snapshot.appleNotes ?? .init(), snapshot.workspace?.bounded ?? .init())
    }
    func save(clipboard: [ClipboardEntry], notes: [QuickNote], appleNotes: AppleNotesState, workspace: PersonalWorkspace) throws {
        let key = try encryptionKey()
        let data = try JSONEncoder().encode(Snapshot(clipboard: clipboard, notes: notes, appleNotes: appleNotes, workspace: workspace.bounded))
        // Link baselines add to the snapshot. Never write a file that the bounded
        // loader would reject on the next launch; retain the previous file.
        guard data.count < 63_999_936 else { throw CocoaError(.fileWriteOutOfSpace) }
        guard let encrypted = try AES.GCM.seal(data, using: key).combined else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try encrypted.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

@MainActor
final class LocalToolsManager: ObservableObject {
    static let shared = LocalToolsManager()
    @Published private(set) var clipboard: [ClipboardEntry] = []
    @Published private(set) var notes: [QuickNote] = []
    @Published private(set) var appleNotesState = AppleNotesState()
    @Published private(set) var workspace = PersonalWorkspace()
    @Published private(set) var loaded = false
    @Published private(set) var paused = false
    @Published var selectedNote: UUID?
    @Published var selectedTool: NotchTool = .clipboard
    @Published private(set) var error: String?
    @Published var captureText = ""
    @Published private(set) var capturedCodes: [String] = []
    @Published private(set) var recognizing = false
    @Published private(set) var needsSave = false
    private let vault = LocalToolsVault()
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var timer: Timer?
    private var changeCount = NSPasteboard.general.changeCount
    private var observations = Set<AnyCancellable>()
    private var started = false
    private var locked = false
    private var userPaused = false
    private var revision = 0
    private var captureGeneration = 0
    private var clipboardGeneration = 0
    private var privateContentHidden: Bool { WorkspaceModeManager.shared.active?.hidesPrivateContent == true }

    func start() {
        guard !started else { return }; started = true
        Defaults.publisher(.clipboardHistoryEnabled).receive(on: RunLoop.main).sink { [weak self] _ in self?.configureClipboard() }.store(in: &observations)
        Defaults.publisher(.clipboardRetentionDays).dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.prune() }.store(in: &observations)
        Defaults.publisher(.textCaptureEnabled).receive(on: RunLoop.main).sink { [weak self] change in
            self?.configureShortcuts()
            if !change.newValue { self?.captureGeneration += 1; self?.captureText = ""; self?.capturedCodes = [] }
        }.store(in: &observations)
        Defaults.publisher(.agentUsageEnabled).dropFirst().receive(on: RunLoop.main).sink { change in
            if !change.newValue { AgentInsightsManager.shared.clear() }
        }.store(in: &observations)
        WorkspaceModeManager.shared.$session.dropFirst().receive(on: RunLoop.main).sink { [weak self] session in
            guard let self else { return }
            if session?.mode.hidesPrivateContent == true { captureGeneration += 1; captureText = ""; capturedCodes = [] }
            configureClipboard()
        }.store(in: &observations)
        configureClipboard()
    }
    func load() async {
        if let loadTask { await loadTask.value; return }
        guard !loaded else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await vault.load()
                clipboard = ClipboardPolicy.retained(snapshot.0, now: Date(), days: Defaults[.clipboardRetentionDays])
                notes = Array(snapshot.1.prefix(100)).map { var n = $0; n.text = NotePolicy.bounded(n.text); return n }
                appleNotesState = snapshot.2
                workspace = snapshot.3
                loaded = true; error = nil
            } catch { self.error = "Private tools couldn’t open their encrypted storage. Nothing has been replaced." }
        }
        loadTask = task; await task.value; loadTask = nil
    }
    private func configureClipboard() {
        clipboardGeneration += 1
        paused = locked || userPaused || privateContentHidden
        configureShortcuts()
        timer?.invalidate(); timer = nil
        changeCount = NSPasteboard.general.changeCount // Never capture an old copy on opt-in/unlock.
        guard Defaults[.clipboardHistoryEnabled], !paused else { return }
        Task { await load() }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkClipboard() }
        }
        timer?.tolerance = 0.3
    }
    func setLocked(_ locked: Bool) {
        if locked { captureGeneration += 1 }
        self.locked = locked; captureText = ""; capturedCodes = []
        configureClipboard()
    }
    func pause(_ value: Bool) { userPaused = value; configureClipboard() }
    private func configureShortcuts() {
        if Defaults[.clipboardHistoryEnabled] && !locked && !privateContentHidden { KeyboardShortcuts.enable(.clipboardHistoryPanel) }
        else { KeyboardShortcuts.disable(.clipboardHistoryPanel) }
        if Defaults[.textCaptureEnabled] && !locked && !privateContentHidden { KeyboardShortcuts.enable(.captureNotchText) }
        else { KeyboardShortcuts.disable(.captureNotchText) }
    }
    private func checkClipboard() {
        guard ClipboardPolicy.recordingAllowed(enabled: Defaults[.clipboardHistoryEnabled], loaded: loaded,
                                               locked: locked, userPaused: userPaused || privateContentHidden) else { return }
        let board = NSPasteboard.general
        guard board.changeCount != changeCount else { return }
        changeCount = board.changeCount
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let extra = Set(Defaults[.clipboardExcludedApps].split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init))
        let allTypes = Set((board.pasteboardItems ?? []).flatMap { $0.types.map(\.rawValue) })
        guard ClipboardPolicy.canCapture(types: allTypes, source: source, exclusions: ClipboardPolicy.excludedApps.union(extra)),
              !allTypes.contains(NSPasteboard.PasteboardType.fileURL.rawValue) else { return }
        var entry = ClipboardEntry(source: NSWorkspace.shared.frontmostApplication?.localizedName ?? "App")
        if let text = board.string(forType: .string), !text.isEmpty, text.utf8.count <= 500_000 {
            entry.text = text
        } else if let data = board.data(forType: .png), data.count <= 2_000_000 {
            entry.image = data
        } else if let data = board.data(forType: .tiff), data.count <= 2_000_000 {
            let pending = entry
            let generation = clipboardGeneration
            Task {
                let encoded = await Task.detached(priority: .utility) { () -> Data? in
                    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: 1200,
                            kCGImageSourceCreateThumbnailWithTransform: true
                          ] as CFDictionary) else { return nil }
                    let output = NSMutableData()
                    guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
                    CGImageDestinationAddImage(destination, image, nil)
                    guard CGImageDestinationFinalize(destination), output.length <= 2_000_000 else { return nil }
                    return output as Data
                }.value
                guard ClipboardPolicy.recordingAllowed(enabled: Defaults[.clipboardHistoryEnabled], loaded: loaded,
                                                       locked: locked, userPaused: userPaused || privateContentHidden),
                      generation == clipboardGeneration, let encoded else { return }
                var converted = pending; converted.image = encoded; addClipboardEntry(converted)
            }
            return
        } else { return }
        addClipboardEntry(entry)
    }
    private func addClipboardEntry(_ value: ClipboardEntry) {
        var entry = value
        // Keep a pin on duplicate copies rather than creating unbounded copies.
        if let duplicate = clipboard.first(where: { $0.text == entry.text && $0.image == entry.image }) {
            entry.id = duplicate.id; entry.pinned = duplicate.pinned
            clipboard.removeAll { $0.id == duplicate.id }
        }
        clipboard.insert(entry, at: 0); prune()
    }
    func copy(_ entry: ClipboardEntry) {
        let board = NSPasteboard.general; board.clearContents()
        if let text = entry.text { board.setString(text, forType: .string) }
        else if let image = entry.image { board.setData(image, forType: .png) }
        changeCount = board.changeCount
    }
    func pin(_ entry: ClipboardEntry) {
        guard let index = clipboard.firstIndex(where: { $0.id == entry.id }) else { return }
        clipboard[index].pinned.toggle(); prune()
    }
    func remove(_ entry: ClipboardEntry) { clipboard.removeAll { $0.id == entry.id }; persist() }
    func clearClipboard() { clipboard.removeAll { !$0.pinned }; persist() }
    private func prune() {
        guard loaded else { return }
        clipboard = ClipboardPolicy.retained(clipboard, now: Date(), days: Defaults[.clipboardRetentionDays]); persist()
    }
    func addNote() {
        guard loaded, notes.count < 100 else { return }
        let note = QuickNote(); notes.insert(note, at: 0); selectedNote = note.id; persist()
    }
    func updateNote(_ id: UUID, text: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].text = NotePolicy.bounded(text); notes[i].modified = Date(); persist()
    }
    func removeNote(_ id: UUID) {
        if let link = notes.first(where: { $0.id == id })?.appleNote {
            appleNotesState.ignoredRemoteIDs.insert(link.remoteID)
        }
        notes.removeAll { $0.id == id }; selectedNote = notes.first?.id; persist()
    }
    func setAppleNotesScope(_ scope: AppleNotesScope) { appleNotesState.scope = scope; persist() }
    func ignoreAppleNote(_ remoteID: String) { appleNotesState.ignoredRemoteIDs.insert(remoteID); persist() }
    func disconnectAppleNotes() {
        for index in notes.indices { notes[index].appleNote = nil }
        appleNotesState = .init(); persist()
    }
    func updateAppleNote(_ id: UUID, remoteID: String, baseText: String, text: String? = nil) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if let text { notes[index].text = text; notes[index].modified = Date() }
        notes[index].appleNote = .init(remoteID: remoteID, baseText: baseText)
        persist()
    }
    @discardableResult
    func importAppleNote(remoteID: String, text: String) -> Bool {
        guard loaded, notes.count < 100, !appleNotesState.ignoredRemoteIDs.contains(remoteID),
              !notes.contains(where: { $0.appleNote?.remoteID == remoteID }) else { return false }
        notes.insert(QuickNote(text: text, appleNote: .init(remoteID: remoteID, baseText: text)), at: 0)
        persist(); return true
    }
    @discardableResult
    func keepAppleNotesConflict(_ id: UUID, remoteID: String, remoteText: String) -> Bool {
        guard let note = notes.first(where: { $0.id == id }), notes.count < 100 else { return false }
        let copy = QuickNote(text: note.text, isConflictCopy: true)
        notes.insert(copy, at: 0)
        updateAppleNote(id, remoteID: remoteID, baseText: remoteText, text: remoteText)
        return true
    }
    private func persist() {
        guard loaded else { return }
        revision += 1; needsSave = true
        let savingRevision = revision
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            do {
                try await vault.save(clipboard: clipboard, notes: notes, appleNotes: appleNotesState, workspace: workspace)
                if revision == savingRevision { needsSave = false; error = nil }
            }
            catch { self.error = "Changes couldn’t be saved. Keep this window open and try again." }
        }
    }
    func flush() async {
        saveTask?.cancel()
        guard loaded, needsSave else { return }
        let savingRevision = revision
        do {
            try await vault.save(clipboard: clipboard, notes: notes, appleNotes: appleNotesState, workspace: workspace)
            if revision == savingRevision { needsSave = false }
        }
        catch { self.error = "Changes couldn’t be saved." }
    }
    func saveSnippet(id: UUID? = nil, name: String, text: String) {
        guard loaded, !locked, !privateContentHidden, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !text.isEmpty, text.count <= 20_000, name.count <= 80 else { return }
        let value = TextSnippet(id: id ?? UUID(), name: name, text: text)
        if let index = workspace.snippets.firstIndex(where: { $0.id == value.id }) { workspace.snippets[index] = value }
        else if workspace.snippets.count < 100 { workspace.snippets.append(value) }
        persist()
    }
    func removeSnippet(_ id: UUID) { guard !locked, !privateContentHidden else { return }; workspace.snippets.removeAll { $0.id == id }; persist() }
    func copySnippet(_ value: TextSnippet) {
        guard !locked, !privateContentHidden, workspace.snippets.contains(value) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value.text, forType: .string)
        NSPasteboard.general.setString("", forType: .init("org.nspasteboard.AutoGeneratedType"))
        changeCount = NSPasteboard.general.changeCount
    }
    func saveQuicklink(name: String, template: String) {
        guard loaded, !locked, !privateContentHidden, workspace.links.count < 100,
              !name.isEmpty, name.count <= 80, QuicklinkPolicy.url(template, query: "test") != nil else { return }
        workspace.links.append(.init(name: name, template: template)); persist()
    }
    func chooseQuicklinkFolder() {
        guard loaded, !locked, !privateContentHidden, workspace.links.count < 100 else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.message = "Choose a folder for a named Quicklink. Notchscape won’t scan its contents."
        panel.begin { [weak self] result in
            Task { @MainActor in
                guard let self, !self.locked, !self.privateContentHidden, result == .OK, let url = panel.url,
                      let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil),
                      self.workspace.links.count < 100 else { return }
                self.workspace.links.append(.init(name: String(url.lastPathComponent.prefix(80)), template: "", folderBookmark: data)); self.persist()
            }
        }
    }
    func removeQuicklink(_ id: UUID) { guard !locked, !privateContentHidden else { return }; workspace.links.removeAll { $0.id == id }; persist() }
    func openQuicklink(_ link: NamedQuicklink, query: String = "") {
        guard !locked, !privateContentHidden, workspace.links.contains(link) else { return }
        if let bookmark = link.folderBookmark {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale),
                  !stale, url.startAccessingSecurityScopedResource() else { error = "Choose this Quicklink’s folder again to renew access."; return }
            defer { url.stopAccessingSecurityScopedResource() }; NSWorkspace.shared.open(url)
        } else if let url = QuicklinkPolicy.url(link.template, query: query) { NSWorkspace.shared.open(url) }
    }
    func saveSwatch(_ hex: String) {
        guard loaded, !locked, !privateContentHidden, workspace.swatches.count < 100,
              let normalized = ColorFormatPolicy.format(hex, as: .hex), !workspace.swatches.contains(where: { $0.hex == normalized }) else { return }
        workspace.swatches.append(.init(name: normalized, hex: normalized)); persist()
    }
    func removeSwatch(_ id: UUID) { guard !locked, !privateContentHidden else { return }; workspace.swatches.removeAll { $0.id == id }; persist() }
    func saveWindowLayout(_ layout: SavedWindowLayout) {
        guard loaded, !locked, !privateContentHidden, layout.isValid, (workspace.windowLayouts?.count ?? 0) < 20 else { return }
        if workspace.windowLayouts == nil { workspace.windowLayouts = [] }
        workspace.windowLayouts?.append(layout); persist()
    }
    func removeWindowLayout(_ id: UUID) { guard loaded, !locked, !privateContentHidden else { return }; workspace.windowLayouts?.removeAll { $0.id == id }; persist() }
    func recognizeImageFile() {
        guard Defaults[.textCaptureEnabled], !locked, !privateContentHidden, !recognizing else { return }
        captureGeneration += 1; captureText = ""; capturedCodes = []
        let generation = captureGeneration
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        panel.message = "Choose a screenshot or image. Text recognition stays on this Mac."
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self, generation == self.captureGeneration else { return }
                await self.recognize(url)
            }
        }
    }
    func captureScreenText() {
        guard Defaults[.textCaptureEnabled], !locked, !privateContentHidden, !recognizing else { return }
        // Use the system's interactive region picker. No background capture or
        // continuous screen stream; Esc cancels without touching the clipboard.
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            error = "Allow Screen Recording in System Settings to capture a region, or choose an image instead."; return
        }
        captureGeneration += 1; captureText = ""; capturedCodes = []
        recognizing = true; error = nil
        let generation = captureGeneration
        Task {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("notch-ocr-\(UUID().uuidString).png")
            let result = await Task.detached(priority: .userInitiated) { () -> Int32 in
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i", "-r", "-x", "-t", "png", url.path]
                process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                do { try process.run(); process.waitUntilExit(); return process.terminationStatus } catch { return -1 }
            }.value
            recognizing = false
            defer { try? FileManager.default.removeItem(at: url) }
            if generation == captureGeneration, result == 0, FileManager.default.fileExists(atPath: url.path) { await recognize(url) }
        }
    }
    private func recognize(_ url: URL) async {
        guard Defaults[.textCaptureEnabled], !locked, !privateContentHidden else { return }
        let generation = captureGeneration
        recognizing = true; error = nil
        let result = await Task.detached(priority: .userInitiated) { () -> (String, [String])? in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  (attrs[.size] as? NSNumber)?.intValue ?? Int.max < 30_000_000,
                  let image = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int,
                  let height = props[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 30_000, height <= 30_000,
                  Double(width)*Double(height) <= 100_000_000 else { return nil }
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true; request.automaticallyDetectsLanguage = true
            let barcodes = VNDetectBarcodesRequest()
            do {
                try VNImageRequestHandler(url: url).perform([request, barcodes])
                let text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
                let codes = Array(Set((barcodes.results ?? []).compactMap(\.payloadStringValue).filter { !$0.isEmpty && $0.count <= 4096 })).sorted()
                return (text, Array(codes.prefix(20)))
            } catch { return nil }
        }.value
        recognizing = false
        guard !locked, !privateContentHidden, Defaults[.textCaptureEnabled], generation == captureGeneration else { return }
        if let result, !result.0.isEmpty || !result.1.isEmpty { captureText = String(result.0.prefix(100_000)); capturedCodes = result.1 }
        else { error = "No readable text found. Try a sharper image under 30 MB." }
    }
    func copyCapture() {
        guard !locked, !privateContentHidden, !captureText.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(captureText, forType: .string)
    }
    func copyCode(_ value: String) {
        guard !locked, !privateContentHidden, capturedCodes.contains(value) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
        NSPasteboard.general.setString("", forType: .init("org.nspasteboard.AutoGeneratedType")); changeCount = NSPasteboard.general.changeCount
    }
}
