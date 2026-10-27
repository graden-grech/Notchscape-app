import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI

@MainActor
final class NotchToolsWindowController: NSWindowController {
    static let shared = NotchToolsWindowController()
    private init() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 700, height: 470),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Tools"; window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar(identifier: "NotchToolsToolbar")
        window.contentView = NSHostingView(rootView: ProductivityHubView(expanded: true)
            .padding(16).background(LiquidGlassSettingsBackground()))
        window.minSize = .init(width: 540, height: 360)
        window.sharingType = .none
        window.setFrameAutosaveName("NotchPrivateTools")
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show(_ tool: NotchTool = .clipboard) {
        guard WorkspaceModeManager.shared.active?.hidesPrivateContent != true,
              let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session["CGSSessionScreenIsLocked"] as? Bool != true else { return }
        LocalToolsManager.shared.selectedTool = tool
        if window?.isVisible != true { window?.center() }
        showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
}

struct ProductivityHubView: View {
    var expanded = false
    @ObservedObject private var tools = LocalToolsManager.shared
    @ObservedObject private var modes = WorkspaceModeManager.shared
    @ObservedObject private var appleNotes = AppleNotesSyncManager.shared
    @Default(.clipboardHistoryEnabled) private var clipboardEnabled
    @Default(.quickNotesEnabled) private var notesEnabled
    @Default(.deviceControlsEnabled) private var devicesEnabled
    @Default(.textCaptureEnabled) private var captureEnabled
    @Default(.appTheme) private var theme
    @Default(.useCustomAccentColor) private var customAccent
    @Default(.customAccentColorData) private var accentData
    @State private var search = ""
    @State private var confirmClear = false
    @State private var confirmDeleteNote = false
    @State private var copied: UUID?

