import Defaults
import SwiftUI

struct WorkspaceModesSettings: View {
    @ObservedObject private var modes = WorkspaceModeManager.shared
    @State private var choice: WorkspaceMode = .work
    @State private var duration: WorkspaceModeDuration = .untilQuit
    var body: some View {
        Form {
            if let session = modes.session {
                Section {
                    Label("\(session.mode.title) Mode is active", systemImage: session.mode.symbol).font(.headline)
                    if let expiry = session.expiresAt { LabeledContent("Ends", value: expiry.formatted(date: .omitted, time: .shortened)) }
                    else { Text("Ends when you turn it off or quit Notchscape.").foregroundStyle(.secondary) }
                    Button("End Mode and Restore My Settings") { modes.end() }
                } header: { Text("Active Mode") }
            }
            Section {
                Picker("Mode", selection: $choice) {
                    ForEach(WorkspaceMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                if choice.hidesPrivateContent {
                    LabeledContent("Duration", value: "Until ended or app quits")
                    Text("Presentation never ends automatically. End it yourself when sharing is finished.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Duration", selection: $duration) {
                        ForEach(WorkspaceModeDuration.allCases) { Text($0.title).tag($0) }
                    }
                }
                Toggle("Use \(choice.title) Mode", isOn: Binding(
                    get: { modes.active == choice },
                    set: { if $0 { modes.activate(choice, duration: duration) } else { modes.end() } }))
            } header: { Text("One Switch, One Setup") } footer: {
                Text("Only one Mode runs at a time. Starting another replaces it. Modes are temporary overlays: your saved settings—including changes you make while a Mode is active—return when it ends. Nothing is permanently rewritten.")
            }
            Section {
                ForEach(choice.changes, id: \.self) { change in Label(change, systemImage: "checkmark.circle").font(.callout) }
            } header: { Text("\(choice.title) Preview") }
            Section {
                Text("Modes never enable recording, camera, microphone, location, accounts or cloud sync. Existing feature-off switches and lock-screen privacy always win. Presentation hides this app’s private notch content; it does not redact other apps or secure your screen sharing.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Your Control Comes First") }
        }
        .onAppear { if let active = modes.active { choice = active } }
        .navigationTitle("Modes")
    }
}

struct WorkspaceModeMenu: View {
    @ObservedObject private var modes = WorkspaceModeManager.shared
    var body: some View {
        Menu {
            if let active = modes.active {
                Label("\(active.title) Mode is active", systemImage: active.symbol)
                Button("End Mode / Restore Settings") { modes.end() }
                Divider()
            }
            ForEach(WorkspaceMode.allCases) { mode in
                Button { modes.activate(mode) } label: { Label(mode.title, systemImage: mode.symbol) }
            }
            Divider()
            Button("Modes Settings…") { SettingsWindowController.shared.showWindow(section: "Modes") }
        } label: {
            Label(modes.active.map { "Mode: \($0.title)" } ?? "Modes", systemImage: modes.active?.symbol ?? "square.stack.3d.up")
        }
    }
}

struct PresentationModePlaceholder: View {
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "person.crop.rectangle").font(.title2).foregroundStyle(.secondary)
            Text("Presentation Mode").font(.headline)
            Text("Private notch content is hidden. Your other apps are not redacted.").font(.caption).foregroundStyle(.secondary)
            Button("End Mode and Restore") { WorkspaceModeManager.shared.end() }
                .buttonStyle(.bordered)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
