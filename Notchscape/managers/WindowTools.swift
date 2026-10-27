import AppKit
import ApplicationServices
import ScreenCaptureKit
import SwiftUI

struct ManagedWindow: Identifiable {
    var id: String
    var app: NSRunningApplication
    var title: String
    var ordinal: Int
    var element: AXUIElement
    var frame: CGRect
}
struct WindowRestoreMatch: Identifiable {
    let id = UUID()
    let window: ManagedWindow
    let frame: CGRect
    let display: String
}
@MainActor
final class WindowToolsManager: ObservableObject {
    static let shared = WindowToolsManager()
    @Published private(set) var apps: [NSRunningApplication] = []
    @Published private(set) var windows: [ManagedWindow] = []
    @Published private(set) var trusted = false
    @Published var message: String?
    @Published private(set) var preview: CGImage?
    @Published private(set) var previewing = false
    @Published private(set) var refreshing = false
    @Published private(set) var positioning = false
    private var undo: [(AXUIElement, CGRect)] = []
    private var generation = 0
    private var scanGeneration = 0
    private var scanTask: Task<Void, Never>?
    private var moveTask: Task<Void, Never>?
    private var moveGeneration = 0
    func requestAccess() { guard WorkspaceAccess.privateToolsAllowed else { return }; _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
    func refresh() {
        guard WorkspaceAccess.privateToolsAllowed else { clearPrivate(); return }
        scanGeneration += 1; scanTask?.cancel(); let token = scanGeneration
        trusted = AXIsProcessTrusted(); preview = nil; windows = []; refreshing = false
        apps = Array(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.bundleIdentifier != Bundle.main.bundleIdentifier }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }.prefix(80))
        guard trusted else { return }
        refreshing = true
        let pids = Array(apps.prefix(40).map(\.processIdentifier)), top = Self.desktopTop
        scanTask = Task { [weak self] in
            let worker = Task.detached(priority: .utility) { Self.scan(pids: pids, top: top) }
            let results = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard let self, !Task.isCancelled, scanGeneration == token, WorkspaceAccess.privateToolsAllowed else { return }
            windows = results.compactMap { row in
                guard let app = apps.first(where: { $0.processIdentifier == row.pid }) else { return nil }
                return .init(id: "\(row.pid)-\(row.ordinal)", app: app, title: row.title, ordinal: row.ordinal, element: row.element, frame: row.frame)
            }
            refreshing = false
        }
    }
    private struct ScanRow { let pid: pid_t; let ordinal: Int; let title: String; let element: AXUIElement; let frame: CGRect }
    private nonisolated static func scan(pids: [pid_t], top: CGFloat) -> [ScanRow] {
        var rows: [ScanRow] = []
        let deadline = ContinuousClock.now.advanced(by: .seconds(6))
        // Finite, on-demand AX IPC runs off the main thread, never in a timer.
        for pid in pids {
            guard !Task.isCancelled, ContinuousClock.now < deadline else { break }
            let element = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(element, 0.075)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success, let elements = value as? [AXUIElement] else { continue }
            for (ordinal, window) in elements.prefix(20).enumerated() {
                guard !Task.isCancelled, ContinuousClock.now < deadline else { break }
                AXUIElementSetMessagingTimeout(window, 0.075)
                guard let rect = readFrame(window, top: top), rect.width > 50, rect.height > 30 else { continue }
                var title: CFTypeRef?; AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
                rows.append(.init(pid: pid, ordinal: ordinal, title: String((title as? String ?? "Untitled Window").prefix(300)), element: window, frame: rect))
                if rows.count >= 100 { return rows }
            }
        }; return rows
    }
    private static var desktopTop: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }
    private static func frame(_ element: AXUIElement) -> CGRect? {
        readFrame(element, top: desktopTop)
    }
    private nonisolated static func readFrame(_ element: AXUIElement, top: CGFloat) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s), [p.x,p.y,s.width,s.height].allSatisfy(\.isFinite) else { return nil }
        return CGRect(x: p.x, y: top-p.y-s.height, width: s.width, height: s.height)
    }
    func activate(_ window: ManagedWindow) {
        guard WorkspaceAccess.privateToolsAllowed, AXIsProcessTrusted(), !window.app.isTerminated else { return }
        window.app.activate(); _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }
    func activateApp(_ app: NSRunningApplication) { guard WorkspaceAccess.privateToolsAllowed else { return }; app.activate() }
    private nonisolated static func move(_ element: AXUIElement, to rect: CGRect, top: CGFloat) -> Bool {
        guard AXIsProcessTrusted(), [rect.minX,rect.minY,rect.width,rect.height].allSatisfy(\.isFinite), rect.width >= 80, rect.height >= 60 else { return false }
        var canPosition = DarwinBoolean(false), canSize = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &canPosition) == .success, canPosition.boolValue,
              AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &canSize) == .success, canSize.boolValue else { return false }
        var p = CGPoint(x: rect.minX, y: top-rect.maxY), s = rect.size
        guard let pos = AXValueCreate(.cgPoint, &p), let size = AXValueCreate(.cgSize, &s) else { return false }
        let first = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, size)
        let second = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, pos)
        _ = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, size)
        return first == .success && second == .success
    }
    func place(_ window: ManagedWindow, placement: WindowPlacement, screenIndex: Int) {
        guard WorkspaceAccess.privateToolsAllowed, NSScreen.screens.indices.contains(screenIndex) else { return }
        let target = placement.frame(in: NSScreen.screens[screenIndex].visibleFrame, current: window.frame)
        applyMoves([(window.element, target)])
    }
    func restoreUndo() {
        guard WorkspaceAccess.privateToolsAllowed else { return }
        let previous = undo; undo = []; applyMoves(previous)
    }
    func saveLayout(name: String, ids: Set<String>) {
        guard WorkspaceAccess.privateToolsAllowed, LocalToolsManager.shared.loaded else { return }
        let positions: [SavedWindowPosition] = windows.filter { ids.contains($0.id) }.prefix(40).compactMap { window in
            guard let bundle = window.app.bundleIdentifier,
                  let screen = NSScreen.screens.max(by: { $0.visibleFrame.intersection(window.frame).area < $1.visibleFrame.intersection(window.frame).area }) else { return nil }
            let v = screen.visibleFrame, f = window.frame.intersection(v)
            guard !f.isNull, v.width > 0, v.height > 0 else { return nil }
            let value = SavedWindowPosition(bundleID: bundle, ordinal: window.ordinal, displayID: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")].map { String(describing: $0) } ?? "", x: (f.minX-v.minX)/v.width, y: (f.minY-v.minY)/v.height, width: f.width/v.width, height: f.height/v.height)
            return value.isValid ? value : nil
        }
        let layout = SavedWindowLayout(name: String(name.prefix(80)), positions: positions)
        guard layout.isValid else { message = "Select at least one resizable window and enter a name."; return }
        LocalToolsManager.shared.saveWindowLayout(layout); message = "Layout saved encrypted on this Mac. No window titles or previews are saved."
    }
    func matches(_ layout: SavedWindowLayout) -> [WindowRestoreMatch] {
        guard WorkspaceAccess.privateToolsAllowed, layout.isValid else { return [] }
        return layout.positions.compactMap { position in
            let candidates = windows.filter { $0.app.bundleIdentifier == position.bundleID && $0.ordinal == position.ordinal }
            guard candidates.count == 1, let window = candidates.first, let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")].map { String(describing: $0) } ?? "") == position.displayID }) ?? NSScreen.main else { return nil }
            return .init(window: window, frame: position.frame(in: screen.visibleFrame), display: screen.localizedName)
        }
    }
    func restore(_ matches: [WindowRestoreMatch]) {
        applyMoves(matches.map { ($0.window.element, $0.frame) })
    }
    private func applyMoves(_ values: [(AXUIElement, CGRect)]) {
        guard WorkspaceAccess.privateToolsAllowed, AXIsProcessTrusted(), !positioning, !values.isEmpty else { return }
        moveGeneration += 1; let token = moveGeneration, top = Self.desktopTop
        positioning = true; message = "Positioning selected windows…"
        moveTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { () -> [(AXUIElement, CGRect)] in
                var previous: [(AXUIElement, CGRect)] = []
                for (element, target) in values.prefix(40) {
                    guard !Task.isCancelled, let session = CGSessionCopyCurrentDictionary() as? [String: Any], session["CGSSessionScreenIsLocked"] as? Bool != true else { break }
                    guard let old = Self.readFrame(element, top: top) else { continue }
                    if Self.move(element, to: target, top: top) { previous.append((element, old)) }
                }
                return previous
            }
            let previous = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard let self, !Task.isCancelled, moveGeneration == token, WorkspaceAccess.privateToolsAllowed else { return }
            undo = previous; positioning = false; message = "Moved \(previous.count) window(s). Apps may enforce minimum sizes. No apps launched or closed. Undo available."
            refresh()
        }
    }
    func previewWindow(_ window: ManagedWindow) {
        guard WorkspaceAccess.privateToolsAllowed, !previewing else { return }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else { message = "Optional previews require Screen Recording access. Switching and positioning work without it."; return }
        generation += 1; let token = generation; previewing = true; preview = nil
        Task {
            defer { if generation == token { previewing = false } }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard generation == token, WorkspaceAccess.privateToolsAllowed else { return }
                let matches = content.windows.filter { $0.owningApplication?.processID == window.app.processIdentifier && $0.title == window.title }
                guard matches.count == 1, let target = matches.first else { message = "This window can’t be identified unambiguously for preview."; return }
                let filter = SCContentFilter(desktopIndependentWindow: target), config = SCStreamConfiguration()
                let scale = min(1, 800/max(1,target.frame.width), 600/max(1,target.frame.height))
                config.width = max(1,Int(target.frame.width*scale)); config.height = max(1,Int(target.frame.height*scale)); config.capturesAudio = false; config.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                guard generation == token, WorkspaceAccess.privateToolsAllowed else { return }; preview = image
            } catch { message = "The optional preview couldn’t be captured. No background capture is running." }
        }
    }
    func clearPrivate() { generation += 1; scanGeneration += 1; scanTask?.cancel(); scanTask = nil; moveGeneration += 1; moveTask?.cancel(); moveTask = nil; positioning = false; refreshing = false; apps = []; windows = []; preview = nil; previewing = false; undo = [] }
}
private extension CGRect { var area: CGFloat { isNull ? 0 : width*height } }

