import AppKit
import SwiftUI
import Defaults

@MainActor
final class WorkspaceToolsVisibility: ObservableObject {
    static let shared = WorkspaceToolsVisibility()
    @Published var visible = false
}

@MainActor
final class WorkspaceToolsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = WorkspaceToolsWindowController()
    private init() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 760, height: 580), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Workspace Tools"; window.minSize = .init(width: 620, height: 440); window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified; window.titlebarSeparatorStyle = .none; window.toolbar = NSToolbar(identifier: "NotchWorkspaceTools")
        window.sharingType = .none
        window.contentView = NSHostingView(rootView: WorkspaceToolsView().background(LiquidGlassSettingsBackground()))
        super.init(window: window)
        window.delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }
    func show() { guard WorkspaceAccess.privateToolsAllowed else { return }; if window?.isVisible != true { window?.center() }; showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil); WorkspaceToolsVisibility.shared.visible = true }
    override func close() { WorkspaceToolsVisibility.shared.visible = false; super.close(); Task { await LocalToolsManager.shared.flush() } }
    func windowWillClose(_ notification: Notification) { WorkspaceToolsVisibility.shared.visible = false; Task { await LocalToolsManager.shared.flush() } }
    func windowDidChangeOcclusionState(_ notification: Notification) { WorkspaceToolsVisibility.shared.visible = window?.occlusionState.contains(.visible) == true }
}

private enum WorkspaceToolPage: String, CaseIterable, Identifiable {
    case calculator = "Calculator", snippets = "Snippets", quicklinks = "Quicklinks", timers = "Clocks", events = "Countdown", music = "Music Queue", features = "Feature Catalogue"
    var id: Self { self }
}
struct WorkspaceToolsView: View {
    @ObservedObject private var tools = LocalToolsManager.shared
    @ObservedObject private var modes = WorkspaceModeManager.shared
    @State private var page: WorkspaceToolPage = .calculator
    var body: some View {
        Group {
            if modes.active?.hidesPrivateContent == true { PresentationModePlaceholder() }
            else {
                VStack(spacing: 0) {
                    HStack {
                        Picker("Workspace tool", selection: $page) { ForEach(WorkspaceToolPage.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).frame(maxWidth: 240)
                        Spacer(); Button { CommandPaletteController.shared.show() } label: { Label("Commands", systemImage: "command") }
                    }.padding()
                    switch page { case .calculator: CalculatorWorkspaceView(); case .snippets: SnippetsWorkspaceView(); case .quicklinks: QuicklinksWorkspaceView(); case .timers: ClocksWorkspaceView(); case .events: PinnedEventWorkspaceView(); case .music: MusicQueueCapabilityView(); case .features: FeatureCatalogueView() }
                    if let error = tools.error { Text(error).font(.caption).foregroundStyle(.orange).padding(8) }
                }
            }
        }.controlSize(.small).toggleStyle(CompactSwitchToggleStyle()).task { await tools.load() }
            .onDisappear { Task { await tools.flush() } }
    }
}

private struct CalculatorWorkspaceView: View {
    @State private var expression = ""
    var body: some View {
        Form {
            Section("Calculate") {
                TextField("2 * (3 + 4), 10 km to mi, today +7 days", text: $expression).textFieldStyle(.roundedBorder)
                    .onChange(of: expression) { _, value in if value.count > 1024 { expression = String(value.prefix(1024)) } }
                if let result = LocalCalculator.result(expression), !expression.isEmpty {
                    Text(result).font(.largeTitle.monospacedDigit()).textSelection(.enabled)
                    Button("Copy Result") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result, forType: .string) }
                } else { Text(expression.isEmpty ? "Type an expression to start." : "Check the expression or units.").foregroundStyle(.secondary) }
            }
            Section("On Your Mac") { Text("Arithmetic, length, mass, temperature, time, decimal/binary data units and local-calendar date offsets. No exchange-rate guesses, code evaluation, history, or network requests.").foregroundStyle(.secondary) }
        }.formStyle(.grouped)
    }
}

