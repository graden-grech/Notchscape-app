import SwiftUI
import AppKit

/// Replay has its own standard window, so a theme or import sheet in Settings
/// never competes with the tour for the same presentation slot.
@MainActor
final class SettingsTourWindowController: NSWindowController {
    static let shared = SettingsTourWindowController()
    private init() { super.init(window: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        if let window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let tourWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
        tourWindow.title = "Notchscape Settings Tour"
        tourWindow.identifier = NSUserInterfaceItemIdentifier("NotchscapeSettingsTourWindow")
        tourWindow.isRestorable = false
        tourWindow.isReleasedWhenClosed = false
        tourWindow.contentView = NSHostingView(rootView: SettingsTourView(
            onFinish: { [weak tourWindow] in tourWindow?.close() },
            onSkip: { [weak tourWindow] in tourWindow?.close() },
            onOpenSection: { [weak tourWindow] section in
                tourWindow?.close()
                SettingsWindowController.shared.showWindow(section: section)
            }))
        self.window = tourWindow
        tourWindow.center()
        NSApp.activate(ignoringOtherApps: true)
        tourWindow.makeKeyAndOrderFront(nil)
    }
}

/// Shared first-run/replay tour. No feature preference bindings or permission
/// requests: each optional Open Settings action goes to the real settings page.
struct SettingsTourView: View {
    @ObservedObject private var performance = AppPerformanceManager.shared
    @State private var progress = SettingsTourProgress()
    let onFinish: () -> Void
    let onSkip: () -> Void
    let onOpenSection: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings Tour").font(.headline)
                Spacer()
                Button("Skip Tour") { progress.skip(); onSkip() }
                    .help("Close the tour without changing any settings")
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)

            ProgressView(value: Double(progress.index + 1), total: Double(SettingsTourChapter.allCases.count))
                .accessibilityLabel("Step \(progress.index + 1) of \(SettingsTourChapter.allCases.count)")
                .padding(.horizontal, 24)

            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: progress.chapter.symbol)
                                .font(.system(size: 30, weight: .medium)).foregroundStyle(Color.effectiveAccent)
                                .accessibilityHidden(true)
                            Text(progress.chapter.title).font(.title2.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                            Text(progress.chapter.subtitle).font(.callout).foregroundStyle(.secondary)
                        }

                        ForEach(progress.chapter.topics(accountsEnabled: AccountFeaturePolicy.enabled), id: \.sectionID) { topic in
                            if let destination = NotchSettingsDestination.all.first(where: { $0.id == topic.sectionID }) {
                                topicCard(topic, destination: destination)
                            }
                        }

                        Text("Nothing changes while you tour. Open a page only when you're ready to choose a setting.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .id("chapterTop")
                }
                .onChange(of: progress.index) { _, _ in reader.scrollTo("chapterTop", anchor: .top) }
            }

            Divider()
            HStack {
                Button("Back") { progress.back() }.disabled(progress.isFirst)
                Spacer()
                Text("\(progress.index + 1) of \(SettingsTourChapter.allCases.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(progress.isLast ? "Done" : "Next") {
                    progress.next()
                    if progress.isFinished { onFinish() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.effectiveAccent)
        .controlSize(.regular)
        .transaction { if performance.suppressAnimations { $0.animation = nil; $0.disablesAnimations = true } }
    }

    private func topicCard(_ topic: SettingsTourTopic, destination: NotchSettingsDestination) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(destination.title, systemImage: destination.symbol).font(.headline)
            Text(topic.summary).font(.callout)
            Text(topic.suggestion).font(.caption).foregroundStyle(.secondary)
            Button("Open \(destination.title) Settings", systemImage: "arrow.up.forward") {
                onOpenSection(destination.id)
            }
            .buttonStyle(.link).font(.callout)
            .accessibilityHint("Leaves the tour and opens this settings page")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
