import AppKit
import CoreAudio
import CoreMediaIO
import Defaults
import Foundation
import SwiftUI
import Combine

enum Browser { case safari, chrome, finder }

struct DownloadFile: Identifiable, Equatable {
    let id: String
    let name: String
    let size: Int64
    let formattedSize: String
    let browser: Browser
    let url: URL
}

@MainActor
final class DownloadWatcher: ObservableObject {
    static let shared = DownloadWatcher()
    @Published private(set) var downloadFiles: [DownloadFile] = []
    @Published private(set) var recentlyCompletedName: String?
    private var priorFiles: [String: DownloadFile] = [:]
    private var observedSizes: [String: Int64] = [:]
    private var completionTask: Task<Void, Never>?
    private var timer: Timer?
    struct Folder: Codable, Identifiable { var id = UUID(); let name: String; let bookmark: Data }
    @Published private(set) var folders: [Folder] = []
    @Published private(set) var folderError: String?
    private var observations = Set<AnyCancellable>()
    private var sources: [any DispatchSourceFileSystemObject] = []
    private var roots: [URL] = []
    private var pendingScan: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var generation = 0
    private var locked = false
    private let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!

    private init() {
        if let data = UserDefaults.standard.data(forKey: "downloads.additionalFolders"), data.count <= 900_000,
           let decoded = try? JSONDecoder().decode([Folder].self, from: data) {
            folders = Array(decoded.filter { $0.bookmark.count <= 100_000 && $0.name.count <= 100 }.prefix(8))
        }
        Defaults.publisher(.enableDownloadListener).receive(on: RunLoop.main).sink { [weak self] _ in self?.configure() }.store(in: &observations)
        WorkspaceModeManager.shared.$session.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.configure() }.store(in: &observations)
        configure()
    }
    func setLocked(_ value: Bool) { locked = value; configure() }
    func chooseFolder() {
        guard WorkspaceAccess.privateToolsAllowed, Defaults[.enableDownloadListener], folders.count < 8 else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Watch this folder’s top level for downloads. Subfolders are not scanned."
        panel.begin { [weak self] result in
            Task { @MainActor in
                guard let self, WorkspaceAccess.privateToolsAllowed, result == .OK, let url = panel.url,
                      self.folders.count < 8, let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
                self.folders.append(.init(name: String(url.lastPathComponent.prefix(100)), bookmark: data)); self.saveFolders(); self.configure()
            }
        }
    }
    func removeFolder(_ id: UUID) { guard WorkspaceAccess.privateToolsAllowed else { return }; folders.removeAll { $0.id == id }; saveFolders(); configure() }
    private func saveFolders() { if let data = try? JSONEncoder().encode(folders) { UserDefaults.standard.set(data, forKey: "downloads.additionalFolders") } }
    private func configure() {
        generation += 1; timer?.invalidate(); timer = nil; pendingScan?.cancel(); scanTask?.cancel()
        sources.forEach { $0.cancel() }; sources = []; roots = []; observedSizes = [:]; priorFiles = [:]; downloadFiles = []
        completionTask?.cancel(); recentlyCompletedName = nil
        guard Defaults[.enableDownloadListener], !locked, WorkspaceModeManager.shared.active?.hidesPrivateContent != true else { return }
        folderError = nil
        var resolved: [(URL, Bool)] = [(downloadsURL, false)]
        for folder in folders {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: folder.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale), !stale, url.startAccessingSecurityScopedResource() { resolved.append((url, true)) }
            else { folderError = "Choose an unavailable folder again to renew access." }
        }
        var seen = Set<String>()
        for (url, scoped) in resolved {
            guard seen.insert(url.standardizedFileURL.path).inserted else { if scoped { url.stopAccessingSecurityScopedResource() }; continue }
            let fd = open(url.path, O_EVTONLY)
            guard fd >= 0 else { if scoped { url.stopAccessingSecurityScopedResource() }; continue }
            roots.append(url)
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .global(qos: .utility))
            source.setEventHandler { [weak self] in Task { @MainActor in self?.scheduleScan() } }
            source.setCancelHandler { close(fd); if scoped { url.stopAccessingSecurityScopedResource() } }
            sources.append(source); source.resume()
        }
        scheduleScan()
    }
    private func scheduleScan() {
        pendingScan?.cancel()
        pendingScan = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard !Task.isCancelled else { return }; self?.scan()
        }
    }

    func reveal(_ download: DownloadFile) {
        NSWorkspace.shared.activateFileViewerSelecting([download.url])
    }

    private func scan() {
        guard Defaults[.enableDownloadListener], !locked, WorkspaceModeManager.shared.active?.hidesPrivateContent != true else { return }
        scanTask?.cancel()
        let ticket = generation, roots = roots, sizes = observedSizes
        scanTask = Task { [weak self] in
        let snapshot = await Task.detached(priority: .utility) { () -> ([DownloadFile], [String: Int64]) in
        let keys: Set<URLResourceKey> = [.fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        var urls: [URL] = []
        for root in roots {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants, .skipsHiddenFiles]) else { continue }
            urls.append(contentsOf: walker.prefix(500).compactMap { $0 as? URL })
        }
        let temporaryExtensions = ["download", "crdownload", "part"]
        let files = urls.compactMap { url -> DownloadFile? in
            let ext = url.pathExtension.lowercased()
            let values = try? url.resourceValues(forKeys: keys)
            let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            let isTemporary = temporaryExtensions.contains(ext)
            let wasObserved = sizes[url.path] != nil
            let isGrowing = wasObserved && sizes[url.path] != size
                && (values?.contentModificationDate?.timeIntervalSinceNow ?? -.infinity) > -120
            guard isTemporary || (isGrowing && size > 1_000_000) else { return nil }
            let browser: Browser = ext == "download" ? .safari
                : ext == "crdownload" ? .chrome : .finder
            return DownloadFile(
                id: url.path,
                name: url.deletingPathExtension().lastPathComponent,
                size: size,
                formattedSize: ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                browser: browser,
                url: url
            )
        }.sorted { $0.size > $1.size }
        let measurements = Dictionary(urls.map { url in
            let values = try? url.resourceValues(forKeys: keys)
            return (url.path, Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0))
        }, uniquingKeysWith: { first, _ in first })
        return (Array(files.prefix(40)), measurements)
        }.value
        guard !Task.isCancelled, let self, ticket == generation, !locked,
              WorkspaceModeManager.shared.active?.hidesPrivateContent != true else { return }
        let files = snapshot.0
        let current = Dictionary(files.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let completed = priorFiles.values.first(where: { current[$0.id] == nil }) {
            recentlyCompletedName = completed.name
            completionTask?.cancel()
            completionTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                self?.recentlyCompletedName = nil
            }
        }
        priorFiles = current
        observedSizes = snapshot.1
        downloadFiles = files
        timer?.invalidate(); timer = nil
        if !files.isEmpty {
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in Task { @MainActor in self?.scan() } }
            timer?.tolerance = 0.4
        }
        }
    }
}

