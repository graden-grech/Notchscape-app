import AppKit
@preconcurrency import ApplicationServices
import ScreenCaptureKit
import SwiftUI
import KeyboardShortcuts

enum WindowToolsShortcutAction: Hashable, Identifiable, Sendable {
    case placement(WindowPlacement), nextDisplay, previousDisplay, undo
    static var all: [Self] { WindowPlacement.allCases.map(Self.placement) + [.nextDisplay, .previousDisplay, .undo] }
    var id: String {
        switch self {
        case .placement(let placement): "windowTools." + placement.shortcutID
        case .nextDisplay: "windowTools.nextDisplay"
        case .previousDisplay: "windowTools.previousDisplay"
        case .undo: "windowTools.undo"
        }
    }
    var title: String {
        switch self {
        case .placement(let placement): placement.rawValue
        case .nextDisplay: "Next Display"
        case .previousDisplay: "Previous Display"
        case .undo: "Undo Window Move"
        }
    }
    // No initial binding: assigning a shortcut is always an explicit user action.
    var shortcutName: KeyboardShortcuts.Name { .init(id) }
}

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
    @Published private(set) var canUndo = false
    @Published private(set) var gap: Double = 0
    private var undo: [(AXUIElement, CGRect)] = []
    private var generation = 0
    private var scanGeneration = 0
    private var scanTask: Task<Void, Never>?
    private var moveTask: Task<Void, Never>?
    private var moveGeneration = 0
    private var shortcutsRegistered = false
    private var activationTask: Task<Void, Never>?
    private var interfaceVisible = false
    private var displayObserver: NSObjectProtocol?

    func interfaceOpened() {
        guard WorkspaceAccess.privateToolsAllowed else { return }
        interfaceVisible = true
        refresh()
    }
    func setGap(_ value: Double) {
        guard WindowLayoutGeometry.validGap(value) else { return }
        gap = value
    }
    /// Startup registration performs no AX lookup, prompt, preview or movement.
    func registerShortcuts() {
        guard !shortcutsRegistered else { return }
        shortcutsRegistered = true
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.displayConfigurationChanged() }
        }
        for action in WindowToolsShortcutAction.all {
            KeyboardShortcuts.onKeyUp(for: action.shortcutName) { [weak self] in
                Task { @MainActor in self?.performShortcut(action) }
            }
        }
    }
    private func displayConfigurationChanged() {
        moveGeneration += 1; moveTask?.cancel(); moveTask = nil; positioning = false
        undo = []; canUndo = false
        message = "The display arrangement changed. Choose a connected display before positioning."
        if interfaceVisible { refresh() } else { clearPreview() }
    }
    func clearPreview() { generation += 1; preview = nil; previewing = false }
    private func performShortcut(_ action: WindowToolsShortcutAction) {
        guard WorkspaceAccess.privateToolsAllowed, !positioning, AXIsProcessTrusted() else { return }
        if action == .undo { restoreUndo(); return }
        guard let app = NSWorkspace.shared.frontmostApplication, app.activationPolicy == .regular,
              !app.isTerminated, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let displays = NSScreen.screens.map(\.visibleFrame)
        let operation: MoveOperation
        switch action {
        case .placement(let placement): operation = .focusedPlacement(placement, displays: displays, gap: gap)
        case .nextDisplay: operation = .transfer(displays: displays, direction: 1)
        case .previousDisplay: operation = .transfer(displays: displays, direction: -1)
        case .undo: return
        }
        applyMoves([], focusedPID: app.processIdentifier, focusedOperation: operation)
    }
    func requestAccess() { guard WorkspaceAccess.privateToolsAllowed else { return }; _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
    func refresh() {
        guard WorkspaceAccess.privateToolsAllowed else { clearPrivate(); return }
        scanGeneration += 1; scanTask?.cancel(); let token = scanGeneration
        trusted = AXIsProcessTrusted(); clearPreview(); windows = []; refreshing = false
        apps = Array(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.bundleIdentifier != Bundle.main.bundleIdentifier }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }.prefix(80))
        guard trusted else { return }
        refreshing = true
        guard let top = Self.desktopTop else { refreshing = false; return }
        let pids = Array(apps.prefix(40).map(\.processIdentifier))
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
    private struct ScanRow: @unchecked Sendable { let pid: pid_t; let ordinal: Int; let title: String; let element: AXUIElement; let frame: CGRect }
    private nonisolated static func scan(pids: [pid_t], top: CGFloat) -> [ScanRow] {
        var rows: [ScanRow] = []
        let deadline = ContinuousClock.now.advanced(by: .seconds(6))
        // Finite, on-demand AX IPC runs off the main thread, never in a timer.
        for pid in pids {
            guard permitsAXOperation(), ContinuousClock.now < deadline else { break }
            let element = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(element, 0.075)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success, let elements = value as? [AXUIElement] else { continue }
            for (ordinal, window) in elements.prefix(20).enumerated() {
                guard permitsAXOperation(), ContinuousClock.now < deadline else { break }
                AXUIElementSetMessagingTimeout(window, 0.075)
                guard let rect = readFrame(window, top: top), rect.width > 50, rect.height > 30 else { continue }
                var title: CFTypeRef?; AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
                rows.append(.init(pid: pid, ordinal: ordinal, title: String((title as? String ?? "Untitled Window").prefix(300)), element: window, frame: rect))
                if rows.count >= 100 { return rows }
            }
        }; return rows
    }
    private static var desktopTop: CGFloat? { NSScreen.screens.first?.frame.maxY }
    private nonisolated static func readFrame(_ element: AXUIElement, top: CGFloat) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s), [p.x,p.y,s.width,s.height].allSatisfy(\.isFinite) else { return nil }
        let rect = CGRect(x: p.x, y: top-p.y-s.height, width: s.width, height: s.height)
        return WindowLayoutGeometry.valid(rect) ? rect : nil
    }
    func activate(_ window: ManagedWindow) {
        guard WorkspaceAccess.privateToolsAllowed, AXIsProcessTrusted(), !window.app.isTerminated else { return }
        window.app.activate()
        activationTask?.cancel()
        let element = WindowElement(window.element)
        activationTask = Task.detached(priority: .userInitiated) {
            guard Self.permitsAXOperation() else { return }
            AXUIElementSetMessagingTimeout(element.value, 0.075)
            _ = AXUIElementPerformAction(element.value, kAXRaiseAction as CFString)
        }
    }
    func activateApp(_ app: NSRunningApplication) { guard WorkspaceAccess.privateToolsAllowed else { return }; app.activate() }
    private struct WindowElement: @unchecked Sendable { let value: AXUIElement; init(_ value: AXUIElement) { self.value = value } }
    private enum MoveOperation: Sendable {
        case frame(CGRect)
        case placement(WindowPlacement, visible: CGRect, gap: Double)
        case focusedPlacement(WindowPlacement, displays: [CGRect], gap: Double)
        case grid(WindowGridRegion, visible: CGRect, gap: Double)
        case transfer(displays: [CGRect], direction: Int)
        func target(current: CGRect) -> CGRect {
            switch self {
            case .frame(let frame): return frame
            case .placement(let placement, let visible, let gap): return placement.frame(in: visible, current: current, gap: gap)
            case .focusedPlacement(let placement, let displays, let gap):
                guard let index = WindowLayoutGeometry.displayIndex(for: current, in: displays) else { return .null }
                return placement.frame(in: displays[index], current: current, gap: gap)
            case .grid(let region, let visible, let gap): return region.frame(in: visible, gap: gap)
            case .transfer(let displays, let direction): return WindowLayoutGeometry.transferred(current, among: displays, direction: direction)
            }
        }
    }
    private struct MoveRequest: @unchecked Sendable { let element: AXUIElement; let operation: MoveOperation }
    private struct MoveOutcome: @unchecked Sendable {
        var previous: [(AXUIElement, CGRect)] = []
        var completed = 0
        var partial = 0
    }
    private struct MoveAttempt { let changed: Bool; let complete: Bool }
    private nonisolated static func permitsAXOperation() -> Bool {
        guard !Task.isCancelled, AXIsProcessTrusted(),
              let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        func boolean(_ value: Any?) -> Bool? {
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
            return number.boolValue
        }
        guard boolean(session[kCGSessionOnConsoleKey as String]) == true,
              boolean(session[kCGSessionLoginDoneKey as String]) == true else { return false }
        // Normal unlocked sessions omit this key. A present malformed or true
        // value cannot authorize an AX read/write.
        if let locked = session["CGSSessionScreenIsLocked"] {
            guard boolean(locked) == false else { return false }
        }
        return true
    }
    private nonisolated static func move(_ element: AXUIElement, to rect: CGRect, top: CGFloat) -> MoveAttempt {
        guard permitsAXOperation(), WindowLayoutGeometry.valid(rect), rect.width >= 80, rect.height >= 60 else { return .init(changed: false, complete: false) }
        var canPosition = DarwinBoolean(false), canSize = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &canPosition) == .success, canPosition.boolValue,
              AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &canSize) == .success, canSize.boolValue else { return .init(changed: false, complete: false) }
        var p = CGPoint(x: rect.minX, y: top-rect.maxY), s = rect.size
        guard let pos = AXValueCreate(.cgPoint, &p), let size = AXValueCreate(.cgSize, &s), permitsAXOperation() else { return .init(changed: false, complete: false) }
        let first = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, size)
        guard permitsAXOperation() else { return .init(changed: first == .success, complete: false) }
        let second = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, pos)
        guard permitsAXOperation() else { return .init(changed: first == .success || second == .success, complete: false) }
        let last = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, size)
        return .init(changed: first == .success || second == .success || last == .success,
                     complete: first == .success && second == .success && last == .success)
    }
    func place(_ window: ManagedWindow, placement: WindowPlacement, screenIndex: Int) {
        guard WorkspaceAccess.privateToolsAllowed, NSScreen.screens.indices.contains(screenIndex) else { return }
        applyMoves([.init(element: window.element, operation: .placement(placement, visible: NSScreen.screens[screenIndex].visibleFrame, gap: gap))])
    }
    func place(_ window: ManagedWindow, grid: WindowGridRegion, screenIndex: Int) {
        guard WorkspaceAccess.privateToolsAllowed, grid.isValid, NSScreen.screens.indices.contains(screenIndex) else { return }
        applyMoves([.init(element: window.element, operation: .grid(grid, visible: NSScreen.screens[screenIndex].visibleFrame, gap: gap))])
    }
    func transfer(_ window: ManagedWindow, direction: Int) {
        guard WorkspaceAccess.privateToolsAllowed, NSScreen.screens.count > 1, direction == -1 || direction == 1 else { return }
        applyMoves([.init(element: window.element, operation: .transfer(displays: NSScreen.screens.map(\.visibleFrame), direction: direction))])
    }
    func restoreUndo() {
        guard WorkspaceAccess.privateToolsAllowed, !positioning, !undo.isEmpty else { return }
        applyMoves(undo.map { .init(element: $0.0, operation: .frame($0.1)) })
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
        applyMoves(matches.map { .init(element: $0.window.element, operation: .frame($0.frame)) })
    }
    private func applyMoves(_ values: [MoveRequest], focusedPID: pid_t? = nil, focusedOperation: MoveOperation? = nil) {
        guard WorkspaceAccess.privateToolsAllowed, AXIsProcessTrusted(), !positioning,
              !values.isEmpty || (focusedPID != nil && focusedOperation != nil),
              let top = Self.desktopTop, top.isFinite else { return }
        moveGeneration += 1; let token = moveGeneration
        positioning = true; message = "Positioning selected windows…"
        moveTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { () -> MoveOutcome in
                var requests = values
                var outcome = MoveOutcome()
                let deadline = ContinuousClock.now.advanced(by: .seconds(6))
                if let pid = focusedPID, let operation = focusedOperation {
                    guard Self.permitsAXOperation() else { return outcome }
                    let app = AXUIElementCreateApplication(pid)
                    AXUIElementSetMessagingTimeout(app, 0.075)
                    var focused: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused) == .success,
                          let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return outcome }
                    requests = [.init(element: focused as! AXUIElement, operation: operation)]
                }
                for request in requests.prefix(40) {
                    guard Self.permitsAXOperation(), ContinuousClock.now < deadline else { break }
                    AXUIElementSetMessagingTimeout(request.element, 0.075)
                    guard let old = Self.readFrame(request.element, top: top) else { continue }
                    let target = request.operation.target(current: old)
                    let attempt = Self.move(request.element, to: target, top: top)
                    if attempt.changed { outcome.previous.append((request.element, old)) }
                    if attempt.complete { outcome.completed += 1 }
                    else if attempt.changed { outcome.partial += 1 }
                }
                return outcome
            }
            let outcome = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard let self, !Task.isCancelled, moveGeneration == token, WorkspaceAccess.privateToolsAllowed else { return }
            if !outcome.previous.isEmpty { undo = outcome.previous }
            canUndo = !undo.isEmpty
            positioning = false
            if outcome.completed + outcome.partial == 0 {
                message = "No windows moved. The app may not support that size or the selected window may have closed."
            } else {
                message = "Positioned \(outcome.completed) window(s)." +
                    (outcome.partial > 0 ? " \(outcome.partial) changed only partly; Undo is available." : " Undo is available.") +
                    " Apps may enforce minimum sizes."
            }
            // A focused-window shortcut does not enumerate other apps/titles
            // just to update an interface that is closed.
            if interfaceVisible { refresh() }
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
            } catch {
                guard generation == token, WorkspaceAccess.privateToolsAllowed else { return }
                message = "The optional preview couldn’t be captured. No background capture is running."
            }
        }
    }
    func clearPrivate() { generation += 1; scanGeneration += 1; scanTask?.cancel(); scanTask = nil; moveGeneration += 1; moveTask?.cancel(); moveTask = nil; activationTask?.cancel(); activationTask = nil; interfaceVisible = false; positioning = false; refreshing = false; apps = []; windows = []; preview = nil; previewing = false; undo = []; canUndo = false; message = nil }
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
    func show() { guard WorkspaceAccess.privateToolsAllowed else { return }; window?.center(); showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil); WindowToolsManager.shared.interfaceOpened() }
    override func close() { WindowToolsManager.shared.clearPrivate(); super.close() }
    func windowWillClose(_ notification: Notification) { WindowToolsManager.shared.clearPrivate() }
}
private struct WindowToolsDisplayOption: Identifiable {
    let id: UInt32
    let index: Int
    let name: String
}
private struct WindowToolsView: View {
    @ObservedObject private var manager = WindowToolsManager.shared
    @ObservedObject private var tools = LocalToolsManager.shared
    @State private var selected: String?
    @State private var marked = Set<String>()
    @State private var layoutName = ""
    @State private var selectedDisplayID: UInt32?
    @State private var restore: SavedWindowLayout?
    @State private var remove: SavedWindowLayout?
    @State private var expandedGroups: Set<WindowPlacementGroup> = [.halves]
    @State private var gridColumns = 3
    @State private var gridRows = 2
    @State private var gridFirstColumn = 0
    @State private var gridFirstRow = 0
    @State private var gridLastColumn = 0
    @State private var gridLastRow = 0
    @State private var selectingGridEnd = false
    private var gridRegion: WindowGridRegion {
        .init(columns: gridColumns, rows: gridRows, firstColumn: gridFirstColumn, firstRow: gridFirstRow,
              lastColumn: gridLastColumn, lastRow: gridLastRow)
    }
    private var displays: [WindowToolsDisplayOption] {
        NSScreen.screens.enumerated().compactMap { index, screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return .init(id: number.uint32Value, index: index, name: screen.localizedName)
        }
    }
    private var screenIndex: Int? { displays.first { $0.id == selectedDisplayID }?.index }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Windows & Workspaces").font(.title2.bold()); Spacer(); if manager.refreshing || manager.positioning { ProgressView().controlSize(.small) }; Button("Refresh") { manager.refresh() }.disabled(manager.refreshing || manager.positioning); Button("Undo Move") { manager.restoreUndo() }.disabled(manager.positioning || !manager.canUndo) }
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
                            Picker("Display", selection: $selectedDisplayID) {
                                ForEach(displays) { Text($0.name).tag(Optional($0.id)) }
                            }
                            HStack {
                                Button("Previous Display") { manager.transfer(window, direction: -1) }
                                Button("Next Display") { manager.transfer(window, direction: 1) }
                            }.disabled(manager.positioning || NSScreen.screens.count < 2)
                            HStack {
                                Text("Gap")
                                Slider(value: Binding(get: { manager.gap }, set: { manager.setGap($0) }), in: 0...32, step: 1)
                                    .accessibilityLabel("Space around each placed window")
                                Text("\(Int(manager.gap)) pt").monospacedDigit().frame(width: 36, alignment: .trailing)
                            }.help("Space around each placed window. Movement and centering keep the current size.")
                            ForEach(WindowPlacementGroup.allCases) { group in
                                DisclosureGroup(group.rawValue, isExpanded: Binding(get: { expandedGroups.contains(group) }, set: {
                                    if $0 { expandedGroups.insert(group) } else { expandedGroups.remove(group) }
                                })) {
                                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())]) {
                                        ForEach(WindowPlacement.allCases.filter { $0.group == group }) { placement in
                                            Button(placement.rawValue) {
                                                if let screenIndex { manager.place(window, placement: placement, screenIndex: screenIndex) }
                                            }
                                                .frame(maxWidth: .infinity)
                                                .disabled(manager.positioning || !manager.trusted || screenIndex == nil)
                                        }
                                    }.padding(.top, 5)
                                }
                            }
                            DisclosureGroup("Custom Grid") {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Picker("Columns", selection: $gridColumns) { ForEach(1...6, id: \.self) { Text("\($0)").tag($0) } }
                                        Picker("Rows", selection: $gridRows) { ForEach(1...6, id: \.self) { Text("\($0)").tag($0) } }
                                    }
                                    Text("Choose a cell, then an opposite corner to select a larger region. Apply when ready.")
                                        .font(.caption).foregroundStyle(.secondary)
                                    WindowGridSelection(region: gridRegion, select: selectGridCell)
                                    HStack {
                                        Button("Select All") {
                                            gridFirstColumn = 0; gridFirstRow = 0
                                            gridLastColumn = gridColumns - 1; gridLastRow = gridRows - 1; selectingGridEnd = false
                                        }
                                        Spacer()
                                        Button("Apply Grid") {
                                            if let screenIndex { manager.place(window, grid: gridRegion, screenIndex: screenIndex) }
                                        }.disabled(manager.positioning || !manager.trusted || !gridRegion.isValid || screenIndex == nil)
                                    }
                                }.padding(.top, 5)
                            }
                            if let image = manager.preview { Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxHeight: 170).clipShape(RoundedRectangle(cornerRadius: 8)) }
                        } else { Text("Select a window to switch, position, or preview it.").foregroundStyle(.secondary) }
                        DisclosureGroup("Keyboard Shortcuts") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("All shortcuts start unassigned. Position shortcuts act on the focused app’s window; Undo restores the most recent move.")
                                    .font(.caption).foregroundStyle(.secondary)
                                ForEach(WindowPlacementGroup.allCases) { group in
                                    Text(group.rawValue).font(.headline).padding(.top, 4)
                                    ForEach(WindowPlacement.allCases.filter { $0.group == group }) { placement in
                                        KeyboardShortcuts.Recorder(placement.rawValue, name: WindowToolsShortcutAction.placement(placement).shortcutName)
                                    }
                                }
                                Divider()
                                ForEach([WindowToolsShortcutAction.previousDisplay, .nextDisplay, .undo]) { action in
                                    KeyboardShortcuts.Recorder(action.title, name: action.shortcutName)
                                }
                            }.padding(.top, 5)
                        }
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
            .onChange(of: selected) { _, _ in
                manager.clearPreview()
                if let frame = manager.windows.first(where: { $0.id == selected })?.frame,
                   let index = WindowLayoutGeometry.displayIndex(for: frame, in: NSScreen.screens.map(\.visibleFrame)) {
                    selectedDisplayID = displays.first { $0.index == index }?.id
                }
            }
            .onChange(of: gridColumns) { _, _ in resetGridSelection() }
            .onChange(of: gridRows) { _, _ in resetGridSelection() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                if screenIndex == nil { selectedDisplayID = displays.first?.id }
            }
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
    private func resetGridSelection() {
        gridFirstColumn = 0; gridFirstRow = 0; gridLastColumn = 0; gridLastRow = 0; selectingGridEnd = false
    }
    private func selectGridCell(_ column: Int, _ row: Int) {
        if selectingGridEnd {
            gridLastColumn = column; gridLastRow = row; selectingGridEnd = false
        } else {
            gridFirstColumn = column; gridLastColumn = column
            gridFirstRow = row; gridLastRow = row; selectingGridEnd = true
        }
    }
}