    private var enabled: Bool {
        switch tools.selectedTool { case .clipboard: clipboardEnabled; case .notes: notesEnabled; case .devices: devicesEnabled; case .capture: captureEnabled; case .utilities: true }
    }
    var body: some View {
        if modes.active?.hidesPrivateContent == true { PresentationModePlaceholder() }
        else { hubContent }
    }
    private var hubContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Tool", selection: $tools.selectedTool) {
                    ForEach(NotchTool.allCases) { tool in Label(tool.title, systemImage: tool.symbol).tag(tool) }
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 440)
                Spacer(minLength: 0)
                if !expanded {
                    Button { NotchToolsWindowController.shared.show(tools.selectedTool) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                        .help("Open Tools window").accessibilityLabel("Open Tools window")
                }
            }
            if !enabled { disabledTool }
            else {
                switch tools.selectedTool {
                case .clipboard: clipboardContent
                case .notes: notesContent
                case .devices: DeviceControlsView(expanded: expanded)
                case .capture: captureContent
                case .utilities: UtilityToolsView(expanded: expanded)
                }
            }
            if let error = tools.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .controlSize(.small)
        .tint(Color(nsColor: NSColor.resolvedAccent(theme: theme, customEnabled: customAccent, customData: accentData)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { if clipboardEnabled || notesEnabled { await tools.load() } }
        .onChange(of: notesEnabled) { _, enabled in if enabled { Task { await tools.load() } } }
        .onChange(of: clipboardEnabled) { _, enabled in if enabled { Task { await tools.load() } } }
        .onDisappear { Task { await tools.flush() } }
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Unpinned Items", role: .destructive) { tools.clearClipboard() }
        } message: { Text("Pinned items are kept. This can’t be undone.") }
        .confirmationDialog("Delete this note?", isPresented: $confirmDeleteNote, titleVisibility: .visible) {
            Button("Delete Note", role: .destructive) { if let id = tools.selectedNote { tools.removeNote(id) } }
        } message: { Text("This only removes this local note and can’t be undone. Its Apple Notes copy, if any, is kept and won’t be imported again.") }
    }
    private var disabledTool: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(tools.selectedTool.title, systemImage: tools.selectedTool.symbol).font(.headline)
            Text(disabledDescription).font(.caption).foregroundStyle(.secondary).lineLimit(expanded ? nil : 3)
            Button("Enable \(tools.selectedTool.title)") {
                switch tools.selectedTool {
                case .clipboard: clipboardEnabled = true
                case .notes: notesEnabled = true
                case .devices: devicesEnabled = true
                case .capture: captureEnabled = true
                case .utilities: break
                }
            }.buttonStyle(.bordered)
            Spacer(minLength: 0)
        }.padding(10)
    }
    private var disabledDescription: String {
        switch tools.selectedTool {
        case .clipboard: "Save future copies on this Mac. History is encrypted, excludes protected clipboard types and known password managers, and pauses when locked. Other sensitive copies may still be recorded; exclusions are in Settings → Tools."
        case .notes: "A private scratchpad, encrypted on this Mac. Optionally save or sync text with a dedicated Apple Notes folder in Settings → Tools."
        case .devices: "See paired Bluetooth devices and available battery levels, connect a device, or choose the Mac’s audio output. No nearby-device scanning."
        case .capture: "Select a screenshot or capture a region to recognize text on this Mac. Screen Recording is requested only when capturing a region."
        case .utilities: "Clean a link or sample a color using on-demand, local tools."
        }
    }
    private var clipboardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if expanded { TextField("Search clipboard", text: $search).textFieldStyle(.roundedBorder) }
                else { Text("\(tools.clipboard.count) items").font(.caption).foregroundStyle(.secondary) }
                Button(tools.paused ? "Resume" : "Pause") { tools.pause(!tools.paused) }
                Button("Clear…") { confirmClear = true }.disabled(tools.clipboard.allSatisfy(\.pinned))
            }
            if tools.clipboard.isEmpty {
                Text("Your next copy will appear here. Protected copies are skipped.").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(tools.clipboard.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.source.localizedCaseInsensitiveContains(search) }) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.image == nil ? "doc.text" : "photo").foregroundStyle(.secondary)
                            Button {
                                tools.copy(entry); copied = entry.id
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    if expanded { Text(entry.source).font(.caption2).foregroundStyle(.secondary) }
                                }
                            }.buttonStyle(.plain).help("Copy item")
                            if copied == entry.id { Image(systemName: "checkmark").foregroundStyle(.green).accessibilityLabel("Copied") }
                            Button { tools.pin(entry) } label: { Image(systemName: entry.pinned ? "pin.fill" : "pin") }
                                .buttonStyle(.borderless).help(entry.pinned ? "Unpin item" : "Pin item").accessibilityLabel(entry.pinned ? "Unpin item" : "Pin item")
                        }.padding(7).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
    private var notesContent: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Button { tools.addNote(); if !expanded { NotchToolsWindowController.shared.show(.notes) } } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }.disabled(!tools.loaded || tools.notes.count >= 100)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(tools.notes) { note in
                            Button { tools.selectedNote = note.id } label: {
                                Text(note.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(6)
                                    .background(tools.selectedNote == note.id ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.frame(width: expanded ? 170 : 150)
            if let note = tools.notes.first(where: { $0.id == tools.selectedNote }) ?? tools.notes.first {
                VStack(alignment: .leading, spacing: 4) {
                    if expanded {
                        TextEditor(text: Binding(get: { tools.notes.first(where: { $0.id == note.id })?.text ?? "" },
                                                 set: { tools.updateNote(note.id, text: $0) }))
                            .font(.body).scrollContentBackground(.hidden).padding(5)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel("Note text")
                        HStack {
                            Label(note.appleNote == nil ? "Saved on this Mac" : "Linked to Apple Notes",
                                  systemImage: note.appleNote == nil ? "lock.shield" : "note.text")
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Button(note.appleNote == nil ? "Save to Apple Notes" : "Sync Note") {
                                Task { await appleNotes.save(note.id) }
                            }.disabled(appleNotes.busy || note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button("Delete…") { tools.selectedNote = note.id; confirmDeleteNote = true }
                        }
                        if let message = appleNotes.message {
                            Text(message).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(note.text.isEmpty ? "Start writing a note…" : note.text).font(.caption).lineLimit(3).frame(maxWidth: .infinity, alignment: .topLeading)
                        HStack {
                            Button("Edit Note…") { tools.selectedNote = note.id; NotchToolsWindowController.shared.show(.notes) }
                            Button("Pin…") { PinnedScratchpadController.shared.show(note: note.id) }
                        }
                    }
                }
            } else {
                Text("A thought, a list, a reminder to yourself. Start a note.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.onAppear { if tools.selectedNote == nil { tools.selectedNote = tools.notes.first?.id } }
    }
    private var captureContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Button { tools.captureScreenText() } label: { Label("Capture Region…", systemImage: "viewfinder") }
                Button("Choose Image…") { tools.recognizeImageFile() }
                if tools.recognizing { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
                Button("Copy Text") { tools.copyCapture() }.disabled(tools.captureText.isEmpty)
            }.disabled(tools.recognizing)
            ForEach(tools.capturedCodes, id: \.self) { code in
                HStack { Label(code, systemImage: "qrcode.viewfinder").lineLimit(2).textSelection(.enabled); Spacer(); Button("Copy Code") { tools.copyCode(code) } }
                    .font(.caption).padding(6).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            if tools.captureText.isEmpty {
                Text("Recognition runs on device. Results are not copied or saved until you choose an action.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if expanded {
                TextEditor(text: $tools.captureText).font(.body).accessibilityLabel("Recognized text")
            } else {
                ScrollView { Text(tools.captureText).font(.caption).frame(maxWidth: .infinity, alignment: .leading) }
            }
            Spacer(minLength: 0)
        }
    }
}

struct DeviceControlsView: View {
    var expanded = false
    @ObservedObject private var manager = DeviceControlsManager.shared
    @Default(.deviceControlsEnabled) private var enabled
    @State private var viewerID = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Picker("Audio output", selection: Binding(get: { manager.selectedOutput }, set: { manager.selectOutput($0) })) {
                    ForEach(manager.outputs) { Text($0.name).tag($0.id) }
                }.disabled(manager.outputs.isEmpty)
                Button { manager.refresh(includeBatteryReport: true) } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh devices and reported batteries").accessibilityLabel("Refresh devices and batteries").disabled(manager.refreshing)
            }
            if expanded { AudioRoutingControlsView() }
            else { Button("Input and Preferred Outputs…") { NotchToolsWindowController.shared.show(.devices) } }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    if manager.devices.isEmpty { Text("No paired devices found. Pair devices in Bluetooth settings.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(manager.devices) { device in
                        HStack(spacing: 8) {
                            Image(systemName: device.symbol).font(.title3).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name).lineLimit(1)
                                Text(batteryText(device)).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if device.connected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Connected") }
                            else { Button(manager.connecting == device.id ? "Connecting…" : "Connect") { manager.connect(device) }.disabled(manager.connecting != nil) }
                        }
                    }
                }
            }
            if let message = manager.message { Text(message).font(.caption2).foregroundStyle(.secondary) }
            Text("Battery levels appear only when macOS publishes them; missing levels are not estimates.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear { manager.appear(viewerID) }
        .onDisappear { manager.disappear(viewerID) }
        .onChange(of: enabled) { _, enabled in if enabled { manager.appear(viewerID) } else { manager.stop() } }
    }
    private func batteryText(_ d: NotchBluetoothDevice) -> String {
        let levels = [("L", d.left), ("R", d.right), ("Case", d.caseBattery)].compactMap { label, level in level.map { "\(label) \($0)%" } }
        if !levels.isEmpty { return levels.joined(separator: " · ") }
        if let battery = d.battery { return "\(battery)%" }
        return d.connected ? "Connected · Battery unavailable" : "Not connected"
    }
}

struct ProductivitySettings: View {
    @Default(.showToolsTab) private var showTools
    @Default(.clipboardHistoryEnabled) private var clipboardEnabled
    @Default(.clipboardRetentionDays) private var retention
    @Default(.clipboardExcludedApps) private var exclusions
    @Default(.quickNotesEnabled) private var notesEnabled
    @Default(.deviceControlsEnabled) private var devicesEnabled
    @Default(.deviceConnectionAlerts) private var deviceAlerts
    @Default(.deviceLowBatteryAlerts) private var batteryAlerts
    @Default(.deviceLowBatteryThreshold) private var batteryThreshold
    @Default(.textCaptureEnabled) private var captureEnabled
    var body: some View {
        Form {
            Section {
                Toggle("Show Tools tab in the notch", isOn: $showTools)
                Button("Open Tools…") { NotchToolsWindowController.shared.show() }
            } header: { Text("Tools") } footer: { Text("Local by default, with no Notchscape account required. Apple Notes integration is optional and uses your existing Notes account.") }
            Section {
                Toggle("Save clipboard history", isOn: $clipboardEnabled)
                Group {
                    Picker("Keep unpinned items", selection: $retention) {
                        Text("1 day").tag(1); Text("7 days").tag(7); Text("30 days").tag(30)
                    }
                    TextField("Additional excluded app bundle IDs", text: $exclusions, prompt: Text("com.example.app"))
                    KeyboardShortcuts.Recorder("Open clipboard", name: .clipboardHistoryPanel)
                }.disabled(!clipboardEnabled).opacity(clipboardEnabled ? 1 : 0.4)
            } header: { Text("Clipboard") } footer: {
                Text("Off by default. Encrypted history holds up to 150 items / 12 MB, including pins. Protected clipboard types and known password managers are excluded; other sensitive copies may still be saved. Recording pauses while locked. Pins ignore age limits, not storage limits. Disabling recording does not delete saved history.")
            }
            Section {
                Toggle("Quick Notes", isOn: $notesEnabled)
                Button("Open Notes…") { NotchToolsWindowController.shared.show(.notes) }.disabled(!notesEnabled)
            } header: { Text("Notes") } footer: { Text("Local copies are encrypted with a device-only Keychain key. Up to 100 notes, 50,000 characters each. Save a single note to Apple Notes from its editor, or enable two-way sync below.") }
            AppleNotesSettingsSection()
            Section {
                Button("Open Clean Link & Color Picker…") { NotchToolsWindowController.shared.show(.utilities) }
            } header: { Text("Utilities") } footer: { Text("Remove known tracking tags from a link, or sample a screen color with Apple’s native color picker. No background clipboard rewriting or screen monitoring.") }
            Section {
                Toggle("Bluetooth devices and audio output", isOn: $devicesEnabled)
                Toggle("Native connection notifications", isOn: $deviceAlerts)
                    .disabled(!devicesEnabled).opacity(devicesEnabled ? 1 : 0.4)
                    .onChange(of: deviceAlerts) { _, enabled in
                        if enabled { DeviceControlsManager.shared.requestConnectionNotifications() }
                    }
                Button("Open Devices…") { NotchToolsWindowController.shared.show(.devices) }.disabled(!devicesEnabled)
                Toggle("Accessory low-battery alerts", isOn: $batteryAlerts).disabled(!devicesEnabled)
                    .onChange(of: batteryAlerts) { _, value in if value { DeviceControlsManager.shared.requestConnectionNotifications() } }
                Picker("Alert below", selection: $batteryThreshold) { Text("10%").tag(10); Text("20%").tag(20); Text("30%").tag(30) }.disabled(!devicesEnabled || !batteryAlerts)
            } header: { Text("Devices") } footer: { Text("Uses paired devices, not nearby discovery. Refreshes while Devices is visible, or every two minutes if low-battery alerts are explicitly enabled. Stops while locked/presenting. Earbud, case and hardware-mute availability depends on macOS and the device.") }
            Section {
                Toggle("On-device text recognition", isOn: $captureEnabled)
                Button("Open Text Capture…") { NotchToolsWindowController.shared.show(.capture) }.disabled(!captureEnabled)
                KeyboardShortcuts.Recorder("Capture screen text", name: .captureNotchText)
                    .disabled(!captureEnabled).opacity(captureEnabled ? 1 : 0.4)
            } header: { Text("Text Capture") } footer: { Text("Apple Vision recognizes text without an AI account. Image selection needs no screen permission. Capturing a region uses macOS’s region picker and requires Screen Recording access. Results are cleared when locked.") }
        }.navigationTitle("Tools")
    }
}

struct AppleNotesSettingsSection: View {
    @ObservedObject private var sync = AppleNotesSyncManager.shared
    @ObservedObject private var tools = LocalToolsManager.shared
    @Default(.quickNotesEnabled) private var notesEnabled
    @Default(.appleNotesSyncEnabled) private var enabled
    @State private var confirmDisconnect = false
    var body: some View {
        Section {
            if let scope = tools.appleNotesState.scope {
                LabeledContent("Account", value: scope.accountName)
            } else {
                Button("Connect Apple Notes…") { Task { await sync.connect() } }
                    .disabled(!notesEnabled || sync.busy)
            }
            Toggle("Automatically sync with Apple Notes", isOn: $enabled)
                .disabled(!notesEnabled || tools.appleNotesState.scope == nil)
                .opacity(notesEnabled && tools.appleNotesState.scope != nil ? 1 : 0.4)
            HStack {
                Button("Sync Now") { Task { await sync.sync() } }
                    .disabled(!notesEnabled || sync.busy || tools.appleNotesState.scope == nil)
                if sync.busy { ProgressView().controlSize(.small).accessibilityLabel("Syncing Apple Notes") }
                if tools.appleNotesState.scope != nil {
                    Spacer()
                    Button("Disconnect…") { confirmDisconnect = true }.disabled(sync.busy)
                }
            }
            if let date = sync.lastSync { LabeledContent("Last synced") { Text(date, style: .time).foregroundStyle(.secondary) } }
            if let message = sync.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        } header: { Text("Apple Notes") } footer: {
            Text("Automatic sync exchanges all Quick Notes with text notes in your connected app folder in Apple Notes. New connections use a Notchscape folder in your default Notes account; reconnecting adopts the app’s previous folder without deleting its notes. An iCloud account syncs through Apple Notes. It runs once a minute while Notes is open and shortly after local edits, and pauses while locked. Deletions never propagate. Conflicting edits are kept as separate copies for review. Text only: rich formatting, attachments, and locked/shared notes are skipped. macOS asks for Automation permission when you first connect.")
        }
        .confirmationDialog("Disconnect Apple Notes?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect") { enabled = false; tools.disconnectAppleNotes() }
        } message: { Text("All local notes and Apple Notes copies are kept. Automatic sync stops. Reconnecting will use the default Notes account at that time.") }
    }
}

struct AgentInsightsView: View {
    @ObservedObject private var agents = AgentStatusManager.shared
    @ObservedObject private var insights = AgentInsightsManager.shared
    @Default(.agentUsageEnabled) private var usageEnabled
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if usageEnabled {
                    ForEach(insights.readings) { reading in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(reading.provider).font(.caption.weight(.semibold))
                                Spacer()
                                Text(reading.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                            }
                            if let remaining = reading.remainingPercent {
                                ProgressView(value: remaining, total: 100)
                                Text("Last reported: \(remaining, specifier: "%.0f")% remaining\(reading.resetsAt.map { " · Resets " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "")")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            if let tokens = reading.tokens { Text("\(tokens.formatted()) recorded tokens").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                    if insights.readings.isEmpty { Text("No usage reading yet. Available local Codex events or hook-provided usage will appear here; missing numbers are not estimated.").font(.caption2).foregroundStyle(.secondary) }
                }
                ForEach(agents.activities) { activity in
                    HStack(spacing: 8) {
                        AgentProviderMark(provider: activity.provider, state: activity.state, size: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.title).font(.caption.weight(.semibold)).lineLimit(1)
                            Text("\(activity.provider) · \(activity.state.label) · \(activity.detail)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                Text("Active for \(max(0, Int(context.date.timeIntervalSince(activity.startedAt) / 60))) min")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Button(activity.provider.localizedCaseInsensitiveContains("claude") ? "Open Terminal" : "Open Codex") { insights.openAgent(activity.provider) }
                            .controlSize(.mini)
                    }
                }
                if agents.activities.isEmpty { Label("Ready for agent activity", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .task(id: usageEnabled) {
            guard usageEnabled else { return }
            await insights.refreshLocalUsage()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                await insights.refreshLocalUsage()
            }
        }
    }
}