private struct SnippetsWorkspaceView: View {
    @ObservedObject private var tools = LocalToolsManager.shared
    @State private var search = ""
    @State private var name = ""
    @State private var text = ""
    @State private var editing: UUID?
    @State private var delete: TextSnippet?
    var body: some View {
        HSplitView {
            VStack {
                TextField("Search snippets", text: $search).textFieldStyle(.roundedBorder)
                List(tools.workspace.snippets.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { snippet in
                    HStack {
                        Button(snippet.name) { editing = snippet.id; name = snippet.name; text = snippet.text }.buttonStyle(.plain)
                        Spacer(); Button { tools.copySnippet(snippet) } label: { Image(systemName: "doc.on.doc") }.help("Copy snippet")
                        Button { delete = snippet } label: { Image(systemName: "trash") }.help("Delete snippet")
                    }
                }
                Button("New Snippet") { editing = nil; name = ""; text = "" }
            }.frame(minWidth: 180, idealWidth: 220).padding(12)
            VStack(alignment: .leading, spacing: 12) {
                TextField("Snippet name", text: $name).textFieldStyle(.roundedBorder)
                TextEditor(text: $text).font(.body.monospaced()).border(.quaternary)
                HStack { Text("\(text.count)/20,000 characters").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Save Snippet") { tools.saveSnippet(id: editing, name: name, text: text); editing = nil; name = ""; text = "" }.disabled(!tools.loaded || name.isEmpty || name.count > 80 || text.isEmpty || text.count > 20_000 || (editing == nil && tools.workspace.snippets.count >= 100)) }
                Text("Encrypted on this Mac. Explicit Copy only; no keystroke watching or automatic text expansion.").font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }.confirmationDialog("Delete snippet?", isPresented: Binding(get: { delete != nil }, set: { if !$0 { delete = nil } })) {
            Button("Delete", role: .destructive) { if let delete { tools.removeSnippet(delete.id) }; delete = nil }
        } message: { Text("This removes the saved snippet and cannot be undone.") }
    }
}

private struct QuicklinksWorkspaceView: View {
    @ObservedObject private var tools = LocalToolsManager.shared
    @State private var name = ""
    @State private var template = ""
    @State private var query = ""
    @State private var delete: NamedQuicklink?
    var body: some View {
        Form {
            Section("New Quicklink") {
                TextField("Name", text: $name)
                TextField("https://example.com/search?q={query}", text: $template)
                HStack {
                    Button("Save Web Quicklink") { tools.saveQuicklink(name: name, template: template); name = ""; template = "" }.disabled(!tools.loaded || name.isEmpty || name.count > 80 || QuicklinkPolicy.url(template, query: "test") == nil || tools.workspace.links.count >= 100)
                    Button("Choose Folder…") { tools.chooseQuicklinkFolder() }.disabled(!tools.loaded || tools.workspace.links.count >= 100)
                }
            }
            Section("My Quicklinks") {
                TextField("Search text for {query} links", text: $query)
                ForEach(tools.workspace.links) { link in
                    HStack { Label(link.name, systemImage: link.folderBookmark == nil ? "link" : "folder"); Spacer(); Button("Open") { tools.openQuicklink(link, query: query) }; Button { delete = link } label: { Image(systemName: "trash") }.help("Remove Quicklink") }
                }
                if tools.workspace.links.isEmpty { Text("No Quicklinks yet.").foregroundStyle(.secondary) }
            }
            Text("Web links open only when you choose Open. Folder access is limited to your selected bookmark. URLs with embedded usernames/passwords and executable schemes are rejected.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).confirmationDialog("Remove Quicklink?", isPresented: Binding(get: { delete != nil }, set: { if !$0 { delete = nil } })) { Button("Remove", role: .destructive) { if let delete { tools.removeQuicklink(delete.id) }; delete = nil } }
    }
}

private struct ClocksWorkspaceView: View {
    @ObservedObject private var clock = WorkspaceClockManager.shared
    @ObservedObject private var visibility = WorkspaceToolsVisibility.shared
    @ObservedObject private var performance = AppPerformanceManager.shared
    @State private var cycle = FocusCycle()
    @State private var awakeMinutes = 30
    var body: some View {
        Form {
            Section("Stopwatch") {
                if visibility.visible && clock.stopwatchRunning {
                    TimelineView(.periodic(from: .now, by: performance.lowImpact ? 1 : 0.1)) { _ in Text(duration(clock.elapsed)).font(.largeTitle.monospacedDigit()) }
                } else { Text(duration(clock.elapsed)).font(.largeTitle.monospacedDigit()) }
                HStack { Button(clock.stopwatchRunning ? "Pause" : "Start") { clock.toggleStopwatch() }; Button("Lap") { clock.lap() }.disabled(!clock.stopwatchRunning || clock.laps.count >= 500); Button("Reset") { clock.resetStopwatch() } }
                ForEach(clock.laps.suffix(8).reversed()) { lap in HStack { Text("Lap \((clock.laps.firstIndex { $0.id == lap.id } ?? 0)+1)"); Spacer(); Text(duration(lap.split)).monospacedDigit(); Text(duration(lap.total)).foregroundStyle(.secondary).monospacedDigit() } }
            }
            Section("Focus Cycles") {
                Stepper("Focus: \(cycle.workMinutes) minutes", value: $cycle.workMinutes, in: 1...180)
                Stepper("Break: \(cycle.breakMinutes) minutes", value: $cycle.breakMinutes, in: 1...60)
                Stepper("Rounds: \(cycle.rounds)", value: $cycle.rounds, in: 1...12)
                if clock.focusPhase != .finished && visibility.visible {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in Text("\(clock.focusPhase.rawValue) · Round \(clock.round)/\(clock.cycle.rounds) · \(duration(clock.pausedRemaining ?? max(0, clock.focusEnd?.timeIntervalSinceNow ?? 0)))").monospacedDigit() }
                }
                HStack { Button("Start Cycles") { clock.startFocus(cycle) }.disabled(clock.focusPhase != .finished); Button(clock.pausedRemaining == nil ? "Pause" : "Resume") { clock.toggleFocusPause() }.disabled(clock.focusPhase == .finished); Button("End") { clock.cancelFocus() }.disabled(clock.focusPhase == .finished) }
                Text("Starts only when you choose Start Cycles. Does not change macOS Focus or play sounds.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Keep Awake") {
                Picker("Duration", selection: $awakeMinutes) { ForEach([15,30,60,120], id: \.self) { Text("\($0) minutes").tag($0) } }
                if let end = clock.keepAwakeEnd { LabeledContent("Ends", value: end.formatted(date: .omitted, time: .shortened)); Button("Stop Keep Awake") { clock.stopKeepAwake() } }
                else { Button("Start Keep Awake") { clock.startKeepAwake(minutes: awakeMinutes) } }
                Text("Prevents idle system sleep only; your display may sleep and you can still lock or sleep manually. Stops on expiry, app quit, Travel or Presentation Mode.").font(.caption).foregroundStyle(.secondary)
                if let error = clock.error { Text(error).foregroundStyle(.orange) }
            }
        }.formStyle(.grouped)
    }
    private func duration(_ seconds: Double) -> String { let tenths = Int(max(0, seconds)*10); return String(format: "%02d:%02d:%02d.%01d", tenths/36000, (tenths/600)%60, (tenths/10)%60, tenths%10) }
}

private struct PinnedEventWorkspaceView: View {
    @ObservedObject private var visibility = WorkspaceToolsVisibility.shared
    @ObservedObject private var calendar = CalendarManager.shared
    @ObservedObject private var pin = PinnedEventManager.shared
    @Default(.showCalendar) private var enabled
    var body: some View {
        Form {
            Section("Pinned Countdown") {
                if let event = pin.visibleEvent {
                    Text(event.title).font(.headline)
                    if visibility.visible {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            let end = event.start > Date() ? event.start : event.end
                            Text(event.start > Date() ? "Starts in " : "Ends in ") + Text(timerInterval: Date()...max(Date(), end), countsDown: true)
                        }
                    }
                    Button("Unpin Event") { pin.clear() }
                } else { Text("Choose an upcoming event from your currently loaded calendar day.").foregroundStyle(.secondary) }
            }
            Section("This Calendar Day") {
                if !enabled { Button("Calendar Settings…") { SettingsWindowController.shared.showWindow(section: "Calendar") } }
                ForEach(calendar.events.filter { $0.type.isEvent && $0.end > Date() }) { event in
                    HStack { VStack(alignment: .leading) { Text(event.title); Text(event.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Pin") { pin.pin(event) } }.disabled(!enabled)
                }
            }
            Text("Uses existing Calendar access and selected calendars only. Selection stays in this session and no calendar data is uploaded or saved as a separate copy.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }
}
