import AppKit
import Defaults
import SwiftUI

@MainActor
final class PinnedScratchpadController: NSWindowController, NSWindowDelegate {
    static let shared = PinnedScratchpadController()
    private init() {
        let panel = NSPanel(contentRect: .init(x: 0, y: 0, width: 360, height: 360), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Scratchpad"; panel.minSize = .init(width: 280, height: 240); panel.isReleasedWhenClosed = false
        panel.level = .floating; panel.sharingType = .none; panel.toolbarStyle = .unified
        panel.toolbar = NSToolbar(identifier: "NotchScratchpad")
        panel.contentView = NSHostingView(rootView: PinnedScratchpadView().background(LiquidGlassSettingsBackground()))
        super.init(window: panel)
        panel.delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }
    func show(note: UUID? = nil) {
        guard WorkspaceAccess.privateToolsAllowed else { return }
        guard Defaults[.quickNotesEnabled] else { SettingsWindowController.shared.showWindow(section: "Tools"); return }
        if let note { LocalToolsManager.shared.selectedNote = note }
        if window?.isVisible != true { window?.center() }; showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func pin(_ value: Bool) { window?.level = value ? .floating : .normal }
    override func close() { super.close(); Task { await LocalToolsManager.shared.flush() } }
    func windowWillClose(_ notification: Notification) { Task { await LocalToolsManager.shared.flush() } }
}
private struct PinnedScratchpadView: View {
    @ObservedObject private var tools = LocalToolsManager.shared
    @ObservedObject private var modes = WorkspaceModeManager.shared
    @Default(.quickNotesEnabled) private var enabled
    @State private var pinned = true
    private var selected: QuickNote? { tools.notes.first { $0.id == tools.selectedNote } ?? tools.notes.first }
    var body: some View {
        Group {
            if modes.active?.hidesPrivateContent == true || !enabled { Text("Notes are hidden.").foregroundStyle(.secondary) }
            else {
                VStack(spacing: 10) {
                    HStack {
                        Picker("Note", selection: Binding(get: { selected?.id }, set: { tools.selectedNote = $0 })) {
                            Text("Choose a note").tag(UUID?.none)
                            ForEach(tools.notes) { Text($0.title).tag(Optional($0.id)) }
                        }.labelsHidden()
                        Button { tools.addNote() } label: { Image(systemName: "square.and.pencil") }.help("New Note").disabled(!tools.loaded || tools.notes.count >= 100)
                        Toggle(isOn: $pinned) { Image(systemName: pinned ? "pin.fill" : "pin") }.toggleStyle(.button).help("Keep on top").accessibilityLabel("Keep scratchpad on top")
                    }
                    if let note = selected {
                        TextEditor(text: Binding(get: { tools.notes.first { $0.id == note.id }?.text ?? "" }, set: { tools.updateNote(note.id, text: $0) })).accessibilityLabel("Note text")
                    } else { ContentUnavailableView("No Notes", systemImage: "note.text", description: Text("Choose New Note to start.")) }
                    Text(tools.needsSave ? "Saving locally…" : "Encrypted on this Mac").font(.caption2).foregroundStyle(.secondary)
                }.padding(12)
            }
        }.controlSize(.small).task { await tools.load() }
            .onChange(of: pinned) { _, value in PinnedScratchpadController.shared.pin(value) }
            .onChange(of: enabled) { _, value in if !value { PinnedScratchpadController.shared.close() } }
            .onDisappear { Task { await tools.flush() } }
    }
}
