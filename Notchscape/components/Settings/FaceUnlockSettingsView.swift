import AppKit
import SwiftUI
import Defaults

@MainActor
final class FaceUnlockWindowController: NSWindowController, NSWindowDelegate {
    static let shared = FaceUnlockWindowController()
    private init() { super.init(window: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        guard FaceUnlockManager.featureEnabled else { return }
        if let window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let panel = NSWindow(contentRect: .init(x: 0, y: 0, width: 640, height: 700),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Notchscape Face Unlock"
        panel.identifier = NSUserInterfaceItemIdentifier("NotchscapeFaceUnlockWindow")
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.delegate = self
        let host = NSHostingView(rootView: FaceUnlockSettingsView().frame(width: 640, height: 700))
        host.sizingOptions = []
        panel.contentView = host
        panel.setContentSize(.init(width: 640, height: 700))
        window = panel
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        FaceUnlockManager.shared.closeSettings()
    }
}

struct FaceUnlockSettingsView: View {
    var embedded = false
    @ObservedObject private var manager = FaceUnlockManager.shared
    @Default(.enableHaptics) private var appHaptics
    @State private var newIdentityLabel = ""
    @State private var macPassword = ""
    @State private var acceptsConvenienceTradeoff = false
    @State private var identityToDelete: FaceIdentitySummary?
    @State private var confirmDeleteVault = false
    @State private var identityToRename: FaceIdentitySummary?
    @State private var renamedLabel = ""

    var body: some View {
        if FaceUnlockManager.featureEnabled {
            availableContent
        } else {
            ContentUnavailableView("Face Unlock is unavailable", systemImage: "lock.shield",
                description: Text("This release does not include the protected Face Unlock companion. Your saved local settings are preserved."))
        }
    }

    private var availableContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.square").font(.system(size: 30, weight: .light))
                    .foregroundStyle(Color.effectiveAccent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Face Unlock").font(.title2.weight(.semibold))
                    Text("Local webcam recognition · Preview").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if manager.isBusy { ProgressView().controlSize(.small) }
            }
            .padding(24)

            Form {
                if !manager.automaticUnlockEnabled {
                    Section("Setup") {
                        DisclosureGroup("Setup steps") {
                            FaceSetupChecklist(authorized: manager.isVaultAuthorized,
                                hasFace: !manager.identities.isEmpty,
                                tested: manager.hasRecentRecognitionTest,
                                hasPassword: manager.hasSavedCredential)
                        }
                    }
                }
                Section {
                    Label(manager.statusMessage, systemImage: manager.statusSymbol)
                        .accessibilityIdentifier("FaceUnlockStatus")
                    if let error = manager.errorMessage {
                        Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
                    }
                    if manager.automaticUnlockEnabled && !manager.isVaultAuthorized {
                        Button("Turn Off Face Unlock") { Task { await manager.setAutomaticUnlockEnabled(false) } }
                            .buttonStyle(.bordered)
                        Button("Authenticate to Resume…") { manager.resumeAutomaticUnlock() }
                            .disabled(manager.isBusy)
                    }
                }

                if !manager.isVaultAuthorized {
                    Section {
                        Text("Your faces and saved Mac password are encrypted on this Mac. Unlock these settings with Touch ID or your device password when you want to make changes.")
                        Button(manager.hasVault ? "Unlock Face Unlock Settings…" : "Set Up Face Unlock…") {
                            Task { await manager.openVault() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manager.isBusy)
                        DisclosureGroup("Troubleshoot Setup") {
                            Button("Check Setup") { Task { await manager.checkStorageAvailability() } }
                                .disabled(manager.isBusy)
                            if manager.canRecoverUnfinishedSetup {
                                Button("Recover Setup…") { Task { await manager.recoverUnfinishedSetup() } }
                                    .disabled(manager.isBusy)
                            }
                        }
                    } header: { Text("Get Started") }
                } else {
                    Section {
                        if manager.identities.isEmpty {
                            Text("Add a face to start. You can add separate appearances for glasses or different lighting.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(manager.identities) { identity in
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.title2).foregroundStyle(Color.effectiveAccent).accessibilityHidden(true)
                                Toggle(identity.label, isOn: Binding(
                                    get: { identity.isEnabled },
                                    set: { value in Task { await manager.setIdentityEnabled(value, id: identity.id) } }))
                                    .toggleStyle(.switch).controlSize(.small)
                                Button("Delete", systemImage: "trash", role: .destructive) { identityToDelete = identity }
                                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                                    .accessibilityLabel("Delete \(identity.label)")
                            }
                            .disabled(manager.isBusy || manager.isCapturing)
                            .contextMenu {
                                Button("Rename…") { renamedLabel = identity.label; identityToRename = identity }
                            }
                        }
                        HStack {
                            TextField("Appearance name (optional)", text: $newIdentityLabel)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: newIdentityLabel) { _, value in
                                    if value.count > 64 { newIdentityLabel = String(value.prefix(64)) }
                                }
                            Button("Add Face…") {
                                let entered = newIdentityLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                                let label = entered.isEmpty ? "Appearance \(manager.identities.count + 1)" : entered
                                Task {
                                    if await manager.beginEnrollment(label: label) { newIdentityLabel = "" }
                                }
                            }
                            .disabled((!newIdentityLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                FaceIdentityTemplate.validatedLabel(newIdentityLabel) == nil) || manager.isBusy || manager.isCapturing)
                        }
                        .disabled(manager.identities.count >= FaceIdentityManifest.maximumIdentities)
                    } header: { Text("People & Appearances · \(manager.identities.count)") } footer: {
                        Text("Save up to eight faces or appearances, including glasses. Every enabled face can unlock this same Mac user account.")
                    }

                    if manager.isCapturing {
                        Section("Camera Session") {
                            Label(manager.captureGuidance, systemImage: manager.captureSymbol)
                                .font(.headline)
                            ProgressView(value: manager.captureProgress)
                            Text("Keep one face in view, then follow the head-turn prompt. No camera image is saved.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Cancel Camera Session", role: .cancel) { manager.cancelCapture() }
                        }
                    } else if !manager.identities.isEmpty {
                        Section {
                            Button("Test Recognition…", systemImage: "person.crop.rectangle") {
                                Task { await manager.beginRecognitionTest() }
                            }
                            .disabled(manager.isBusy)
                            Text("Test your enrolled face and head-turn check before authorizing an unlock session. This test keeps your Mac unlocked.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        if manager.hasSavedCredential {
                            Label("Mac password saved locally", systemImage: "key.fill")
                        }
                        SecureField(manager.hasSavedCredential ? "New Mac password" : "Your Mac password", text: $macPassword)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button(manager.hasSavedCredential ? "Update Saved Password" : "Save Mac Password") {
                                let value = macPassword
                                macPassword = ""
                                Task { await manager.saveMacPassword(value) }
                            }
                            .disabled(macPassword.isEmpty || manager.isBusy || manager.isCapturing)
                            if manager.hasSavedCredential {
                                Button("Remove Saved Password", role: .destructive) {
                                    Task { await manager.removeMacPassword() }
                                }
                                .disabled(manager.isBusy || manager.isCapturing)
                            }
                        }
                    } header: { Text("Mac Password") } footer: {
                        Text("macOS has no third-party Face ID login API. Convenience unlock submits a saved password to the verified macOS login window. Your password is checked locally before saving and is never displayed or sent online.")
                    }

                    Section {
                        Toggle("Use Face Unlock", isOn: Binding(
                            get: { manager.automaticUnlockEnabled },
                            set: { value in Task { await manager.setAutomaticUnlockEnabled(value) } }))
                            .toggleStyle(.switch).controlSize(.small)
                            .disabled(!manager.automaticUnlockEnabled && (!acceptsConvenienceTradeoff ||
                                !manager.hasSavedCredential || !manager.hasRecentRecognitionTest || manager.isCapturing))
                        if !manager.automaticUnlockEnabled {
                            Toggle("Allow the vault key to stay in memory while enabled", isOn: $acceptsConvenienceTradeoff)
                                .toggleStyle(.checkbox)
                            if !manager.hasRecentRecognitionTest {
                                Text("Complete Test Recognition before enabling Face Unlock.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("A regular camera can be fooled by video. Automatic unlock keeps its vault key in memory across lock and sleep while Notchscape runs. Turning it off, quitting or switching users clears that authorization. This is less secure than Touch ID.")
                            .font(.caption).foregroundStyle(.secondary)
                    } header: { Text("Automatic Unlock") } footer: {
                        Text("After setup, scans start when the Mac locks or wakes locked. No timed session to start. macOS may ask you to authenticate again after Notchscape restarts. Unsupported login fields stay locked.")
                    }

                    Section("Apple Watch & Native Unlock") {
                        Label("macOS unlock always takes priority", systemImage: "applewatch")
                        Text("If Apple Watch, Touch ID or your password unlocks the Mac first, Notchscape cancels. It never copies your Mac password to the clipboard or types it into another app.")
                            .font(.caption).foregroundStyle(.secondary)
                        if manager.companionAuthenticationAvailable {
                            Label("Companion authentication is available", systemImage: "checkmark.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    Section("Feedback") {
                        Toggle("Haptic feedback", isOn: $manager.hapticFeedback)
                            .toggleStyle(.switch).controlSize(.small)
                            .disabled(!appHaptics).opacity(appHaptics ? 1 : 0.4)
                        if !appHaptics {
                            Text("App haptics are off in General.").font(.caption).foregroundStyle(.secondary)
                        }
                        Picker("Lock-screen presentation", selection: $manager.presentation) {
                            Text("Minimal").tag(FaceUnlockPresentation.minimal)
                            Text("Expanded guidance").tag(FaceUnlockPresentation.expanded)
                        }
                        Text("Lock-screen visuals follow your existing Show locked Home dropdown setting.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Section {
                        if !manager.automaticUnlockEnabled {
                            Button("Lock These Settings") { manager.lockSettings() }
                        }
                        Button("Delete All Face Unlock Data…", role: .destructive) { confirmDeleteVault = true }
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(manager.isBusy)

            Divider()
            HStack {
                Text("No app account or cloud sync.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !embedded {
                    Button("Done") { FaceUnlockWindowController.shared.close() }.keyboardShortcut(.cancelAction)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.effectiveAccent)
        .controlSize(.regular)
        .sheet(isPresented: Binding(get: { manager.showsCameraGuide }, set: { shown in
            if !shown && manager.showsCameraGuide { manager.cancelCapture() }
        })) {
            FaceScanSessionSheet(manager: manager)
        }
        .confirmationDialog("Delete this face?", isPresented: Binding(
            get: { identityToDelete != nil }, set: { if !$0 { identityToDelete = nil } })) {
                if let identity = identityToDelete {
                    Button("Delete \(identity.label)", role: .destructive) {
                        Task { await manager.deleteIdentity(identity.id) }
                        identityToDelete = nil
                    }
                }
            } message: { Text("Its encrypted enrollment is removed from this Mac.") }
        .confirmationDialog("Delete all Face Unlock data?", isPresented: $confirmDeleteVault) {
            Button("Delete Local Vault", role: .destructive) { Task { await manager.deleteAllData() } }
        } message: { Text("Removes enrolled faces, the saved Mac password and the vault key. Your Mac account is unchanged.") }
        .onDisappear { macPassword = ""; manager.closeSettings() }
        .onAppear { manager.refreshCompanionAvailability() }
        .onChange(of: manager.isVaultAuthorized) { _, authorized in
            if !authorized { macPassword = ""; acceptsConvenienceTradeoff = false }
        }
        .alert("Rename Appearance", isPresented: Binding(
            get: { identityToRename != nil }, set: { if !$0 { identityToRename = nil } })) {
                TextField("Name", text: $renamedLabel)
                Button("Cancel", role: .cancel) { identityToRename = nil }
                Button("Save") {
                    if let identity = identityToRename {
                        let label = renamedLabel
                        Task { await manager.renameIdentity(identity.id, label: label) }
                    }
                    identityToRename = nil
                }
            }
    }
}

/// Uses the already-authorized capture pipeline. Rendering this view never starts a camera.
struct FaceScanSessionSheet: View {
    @ObservedObject var manager: FaceUnlockManager

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                FaceScanCameraCard(source: manager.showsCameraGuide ? manager.cameraPreview : nil,
                    guidance: manager.captureGuidance, symbol: manager.captureSymbol, progress: manager.captureProgress)
            }
            Button("Cancel", role: .cancel) { manager.cancelCapture() }
                .keyboardShortcut(.cancelAction).buttonStyle(.bordered)
        }
        .padding(24).frame(width: 500, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct FaceScanCameraCard: View {
    var source: FaceCameraPreviewSource? = nil
    var image: CGImage? = nil // Synthetic/offscreen layout fixtures only.
    let guidance: String
    var symbol: String = "person.crop.square"
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var completed: Double { FaceScanPreviewPolicy.progress(progress) }
    private var hasPreview: Bool { source?.isValid == true || image != nil }

    var body: some View {
        VStack(spacing: 12) {
            Text("Face Scan").font(.title2.weight(.semibold))
            ZStack {
                Color.black
                if let source, source.isValid {
                    FaceCameraPreviewView(source: source).accessibilityHidden(true)
                } else if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                        .frame(width: 416, height: 300).scaleEffect(x: -1, y: 1)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 72, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.5)).accessibilityHidden(true)
                }
                FaceScanSurroundMask().fill(.black.opacity(0.42), style: FillStyle(eoFill: true))
                Ellipse().strokeBorder(.white.opacity(0.55), lineWidth: 1.5)
                    .frame(width: 216, height: 264)
                FaceScanProgressRing(progress: completed)
                    .stroke(Color.effectiveAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 216, height: 264)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: completed)
            }
            .frame(maxWidth: 416).frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Face scan camera guide")
            .accessibilityValue(hasPreview ? "Camera ready" : "Preparing camera")
            Label(guidance, systemImage: symbol)
                .font(.headline).multilineTextAlignment(.center)
                .frame(minHeight: 40).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
            Text(hasPreview ? "Keep your face inside the oval." : "Preparing the camera…")
                .font(.callout).foregroundStyle(.secondary)
            Label("Camera images aren’t saved or uploaded.", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
    }
}

private struct FaceScanProgressRing: Shape {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var arc = Path()
        arc.addRelativeArc(center: .zero, radius: 1, startAngle: .degrees(-90),
                           delta: .degrees(360 * FaceScanPreviewPolicy.progress(progress)))
        return arc.applying(CGAffineTransform(a: rect.width / 2, b: 0, c: 0,
            d: rect.height / 2, tx: rect.midX, ty: rect.midY))
    }
}

private struct FaceScanSurroundMask: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addEllipse(in: CGRect(x: rect.midX - 108, y: rect.midY - 132, width: 216, height: 264))
        return path
    }
}

struct FaceSetupChecklist: View {
    let authorized: Bool
    let hasFace: Bool
    let tested: Bool
    let hasPassword: Bool

    private var steps: [(String, String, Bool)] {
        [("Unlock settings", "Authenticate with Touch ID or your Mac password.", authorized),
         ("Add an appearance", "Follow the camera’s positioning and head-turn guide.", hasFace),
         ("Test recognition", "Check the result while your Mac stays unlocked.", tested),
         ("Save your Mac password", "Then review and enable automatic unlock below.", hasPassword)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Group {
                        if step.2 { Image(systemName: "checkmark.circle.fill") }
                        else { Text("\(index + 1)").font(.caption.weight(.semibold)) }
                    }
                    .frame(width: 24, height: 24)
                    .foregroundStyle(step.2 || index == steps.firstIndex(where: { !$0.2 }) ? Color.effectiveAccent : .secondary)
                    .background(Color.secondary.opacity(0.08), in: Circle())
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.0).font(.callout.weight(.medium))
                        Text(step.1).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(step.2 ? "Complete" : index == steps.firstIndex(where: { !$0.2 }) ? "Current step" : "Not completed")
            }
        }.padding(.vertical, 6)
    }
}
