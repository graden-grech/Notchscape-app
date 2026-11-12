import AppKit
import Combine
import Defaults
import SwiftUI
import UniformTypeIdentifiers

extension Defaults.Keys {
    static let dockWorkspaceEnabled = Key<Bool>("dockWorkspaceEnabled", default: false)
    static let dockWorkspaceLayoutData = Key<Data?>("dockWorkspaceLayoutData", default: nil)
}

@MainActor
final class DockWorkspaceManager: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = DockWorkspaceManager()
    @Published private(set) var layout = DockWorkspaceLayout()
    @Published private(set) var isVisible = false
    @Published private(set) var currentDate = Date()
    @Published private(set) var isLayoutReadOnly = false
    @Published var errorMessage: String?
    private var panel: DockWorkspacePanel?
    private var picker: NSOpenPanel?
    private var subscriptions = Set<AnyCancellable>()
    private var clockTask: Task<Void, Never>?
    private var started = false
    private var systemAwake = true
    private var displayAwake = true
    private var sessionActive = true
    private var lockFence = true
    private var systemLease = false
    private var actionGeneration: UInt64 = 0
    private var icons: [UUID: NSImage] = [:]

    private override init() {
        super.init()
        reload()
    }

    func start() {
        guard !started else { return }; started = true
        systemAwake = true; sessionActive = true
        lockFence = !Self.consoleUnlocked
        displayAwake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
        Defaults.publisher(.dockWorkspaceEnabled).receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            if !privacy.permitsDisplay { hide() }
        }.store(in: &subscriptions)
        Defaults.publisher(.dockWorkspaceLayoutData).receive(on: RunLoop.main).sink { [weak self] _ in
            self?.reload()
        }.store(in: &subscriptions)
        WorkspaceModeManager.shared.$session.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            if !privacy.permitsDisplay { hide() }
        }.store(in: &subscriptions)
        let center = NSWorkspace.shared.notificationCenter
        observe(center, NSWorkspace.willSleepNotification) { $0.systemAwake = false; $0.hide() }
        observe(center, NSWorkspace.didWakeNotification) {
            $0.systemAwake = true; $0.displayAwake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
        }
        observe(center, NSWorkspace.screensDidSleepNotification) { $0.displayAwake = false; $0.hide() }
        observe(center, NSWorkspace.screensDidWakeNotification) { $0.displayAwake = true }
        observe(center, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionActive = false; $0.hide() }
        observe(center, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionActive = true }
        observe(NotificationCenter.default, NSApplication.willTerminateNotification) { $0.stop() }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { $0.hide() }
        observe(NotificationCenter.default, .NSSystemClockDidChange) { $0.currentDate = Date(); $0.configureProviders() }
        observe(NotificationCenter.default, .NSSystemTimeZoneDidChange) { $0.currentDate = Date() }
        DistributedNotificationCenter.default().publisher(for: .init("com.apple.screenIsLocked"))
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.lockFence = true; self?.hide() }.store(in: &subscriptions)
        DistributedNotificationCenter.default().publisher(for: .init("com.apple.screenIsUnlocked"))
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard Self.consoleUnlocked else { return }; self?.lockFence = false
            }.store(in: &subscriptions)
    }

    func stop() {
        hide(); subscriptions.removeAll(); started = false
        panel?.delegate = nil; panel = nil
    }

    func show() {
        start()
        guard privacy.permitsDisplay else {
            errorMessage = Defaults[.dockWorkspaceEnabled]
                ? "Dock is unavailable while your Mac is locked, asleep, or in Presentation mode."
                : "Turn on Dock in Settings to open it."
            if !Defaults[.dockWorkspaceEnabled] { SettingsWindowController.shared.showWindow(section: "Dock") }
            return
        }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main,
              let frame = DockWorkspacePolicy.panelFrame(in: screen.visibleFrame) else {
            errorMessage = "This display does not have enough visible space for Dock."; return
        }
        if panel == nil {
            let value = DockWorkspacePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            value.title = "Notchscape Dock"
            value.isReleasedWhenClosed = false; value.isOpaque = false; value.backgroundColor = .clear
            value.hasShadow = true; value.level = .floating; value.hidesOnDeactivate = false
            value.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            value.isMovableByWindowBackground = true; value.delegate = self
            value.onDismiss = { [weak self] in self?.hide() }
            panel = value
        }
        icons.removeAll()
        if !isLayoutReadOnly { errorMessage = nil }
        currentDate = Date()
        panel?.setFrame(frame, display: false)
        panel?.contentView = NSHostingView(rootView: DockWorkspacePanelView(manager: self, panelWidth: frame.width)
            .frame(width: frame.width, height: frame.height))
        isVisible = true; configureProviders(); panel?.makeKeyAndOrderFront(nil)
    }

    /// Closing is never a layout reset. All transient content and provider
    /// demand end synchronously; unlock/wake never opens the panel again.
    func hide() {
        actionGeneration &+= 1
        picker?.cancel(nil); picker = nil
        isVisible = false; panel?.orderOut(nil); panel?.contentView = nil
        icons.removeAll(); configureProviders()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }

    private var privacy: DockWorkspacePrivacy {
        .init(enabled: Defaults[.dockWorkspaceEnabled], unlocked: !lockFence && Self.consoleUnlocked,
              awake: systemAwake && displayAwake, activeSession: sessionActive,
              presenting: WorkspaceModeManager.shared.active?.hidesPrivateContent == true)
    }
    private static var consoleUnlocked: Bool {
        LocalDesktopSessionPolicy.permitsDisplay(session: CGSessionCopyCurrentDictionary() as? [String: Any],
                                                currentUID: getuid(), effectiveUID: geteuid())
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping @MainActor (DockWorkspaceManager) -> Void) {
        center.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }; action(self)
        }.store(in: &subscriptions)
    }

    private func configureProviders() {
        clockTask?.cancel(); clockTask = nil
        let visible = isVisible && privacy.permitsDisplay
        let needsSystem = visible && layout.widgets.contains(.system)
        if needsSystem != systemLease {
            systemLease = needsSystem
            if needsSystem { SystemPerformanceManager.shared.startSampling() }
            else { SystemPerformanceManager.shared.stopSampling() }
        }
        guard visible, layout.widgets.contains(where: { $0 == .clock || $0 == .calendar }) else { return }
        // Clock/date advance at minute boundaries only while their card exists.
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let seconds = max(1, 60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60))
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                guard !Task.isCancelled, let self, isVisible, privacy.permitsDisplay else { return }
                currentDate = Date()
            }
        }
    }

    private func reload() {
        let saved = Defaults[.dockWorkspaceLayoutData]
        if let decoded = DockWorkspacePolicy.decode(saved) {
            isLayoutReadOnly = false
            if decoded != layout { layout = decoded; icons.removeAll(); configureProviders() }
        } else if saved != nil {
            // Do not overwrite a corrupt or future-schema layout with defaults.
            isLayoutReadOnly = true
            errorMessage = "The saved Dock layout could not be read. Its data has been kept, and layout editing is unavailable."
        } else {
            isLayoutReadOnly = false
        }
    }
    private func save(_ updated: DockWorkspaceLayout) {
        guard !isLayoutReadOnly else {
            errorMessage = "The saved Dock layout could not be read. Its data has been kept, and layout editing is unavailable."; return
        }
        guard updated.isValid, let data = try? JSONEncoder().encode(updated),
              data.count <= DockWorkspacePolicy.maximumLayoutBytes else {
            errorMessage = "This Dock layout could not be saved."; return
        }
        layout = updated; Defaults[.dockWorkspaceLayoutData] = data; configureProviders()
    }

    func setWidget(_ widget: DockWorkspaceWidget, enabled: Bool) {
        var updated = layout
        if enabled, !updated.widgets.contains(widget) { updated.widgets.append(widget) }
        if !enabled { updated.widgets.removeAll { $0 == widget } }
        save(updated)
    }
    func moveWidget(_ widget: DockWorkspaceWidget, by direction: Int) {
        var updated = layout; updated.widgets = DockWorkspacePolicy.moving(widget, by: direction, in: layout.widgets); save(updated)
    }
    func reorderWidget(_ widget: DockWorkspaceWidget, before target: DockWorkspaceWidget) {
        var updated = layout; updated.widgets = DockWorkspacePolicy.placing(widget, at: target, in: layout.widgets); save(updated)
    }
    func removePin(_ id: UUID) {
        var updated = layout; updated.pins.removeAll { $0.id == id }; icons[id] = nil; save(updated)
    }
    func movePin(_ id: UUID, by direction: Int) {
        var updated = layout
        let ids = DockWorkspacePolicy.moving(id, by: direction, in: layout.pins.map(\.id))
        updated.pins = ids.compactMap { id in layout.pins.first { $0.id == id } }; save(updated)
    }
    func reorderPin(_ id: UUID, before target: UUID) {
        var updated = layout
        let ids = DockWorkspacePolicy.placing(id, at: target, in: layout.pins.map(\.id))
        updated.pins = ids.compactMap { id in layout.pins.first { $0.id == id } }; save(updated)
    }

    func addPin(kind: DockWorkspacePin.Kind) {
        start()
        guard privacy.permitsDisplay, picker == nil, !isLayoutReadOnly else { return }
        guard layout.pins.count < DockWorkspacePolicy.maximumPins else {
            errorMessage = "Dock supports up to \(DockWorkspacePolicy.maximumPins) pinned apps and folders."; return
        }
        let value = NSOpenPanel(); picker = value
        value.title = kind == .application ? "Add an App to Dock" : "Add a Folder to Dock"
        value.prompt = "Add"; value.allowsMultipleSelection = false
        value.canChooseFiles = kind == .application; value.canChooseDirectories = kind == .folder
        value.treatsFilePackagesAsDirectories = false
        if kind == .application {
            value.allowedContentTypes = [.applicationBundle]; value.directoryURL = URL(fileURLWithPath: "/Applications")
        }
        let generation = actionGeneration
        value.begin { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, picker === value else { return }; picker = nil
                guard response == .OK, generation == actionGeneration, privacy.permitsDisplay,
                      let url = value.url, url.isFileURL else { return }
                do {
                    let resource = try url.resourceValues(forKeys: [.isDirectoryKey, .isApplicationKey])
                    guard resource.isDirectory == true,
                          (kind == .folder ? resource.isApplication != true : resource.isApplication == true) else {
                        errorMessage = "Choose an installed app or a normal folder."; return
                    }
                    let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                    let name = DockWorkspacePolicy.title(kind == .application ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent)
                    let pin = DockWorkspacePin(id: UUID(), title: name, kind: kind, bookmark: bookmark)
                    guard pin.isValid, layout.pins.count < DockWorkspacePolicy.maximumPins else {
                        errorMessage = "This item could not be added to Dock."; return
                    }
                    var updated = layout; updated.pins.append(pin); save(updated)
                } catch { errorMessage = "The item could not be saved. Choose it again to retry." }
            }
        }
    }

    private func resolve(_ pin: DockWorkspacePin, refreshBookmark: Bool = false) -> URL? {
        guard privacy.permitsDisplay, pin.isValid else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: pin.bookmark, options: [.withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &stale), url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isApplicationKey]),
              values.isDirectory == true,
              (pin.kind == .folder ? values.isApplication != true : values.isApplication == true) else { return nil }
        if refreshBookmark, stale, let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
           bookmark.count <= DockWorkspacePolicy.maximumBookmarkBytes,
           let index = layout.pins.firstIndex(where: { $0.id == pin.id }) {
            var updated = layout; updated.pins[index].bookmark = bookmark; save(updated)
        }
        return url
    }

    func icon(for pin: DockWorkspacePin) -> NSImage? {
        guard isVisible, privacy.permitsDisplay else { return nil }
        if let image = icons[pin.id] { return image }
        guard let url = resolve(pin) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path); icons[pin.id] = image; return image
    }

    func open(_ pin: DockWorkspacePin) {
        guard privacy.permitsDisplay, let url = resolve(pin, refreshBookmark: true) else {
            errorMessage = "This item is unavailable. It may have moved or been removed. Remove its pin and add it again."; return
        }
        if pin.kind == .folder {
            if NSWorkspace.shared.open(url) { hide() }
            else { errorMessage = "Finder could not open this folder." }
        } else {
            let config = NSWorkspace.OpenConfiguration(); config.activates = true
            let generation = actionGeneration
            NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
                Task { @MainActor [weak self] in
                    guard let self, generation == actionGeneration, privacy.permitsDisplay else { return }
                    if error == nil { hide() } else { errorMessage = "This app could not be opened." }
                }
            }
        }
    }
}

@MainActor
private final class DockWorkspacePanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}