@MainActor
final class NotchTimerManager: ObservableObject {
    static let shared = NotchTimerManager()
    @Published private(set) var endDate: Date?
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var label = "Timer"
    @Published private(set) var justFinished = false
    private var timer: Timer?

    private init() {}

    func start(minutes: Int, label: String? = nil) {
        self.label = label ?? "\(minutes)-minute timer"
        endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        justFinished = false
        tick()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func cancel() {
        timer?.invalidate(); timer = nil; endDate = nil
        remainingSeconds = 0; justFinished = false
    }

    private func tick() {
        guard let endDate else { return }
        remainingSeconds = max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
        guard remainingSeconds == 0 else { return }
        timer?.invalidate(); timer = nil; self.endDate = nil; justFinished = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.justFinished = false
        }
    }
}

@MainActor
final class PrivacyActivityMonitor: ObservableObject {
    static let shared = PrivacyActivityMonitor()
    @Published private(set) var microphoneInUse = false
    @Published private(set) var cameraInUse = false
    @Published private(set) var shouldShowActivity = false
    private var timer: Timer?
    private var hideActivityTask: Task<Void, Never>?

    private init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        guard Defaults[.privacyActivitiesEnabled] else {
            microphoneInUse = false
            cameraInUse = false
            shouldShowActivity = false
            hideActivityTask?.cancel()
            return
        }

        let newMicrophoneInUse = Self.defaultInputDeviceIsRunning()
        let newCameraInUse = Self.anyCameraIsRunning()
        let newlyActivated = (newMicrophoneInUse && !microphoneInUse)
            || (newCameraInUse && !cameraInUse)

        microphoneInUse = newMicrophoneInUse
        cameraInUse = newCameraInUse

        guard newlyActivated else { return }
        shouldShowActivity = true
        hideActivityTask?.cancel()
        hideActivityTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.shouldShowActivity = false
        }
    }

    private nonisolated static func defaultInputDeviceIsRunning() -> Bool {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else { return false }
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    private nonisolated static func anyCameraIsRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return false }
        var devices = [CMIODeviceID](repeating: 0, count: Int(size) / MemoryLayout<CMIODeviceID>.size)
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &size, &devices) == noErr else { return false }
        for device in devices {
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            if CMIOObjectGetPropertyData(CMIOObjectID(device), &runningAddress, 0, nil, runningSize, &runningSize, &running) == noErr,
               running != 0 { return true }
        }
        return false
    }
}

struct DownloadArea: View {
    @ObservedObject private var watcher = DownloadWatcher.shared
    var body: some View {
        if let download = watcher.downloadFiles.first {
            Label(download.name, systemImage: "arrow.down.circle.fill")
        }
    }
}