@MainActor
final class WindowToolsController: NSWindowController, NSWindowDelegate {
    static let shared = WindowToolsController()
    private init() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 780, height: 600), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        window.title = "Windows & Workspaces"; window.minSize = .init(width: 650, height: 480); window.sharingType = .none; window.isReleasedWhenClosed = false
        window.toolbar = NSToolbar(identifier: "WindowTools"); window.toolbarStyle = .unified; window.titlebarSeparatorStyle = .none
        window.contentView = NSHostingView(rootView: WindowToolsView().background(LiquidGlassSettingsBackground()))
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }
    func show() { guard WorkspaceAccess.privateToolsAllowed else { return }; window?.center(); showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil); WindowToolsManager.shared.refresh() }
    override func close() { WindowToolsManager.shared.clearPrivate(); super.close() }
    func windowWillClose(_ notification: Notification) { WindowToolsManager.shared.clearPrivate() }
}
private struct WindowToolsView: View {
    @ObservedObject private var manager = WindowToolsManager.shared
    @ObservedObject private var tools = LocalToolsManager.shared
    @State private var selected: String?
    @State private var marked = Set<String>()
    @State private var layoutName = ""
    @State private var screenIndex = 0
    @State private var restore: SavedWindowLayout?
    @State private var remove: SavedWindowLayout?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Windows & Workspaces").font(.title2.bold()); Spacer(); if manager.refreshing || manager.positioning { ProgressView().controlSize(.small) }; Button("Refresh") { manager.refresh() }.disabled(manager.refreshing || manager.positioning); Button("Undo Layout") { manager.restoreUndo() }.disabled(manager.positioning) }
            if !manager.trusted { Label("Window control needs Accessibility access. App switching does not.", systemImage: "hand.raised"); Button("Allow Accessibility…") { manager.requestAccess() } }
            HSplitView {
                VStack(alignment: .leading) {
                    Text("Running Apps").font(.headline)
                    ScrollView { LazyVStack(alignment: .leading) { ForEach(manager.apps, id: \.processIdentifier) { app in Button(app.localizedName ?? "App") { manager.activateApp(app) }.buttonStyle(.plain).padding(4) } } }.frame(maxHeight: 120)
                    Text("Windows").font(.headline)
                    List(manager.windows, selection: $selected) { window in
                        HStack { Toggle("Include in layout", isOn: Binding(get: { marked.contains(window.id) }, set: { if $0 { marked.insert(window.id) } else { marked.remove(window.id) } })).labelsHidden(); VStack(alignment: .leading) { Text(window.title).lineLimit(1); Text(window.app.localizedName ?? "App").font(.caption).foregroundStyle(.secondary) } }.tag(window.id)
                    }
                }.frame(minWidth: 230, idealWidth: 300)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let window = manager.windows.first(where: { $0.id == selected }) {
                            Text(window.title).font(.headline).lineLimit(2)
                            HStack { Button("Switch to Window") { manager.activate(window) }; Button("Preview Once…") { manager.previewWindow(window) }.disabled(manager.previewing) }
                            Picker("Display", selection: $screenIndex) { ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { Text($0.element.localizedName).tag($0.offset) } }
                            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())]) { ForEach(WindowPlacement.allCases) { placement in Button(placement.rawValue) { manager.place(window, placement: placement, screenIndex: screenIndex) }.frame(maxWidth: .infinity).disabled(manager.positioning) } }
                            if let image = manager.preview { Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxHeight: 170).clipShape(RoundedRectangle(cornerRadius: 8)) }
                        } else { Text("Select a window to switch, position, or preview it.").foregroundStyle(.secondary) }
                        Divider()
                        TextField("New layout name", text: $layoutName)
                        Button("Save Checked Windows") { manager.saveLayout(name: layoutName, ids: marked); layoutName = "" }.disabled(marked.isEmpty || layoutName.isEmpty || !tools.loaded || (tools.workspace.windowLayouts?.count ?? 0) >= 20)
                        ForEach(tools.workspace.windowLayouts ?? []) { layout in HStack { Text(layout.name); Spacer(); Button("Review Restore…") { restore = layout }.disabled(manager.refreshing); Button { remove = layout } label: { Image(systemName: "trash") }.help("Remove saved layout") } }
                    }.padding(.leading, 12)
                }.frame(minWidth: 310)
            }
            if let message = manager.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            Text("No apps are launched, closed, or minimized. Layouts store app IDs, window order and relative positions—not titles or previews. Review matches before restoring; app window order can change. Missing displays fall back to the main display.").font(.caption).foregroundStyle(.secondary)
        }.padding(16).controlSize(.small).task { await tools.load() }
            .sheet(item: $restore) { layout in
                let matches = manager.matches(layout)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Restore \(layout.name)?").font(.title2.bold())
                    Text("\(matches.count) of \(layout.positions.count) saved positions match currently open windows. Check these titles before continuing.")
                    List(matches) { match in VStack(alignment: .leading) { Text(match.window.title); Text("\(match.window.app.localizedName ?? "App") → \(match.display)").font(.caption).foregroundStyle(.secondary) } }.frame(minHeight: 180)
                    HStack { Button("Cancel") { restore = nil }.keyboardShortcut(.cancelAction); Spacer(); Button("Restore These Windows") { manager.restore(matches); restore = nil }.disabled(matches.isEmpty) }
                }.padding(24).frame(width: 500)
            }.confirmationDialog("Remove saved layout?", isPresented: Binding(get: { remove != nil }, set: { if !$0 { remove = nil } })) { Button("Remove", role: .destructive) { if let remove { tools.removeWindowLayout(remove.id) }; remove = nil } }
    }
}
