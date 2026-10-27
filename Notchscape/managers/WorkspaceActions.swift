import AppKit
import SwiftUI
import AppIntents

enum WorkspaceAccess {
    @MainActor static var unlocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool != true
    }
    @MainActor static var privateToolsAllowed: Bool { unlocked && WorkspaceModeManager.shared.active?.hidesPrivateContent != true }
}

struct WorkspaceAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let keywords: String
    let perform: @MainActor () -> Void
}

@MainActor
enum WorkspaceActions {
    static var all: [WorkspaceAction] {
        var actions: [WorkspaceAction] = [
            .init(id: "tools", title: "Open Tools", symbol: "square.grid.2x2", keywords: "clipboard notes devices utilities") { NotchToolsWindowController.shared.show(.utilities) },
            .init(id: "workspace", title: "Open Workspace Tools", symbol: "command", keywords: "calculator snippets quicklinks stopwatch focus keep awake") { WorkspaceToolsWindowController.shared.show() },
            .init(id: "wallpapers", title: "Open Wallpaper Library", symbol: "photo", keywords: "background themes space") { NotchWallpaperWindowController.shared.show() },
            .init(id: "scratchpad", title: "Open Pinned Scratchpad", symbol: "pin", keywords: "notes floating window") { PinnedScratchpadController.shared.show() },
            .init(id: "capture", title: "Open Capture Studio", symbol: "viewfinder", keywords: "markup redact crop library record trim video audio gif") { CaptureStudioController.shared.show() },
            .init(id: "windows", title: "Open Windows & Workspaces", symbol: "macwindow.on.rectangle", keywords: "switcher positioning layouts snap") { WindowToolsController.shared.show() },
            .init(id: "end-mode", title: "End Workspace Mode", symbol: "stop.circle", keywords: "restore defaults") { WorkspaceModeManager.shared.end() }
        ]
        actions += WorkspaceMode.allCases.map { mode in
            .init(id: "mode-\(mode.rawValue)", title: "Start \(mode.title) Mode", symbol: mode.symbol, keywords: "preset workspace") { WorkspaceModeManager.shared.activate(mode) }
        }
        actions += NotchSettingsDestination.all.filter { $0.id != "Account" }.map { destination in
            .init(id: "settings-\(destination.id)", title: "\(destination.title) Settings", symbol: destination.symbol, keywords: destination.keywords) { SettingsWindowController.shared.showWindow(section: destination.id) }
        }
        return actions
    }
    static func run(_ id: String) {
        guard WorkspaceAccess.privateToolsAllowed, let action = all.first(where: { $0.id == id }) else { return }
        action.perform()
    }
    /// Deeplinks only open non-sensitive surfaces. They cannot change settings,
    /// end privacy mode, copy snippets, start recording, run shells or open URLs.
    static func handle(_ url: URL) {
        guard WorkspaceAccess.privateToolsAllowed, url.scheme == "notchscape", url.host == "open",
              url.query == nil, url.fragment == nil, url.user == nil, url.password == nil else { return }
        switch url.path { case "/commands": CommandPaletteController.shared.show(); case "/tools": WorkspaceToolsWindowController.shared.show(); case "/settings": SettingsWindowController.shared.showWindow(); default: break }
    }
}

@MainActor
final class CommandPaletteController: NSWindowController {
    static let shared = CommandPaletteController()
    private init() {
        let panel = NSPanel(contentRect: .init(x: 0, y: 0, width: 620, height: 430), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "Commands"; panel.titlebarAppearsTransparent = true; panel.isReleasedWhenClosed = false
        panel.sharingType = .none; panel.isFloatingPanel = true
        panel.contentView = NSHostingView(rootView: CommandPaletteView().background(LiquidGlassSettingsBackground()))
        super.init(window: panel)
    }
    required init?(coder: NSCoder) { fatalError() }
    func show() { guard WorkspaceAccess.privateToolsAllowed else { return }; window?.center(); showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }
}

private struct CommandPaletteView: View {
    @State private var query = ""
    @State private var selected: String?
    @FocusState private var focused: Bool
    private var actions: [WorkspaceAction] {
        let words = query.split(whereSeparator: \.isWhitespace)
        return WorkspaceActions.all.filter { action in words.allSatisfy { (action.title+" "+action.keywords).localizedCaseInsensitiveContains($0) } }
    }
    var body: some View {
        VStack(spacing: 8) {
            TextField("Search actions or calculate…", text: $query).textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit { run() }.padding(.horizontal, 16).padding(.top, 16)
            if let result = LocalCalculator.result(query), !query.isEmpty {
                HStack { Label(result, systemImage: "equal").font(.title2.monospacedDigit()); Spacer(); Button("Copy Result") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result, forType: .string) } }.padding(.horizontal, 16)
            }
            List(actions, selection: $selected) { action in
                Button { CommandPaletteController.shared.close(); WorkspaceActions.run(action.id) } label: { Label(action.title, systemImage: action.symbol).frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(.plain).tag(action.id).padding(.vertical, 3)
            }.listStyle(.inset)
            Text("↑ ↓ to choose · Return to run · Escape to close").font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)
        }
        .onAppear { focused = true; selected = actions.first?.id }
        .onChange(of: query) { _, _ in selected = actions.first?.id }
        .onMoveCommand { direction in
            guard !actions.isEmpty else { return }; let index = actions.firstIndex { $0.id == selected } ?? 0
            if direction == .down { selected = actions[min(index+1, actions.count-1)].id }
            if direction == .up { selected = actions[max(index-1, 0)].id }
        }
        .onExitCommand { CommandPaletteController.shared.close() }
    }
    private func run() { guard let selected else { return }; CommandPaletteController.shared.close(); WorkspaceActions.run(selected) }
}

struct OpenNotchscapeCommandsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Notchscape Commands"
    static var description = IntentDescription("Open the foreground command palette. No action runs automatically.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { CommandPaletteController.shared.show(); return .result() }
}
struct OpenNotchscapeToolsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Notchscape Workspace Tools"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { WorkspaceToolsWindowController.shared.show(); return .result() }
}
struct NotchscapeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenNotchscapeCommandsIntent(), phrases: ["Open commands in \(.applicationName)"], shortTitle: "Commands", systemImageName: "command")
        AppShortcut(intent: OpenNotchscapeToolsIntent(), phrases: ["Open workspace tools in \(.applicationName)"], shortTitle: "Workspace Tools", systemImageName: "square.grid.2x2")
    }
}
