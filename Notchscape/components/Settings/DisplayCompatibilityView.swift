import AppKit
import SwiftUI

/// A separate, disposable preview. It never changes the user's display style or
/// stores a simulated camera profile as real hardware geometry.
@MainActor
final class DisplayCompatibilityWindowController: NSWindowController, NSWindowDelegate, ObservableObject {
    static let shared = DisplayCompatibilityWindowController()

    @Published var preset: DisplayPreviewPreset = .floatingCamera
    @Published private(set) var isExpanded = false
    @Published private(set) var routedClicks = 0
    @Published private(set) var ordinaryClicks = 0
    @Published private(set) var targetReady = false
    private weak var measuredWindow: NSWindow?
    private var targetRect = CGRect.zero

    lazy var interceptor = IslandClickInterceptor { [weak self] in
        guard let self else { return }
        self.routedClicks += 1
        self.toggleSampleHome()
    }

    private init() { super.init(window: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        if let window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        interceptor.stop()
        isExpanded = false
        targetReady = false
        routedClicks = 0
        ordinaryClicks = 0
        let preview = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 690),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        preview.title = "Notchscape Display Compatibility"
        preview.identifier = NSUserInterfaceItemIdentifier("NotchscapeDisplayCompatibilityWindow")
        preview.isReleasedWhenClosed = false
        preview.isRestorable = false
        preview.delegate = self
        let host = NSHostingView(rootView: DisplayCompatibilityView(controller: self, interceptor: interceptor)
            .frame(width: 720, height: 690))
        host.sizingOptions = []
        preview.contentView = host
        preview.setContentSize(NSSize(width: 720, height: 690))
        window = preview
        preview.center()
        NSApp.activate(ignoringOtherApps: true)
        preview.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        interceptor.stop()
        targetReady = false
        measuredWindow = nil
    }

    func changePreset() {
        interceptor.stop()
        isExpanded = false
        routedClicks = 0
    }

    func measureTarget(_ view: NSView) {
        guard let viewWindow = view.window, viewWindow === window,
              let content = viewWindow.contentView else { return }
        let rect = view.convert(view.bounds, to: content)
        guard rect.width > 20, rect.height > 10 else { return }
        if targetRect != rect || measuredWindow !== viewWindow {
            // A changed target requires an explicit restart, never a wider tap.
            if interceptor.status.isRunning { interceptor.stop() }
            targetRect = rect
            measuredWindow = viewWindow
        }
        if !targetReady { targetReady = true }
    }

    func setClickTestEnabled(_ enabled: Bool) {
        guard enabled else { interceptor.stop(); return }
        guard let measuredWindow, measuredWindow === window,
              let screen = measuredWindow.screen,
              let snapshot = NSScreenDisplayGeometryAdapter.snapshot(for: screen),
              targetReady else { return }

        // Exclude the entire central camera lane, including its padding. The
        // surrounding rectangles are confined to this window's visible sample.
        let inset = targetRect.insetBy(dx: 7, dy: 4)
        let cameraLane: CGFloat = 58
        let sideWidth = (inset.width - cameraLane) / 2
        guard sideWidth > 0 else { return }
        let allowed = [
            CGRect(x: inset.minX, y: inset.minY, width: sideWidth, height: inset.height),
            CGRect(x: inset.maxX - sideWidth, y: inset.minY, width: sideWidth, height: inset.height)
        ]
        interceptor.updateSession(isActive: NSApp.isActive, isUnlocked: WorkspaceAccess.unlocked, isAwake: true)
        let protectedCameraLane = CGRect(x: targetRect.midX - cameraLane / 2,
            y: targetRect.minY, width: cameraLane, height: targetRect.height)
        interceptor.startTestWindow(measuredWindow, contentViewLocalRects: allowed,
            coordinateSpace: snapshot.coordinates, protectedContentViewLocalRects: [protectedCameraLane])
    }

    func toggleSampleHome() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || AppPerformanceManager.shared.suppressAnimations {
            isExpanded.toggle()
        } else {
            withAnimation(.smooth(duration: 0.25)) { isExpanded.toggle() }
        }
    }

    func testOrdinaryControl() { ordinaryClicks += 1 }
}

enum DisplayPreviewPreset: String, CaseIterable, Identifiable {
    case attachedNotch, floatingCamera, externalDisplay
    var id: Self { self }
    var title: String {
        switch self {
        case .attachedNotch: "Notched Mac"
        case .floatingCamera: "Floating camera"
        case .externalDisplay: "External display"
        }
    }
    var caption: String {
        switch self {
        case .attachedNotch: "Controls stay beside the camera housing."
        case .floatingCamera: "A separate camera area stays clear as the preview expands."
        case .externalDisplay: "Notchscape's own island fits inside the sample menu bar."
        }
    }
}