/// An abstract layout diagram. It never reads or captures screen contents.
private struct WindowGridSelection: View {
    let region: WindowGridRegion
    let select: (Int, Int) -> Void
    var body: some View {
        GeometryReader { proxy in
            let frame = region.frame(in: CGRect(origin: .zero, size: proxy.size))
            ZStack(alignment: .topLeading) {
                VStack(spacing: 1) {
                    ForEach(0..<region.rows, id: \.self) { row in
                        HStack(spacing: 1) {
                            ForEach(0..<region.columns, id: \.self) { column in
                                Button { select(column, row) } label: {
                                    Rectangle().fill(Color.secondary.opacity(0.08))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .accessibilityLabel("Column \(column + 1), row \(row + 1)")
                                    .accessibilityValue(region.contains(column: column, row: row) ? "Selected" : "Not selected")
                            }
                        }
                    }
                }
                if WindowLayoutGeometry.valid(frame) {
                    Rectangle().fill(Color.accentColor.opacity(0.18))
                        .overlay(Rectangle().strokeBorder(Color.accentColor, lineWidth: 2))
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: proxy.size.height - frame.maxY)
                        .allowsHitTesting(false)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 7))
        }.frame(height: max(100, CGFloat(region.rows) * 24))
            .accessibilityElement(children: .contain).accessibilityLabel("Custom window grid")
    }
}
