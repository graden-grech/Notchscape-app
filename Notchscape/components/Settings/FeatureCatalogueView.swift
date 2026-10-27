import SwiftUI
import Defaults
import AppKit

struct FeatureCatalogueView: View {
    @Default(.clipboardHistoryEnabled) private var clipboard
    @Default(.quickNotesEnabled) private var notes
    @Default(.deviceControlsEnabled) private var devices
    @Default(.textCaptureEnabled) private var textCapture
    @Default(.enableDownloadListener) private var downloads
    @Default(.systemDashboardEnabled) private var system
    @ObservedObject private var modes = WorkspaceModeManager.shared
    var body: some View {
        Form {
            Section("Tools on Demand") {
                LabeledContent("Workspace Tools", value: "Calculator, snippets, Quicklinks, clocks, event countdown")
                Button("Capture Studio…") { CaptureStudioController.shared.show() }
                Text("Image markup, explicit capture library indexing, silent screen recording, trim and media/GIF conversion. Closing Capture Studio stops recording and clears its private image/search cache.").font(.caption).foregroundStyle(.secondary)
                Button("Windows & Workspaces…") { WindowToolsController.shared.show() }
                Text("App switching works without extra access. Window positioning needs Accessibility. Single-window previews additionally require Screen Recording and occur only when requested.").font(.caption).foregroundStyle(.secondary)
                Text("No module starts screen/microphone recording just because its page is enabled.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Background Modules") {
                Toggle("Clipboard history", isOn: $clipboard)
                Text("Off stops clipboard polling. Existing encrypted history remains until explicitly cleared. Lock and Presentation pause collection independently.").font(.caption).foregroundStyle(.secondary)
                Toggle("Quick Notes", isOn: $notes)
                Text("Off closes the pinned scratchpad and prevents editing; encrypted notes are preserved.").font(.caption).foregroundStyle(.secondary)
                Toggle("Bluetooth and audio controls", isOn: $devices)
                Text("Off stops device polling and notification observers. Optional low-battery alerts poll every two minutes while enabled; visible Devices refreshes every 30 seconds. Preferred audio routing uses hot-plug events.").font(.caption).foregroundStyle(.secondary)
                Toggle("Text and QR recognition", isOn: $textCapture)
                Text("On-demand only. Off invalidates pending recognition results. No OCR screen-watching loop.").font(.caption).foregroundStyle(.secondary)
                Toggle("Download watching", isOn: $downloads)
                Text("Filesystem events while idle, bounded two-second progress checks while a download is active. Off/lock/Presentation releases folder observers and scoped access.").font(.caption).foregroundStyle(.secondary)
                Toggle("System tab", isOn: $system)
                Text("CPU/memory/network/disk sampling runs only while the System view is visible. Hiding a tab does not claim to unload every shared service in the app.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Privacy & Lifecycle") {
                LabeledContent("Current Mode", value: modes.active?.title ?? "None")
                Text("Private tool windows close when locked or presenting. Keep Awake releases its power assertion on expiry, lock, Travel, Presentation and quit. Stopwatch/focus state is session-only. Capture search text is memory-only. Accounts remain unavailable in this public build.").foregroundStyle(.secondary)
                Button("Tools Settings…") { SettingsWindowController.shared.showWindow(section: "Tools") }
            }
            Section("Finder & Shortcuts") {
                Text("Finder → Services offers Add to Shelf, Convert Images to PNG, and Create PDF. macOS may require enabling these in Keyboard → Keyboard Shortcuts → Services after installing the app. All actions operate on the selected files and preserve originals.")
                Text("Apple Shortcuts: Open Notchscape Commands and Open Notchscape Workspace Tools. Safe notchscape://open/commands, /tools and /settings links only open foreground surfaces; they cannot run commands or start recording.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

struct MusicQueueCapabilityView: View {
    @ObservedObject private var music = MusicManager.shared
    var body: some View {
        Form {
            Section("Up Next") {
                Label("Queue unavailable from this player connection", systemImage: "list.bullet")
                Text("The existing Apple Music, Spotify and system Now Playing connections do not provide a reliable public Up Next queue. A playlist or last-played list is not substituted for the real queue.").foregroundStyle(.secondary)
                if let id = music.bundleIdentifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    Button("Open Current Player") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
                }
                if !music.isPlayerIdle { LabeledContent("Now Playing", value: music.songTitle) }
            }
            Text("A real queue will require a player-supported integration and its explicit authorization. Notchscape does not scrape your account or ask you to paste an access token.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }
}