private struct DisplayCompatibilityView: View {
    @ObservedObject var controller: DisplayCompatibilityWindowController
    @ObservedObject var interceptor: IslandClickInterceptor
    @State private var showGeometry = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Display Compatibility").font(.title2.weight(.semibold))
                Text("Preview layouts and try click routing inside this window.")
                    .foregroundStyle(.secondary)
            }

            Picker("Sample display", selection: $controller.preset) {
                ForEach(DisplayPreviewPreset.allCases) { preset in Text(preset.title).tag(preset) }
            }
            .pickerStyle(.segmented)
            .onChange(of: controller.preset) { controller.changePreset() }

            sampleDisplay

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Test island click routing", isOn: Binding(
                    get: { interceptor.status.isRunning },
                    set: { controller.setClickTestEnabled($0) }))
                    .toggleStyle(.switch).controlSize(.small)
                    .disabled(!controller.targetReady)
                    .accessibilityHint("Tests the two sides of the sample island in this window only. Stops when you leave the window.")
                Text(interceptor.status.message)
                    .font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("IslandClickTestStatus")
                HStack {
                    Label("\(controller.routedClicks) routed clicks", systemImage: "cursorarrow.click")
                    Spacer()
                    Button("Test a normal control (\(controller.ordinaryClicks))") { controller.testOrdinaryControl() }
                }
                .font(.caption)
            }

            DisclosureGroup("This Mac's reported geometry", isExpanded: $showGeometry) {
                displayGeometrySummary.font(.caption).foregroundStyle(.secondary).padding(.top, 6)
            }
            .font(.callout)

            Spacer(minLength: 0)
            Divider()
            HStack(alignment: .bottom, spacing: 20) {
                Text("Experimental. These are sample layouts, not measured new-Mac dimensions. Native island interception, touch and system-triggered activities still need testing on the new hardware.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Done") { controller.close() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.effectiveAccent)
        .controlSize(.regular)
        .onDisappear { interceptor.stop() }
    }

    private var sampleDisplay: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color.indigo.opacity(0.18), Color.blue.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "apple.logo")
                        Text("Notchscape").fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "wifi")
                        Image(systemName: "battery.75percent")
                    }
                    .font(.system(size: 10)).padding(.horizontal, 14).frame(height: 28)
                    .background(.thinMaterial)
                    Spacer()
                }

                VStack(spacing: 8) {
                    sampleIsland
                    if controller.isExpanded { sampleHome.transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity)) }
                }
                .padding(.top, controller.preset == .attachedNotch ? 0 : 5)
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.08)) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sample display, \(controller.preset.title)")

            HStack {
                Text(controller.preset.caption).foregroundStyle(.secondary)
                Spacer()
                Button(controller.isExpanded ? "Close sample Home" : "Open sample Home") { controller.toggleSampleHome() }
                    .buttonStyle(.link)
            }
            .font(.caption)
        }
    }

    private var sampleIsland: some View {
        HStack(spacing: 0) {
            Button { controller.toggleSampleHome() } label: {
                Image(systemName: "music.note").frame(maxWidth: .infinity, minHeight: 36)
            }
            .accessibilityLabel("Open sample Home from music side")
            Color.black.frame(width: 58)
                .overlay {
                    if controller.preset != .externalDisplay {
                        Capsule().fill(Color.white.opacity(0.05)).frame(width: 38, height: 16)
                    }
                }
                .accessibilityLabel("Camera exclusion area")
            Button { controller.toggleSampleHome() } label: {
                Image(systemName: "sparkle").foregroundStyle(Color.purple.opacity(0.9))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .accessibilityLabel("Open sample Home from AI side")
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 210, height: 36)
        .background(.black, in: RoundedRectangle(cornerRadius: controller.preset == .attachedNotch ? 10 : 18))
        .background {
            IslandClickTargetProbe(onMeasure: controller.measureTarget)
        }
    }

    private var sampleHome: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Weather", systemImage: "cloud.sun.fill").foregroundStyle(.secondary)
                Text("72°").font(.system(size: 30, weight: .light, design: .rounded))
                Text("Sample conditions").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Label("AI activity", systemImage: "sparkle").foregroundStyle(.secondary)
                Text("Ready when you are").font(.headline)
                Text("Sample task").font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(22)
        .frame(width: 370, height: 154)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder private var displayGeometrySummary: some View {
        if let screen = controller.window?.screen,
           let snapshot = NSScreenDisplayGeometryAdapter.snapshot(for: screen) {
            HStack(alignment: .top) {
                Text(screen.localizedName)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Top safe inset: \(snapshot.systemTopSafeInset, specifier: "%.0f") pt")
                    if let gap = snapshot.reportedTopGap {
                        Text("Reported top gap: \(gap.width, specifier: "%.0f") × \(gap.height, specifier: "%.0f") pt")
                    } else { Text("No camera gap reported") }
                }
            }
        } else { Text("Display geometry is unavailable. Click routing stays off.") }
    }
}

/// Obtains real NSWindow content coordinates rather than treating SwiftUI's
/// global space as Quartz coordinates. This view never handles input itself.
private struct IslandClickTargetProbe: NSViewRepresentable {
    let onMeasure: @MainActor (NSView) -> Void
    func makeNSView(context: Context) -> ProbeView { ProbeView(onMeasure: onMeasure) }
    func updateNSView(_ view: ProbeView, context: Context) { view.reportWhenLaidOut() }

    final class ProbeView: NSView {
        let onMeasure: @MainActor (NSView) -> Void
        private var reportPending = false
        init(onMeasure: @escaping @MainActor (NSView) -> Void) {
            self.onMeasure = onMeasure
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); reportWhenLaidOut() }
        override func layout() { super.layout(); reportWhenLaidOut() }
        func reportWhenLaidOut() {
            guard !reportPending else { return }
            reportPending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reportPending = false
                self.onMeasure(self)
            }
        }
    }
}
