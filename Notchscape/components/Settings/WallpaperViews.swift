import AppKit
import Defaults
import SwiftUI

@MainActor
final class NotchWallpaperWindowController: NSWindowController {
    static let shared = NotchWallpaperWindowController()
    private init() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 800, height: 610),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Wallpapers"; window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.toolbarStyle = .unified; window.titlebarSeparatorStyle = .none
        window.toolbar = NSToolbar(identifier: "NotchWallpapersToolbar")
        window.minSize = .init(width: 600, height: 440)
        window.contentView = NSHostingView(rootView: WallpaperBrowserView(expanded: true).padding(16)
            .background(LiquidGlassSettingsBackground()))
        window.setFrameAutosaveName("NotchWallpapers")
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show() {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any], session["CGSSessionScreenIsLocked"] as? Bool != true else { return }
        if window?.isVisible != true { window?.center() }
        showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
}

struct WallpaperBrowserView: View {
    var expanded = false
    @ObservedObject private var library = NotchWallpaperManager.shared
    @ObservedObject private var performance = AppPerformanceManager.shared
    @ObservedObject private var modes = WorkspaceModeManager.shared
    @Default(.appTheme) private var theme
    @Default(.useCustomAccentColor) private var customAccent
    @Default(.customAccentColorData) private var accentData
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var matchTheme = false
    @State private var season: WallpaperSeason?
    @State private var sort = WallpaperBrowseSort.collection
    @State private var previewWallpaper: Wallpaper?
    @State private var selected: String?
    @State private var screens = NSScreen.screens
    private var accent: Color { Color(nsColor: .resolvedAccent(theme: theme, customEnabled: customAccent, customData: accentData)) }
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var wallpapers: [Wallpaper] {
        sort.sorted(WallpaperCatalog.wallpapers(for: library.platform).filter { wallpaper in
            (!favoritesOnly || library.favorites.contains(wallpaper.id))
                && (!matchTheme || WallpaperThemeMatch.matching(theme.rawValue).contains(wallpaper))
                && (season.map { SeasonalWallpaperCatalog.contains(wallpaper, season: $0) } ?? true)
                && (query.isEmpty || "\(wallpaper.name) \(wallpaper.displayRelease) \(wallpaper.source.credit)".localizedCaseInsensitiveContains(query))
        })
    }
    private var hasFilters: Bool { favoritesOnly || matchTheme || season != nil || !query.isEmpty }
    // Applying a hidden selection is surprising after changing a search or filter.
    private var choice: Wallpaper? { wallpapers.first { $0.id == selected } }
    @ViewBuilder var body: some View {
        if #available(macOS 26.0, *), !performance.lowImpact, !performance.reduceTransparency {
            GlassEffectContainer(spacing: 4) { browserContent }
        } else {
            browserContent
        }
    }
    private var browserContent: some View {
        VStack(alignment: .leading, spacing: expanded ? 12 : 8) {
            navigationControls
            if expanded { options }
            if wallpapers.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: expanded ? [GridItem(.adaptive(minimum: 180), spacing: 12)] : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: expanded ? 12 : 6) {
                        ForEach(wallpapers) { wallpaper in card(wallpaper) }
                    }.padding(4)
                }.scrollIndicators(expanded ? .automatic : .hidden)
            }
            applicationControls
            if expanded {
                HStack(spacing: 8) {
                    Text("MacScapes · \(wallpapers.count) \(wallpapers.count == 1 ? "wallpaper" : "wallpapers")")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Menu {
                        Link("512 Pixels macOS archive", destination: URL(string: "https://512pixels.net/projects/default-mac-wallpapers-in-5k/")!)
                        Link("Windows UI Assets archive", destination: URL(string: "https://github.com/bartekl1/windows-ui-assets/tree/main/Wallpapers")!)
                        Link("Unsplash", destination: URL(string: "https://unsplash.com/")!)
                        Link("NASA Image and Video Library", destination: URL(string: "https://images.nasa.gov/")!)
                    } label: { Label("Sources", systemImage: "info.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("View the original wallpaper archives")
                }.font(.caption2).foregroundStyle(.secondary)
            }
        }
        .controlSize(.small).tint(accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if selected == nil { selected = library.lastApplied }
        }
        .onChange(of: library.platform) { _, _ in selected = nil }
        .sheet(item: $previewWallpaper) { wallpaper in
            WallpaperPreviewSheet(wallpaper: wallpaper).tint(accent)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in screens = NSScreen.screens }
        .transaction { transaction in
            if performance.suppressAnimations {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }
    private var navigationControls: some View {
        HStack(spacing: 8) {
            Picker("Collection", selection: $library.platform) {
                ForEach(WallpaperPlatform.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu).labelsHidden()
            .frame(width: expanded ? 170 : 140)
            .accessibilityLabel("Wallpaper collection")
            WallpaperControlButton(title: "Favorites", systemImage: favoritesOnly ? "heart.fill" : "heart",
                                   showsTitle: expanded, selected: favoritesOnly, accent: accent) {
                favoritesOnly.toggle()
            }
            .help(favoritesOnly ? "Show all wallpapers in this collection" : "Show only favorites in this collection")
            .accessibilityLabel("Show only favorites")
            .accessibilityValue(favoritesOnly ? "On" : "Off")
            filterMenu
            Spacer(minLength: 0)
            if expanded {
                WallpaperSearchField(text: $search)
                    .frame(minWidth: 120, maxWidth: 240, minHeight: 26, maxHeight: 26)
            } else {
                WallpaperControlButton(title: "Open Wallpaper Library", systemImage: "arrow.up.left.and.arrow.down.right",
                                       showsTitle: false, accent: accent) {
                    NotchWallpaperWindowController.shared.show()
                }.help("Open Wallpaper Library")
            }
        }
    }
    private var filterMenu: some View {
        Menu {
            Section("App Theme: \(theme.title)") {
                Toggle("Match Current Theme", isOn: $matchTheme)
            }
            Picker("Season", selection: $season) {
                Text("Any Season").tag(WallpaperSeason?.none)
                ForEach(WallpaperSeason.allCases) { season in Text(season.rawValue).tag(Optional(season)) }
            }
            Picker("Sort", selection: $sort) {
                ForEach(WallpaperBrowseSort.allCases) { sort in Text(sort.title).tag(sort) }
            }
            Divider()
            Button("Surprise Preview", systemImage: "sparkles") { surprisePreview() }.disabled(wallpapers.isEmpty)
            Button("Clear Filters", systemImage: "line.3.horizontal.decrease") { clearFilters() }.disabled(!hasFilters)
        } label: {
            Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                .font(.caption.weight(.medium)).foregroundStyle(hasFilters ? accent : .primary)
                .frame(width: NotchHeaderMetrics.controlHeight, height: NotchHeaderMetrics.controlHeight)
                .liquidGlassCapsule(tint: hasFilters ? accent : .white)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Filter by app theme or season, sort, or discover a surprise preview. Browsing never changes your wallpaper.")
        .accessibilityLabel("Wallpaper filters and previews")
        .accessibilityValue(hasFilters ? "Filters active" : "No filters")
    }
    private var options: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Display").font(.caption).foregroundStyle(.secondary)
                Picker("Display", selection: $library.display) {
                    Text("Main display").tag("main")
                    Text("All displays").tag("all")
                    ForEach(screens.compactMap { screen in screen.displayUUID.map { ($0, screen.localizedName) } }, id: \.0) { id, name in
                        Text(name).tag(id)
                    }
                    if library.display != "main", library.display != "all", !screens.contains(where: { $0.displayUUID == library.display }) {
                        Text("Disconnected display").tag(library.display)
                    }
                }
                .pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity)
                .accessibilityLabel("Apply wallpaper to display")
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text("Change Automatically").font(.caption).foregroundStyle(.secondary)
                Picker("Change automatically", selection: $library.rotation) {
                    ForEach(WallpaperRotation.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity)
                .accessibilityLabel("Change wallpaper automatically")
                .help("Rotation uses the selected collection and its favorites. Search, theme, and season filters only affect browsing and the Shuffle button.")
                if library.rotation != .off, let mode = modes.active, mode.pauseWallpapers {
                    Label("Paused by \(mode.title) Mode", systemImage: "pause.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.disabled(library.busy)
    }
    @ViewBuilder private var emptyState: some View {
        if expanded {
            ContentUnavailableView {
                Label(favoritesOnly ? "No Favorites in This Collection" : "No Matching Wallpapers",
                      systemImage: favoritesOnly ? "heart" : "magnifyingglass")
            } description: {
                Text(favoritesOnly ? "No saved favorites match these filters. Clear filters to browse the collection." : "Try another collection, or clear your search, theme, and season filters.")
            } actions: {
                Button("Clear Filters") { clearFilters() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                Image(systemName: favoritesOnly ? "heart" : "line.3.horizontal.decrease").font(.title2).foregroundStyle(.secondary)
                Text("No matching wallpapers").font(.caption.weight(.medium))
                Button("Show All Wallpapers") { clearFilters() }.font(.caption)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func clearFilters() { search = ""; favoritesOnly = false; matchTheme = false; season = nil }
    private func surprisePreview() {
        let alternatives = wallpapers.filter { $0.id != selected }
        previewWallpaper = (alternatives.isEmpty ? wallpapers : alternatives).randomElement()
    }
    private func shuffleVisibleWallpapers() {
        let favorites = wallpapers.filter { library.favorites.contains($0.id) }
        let pool = favorites.isEmpty ? wallpapers : favorites
        let alternatives = pool.filter { $0.id != library.lastApplied }
        if let wallpaper = (alternatives.isEmpty ? pool : alternatives).randomElement() { library.apply(wallpaper) }
    }
    private var applicationControls: some View {
        HStack(spacing: 8) {
            if library.busy {
                ProgressView().controlSize(.small).accessibilityLabel("Applying wallpaper")
            } else if library.failed {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
            }
            Text(library.status ?? choice?.name ?? "Choose a wallpaper, then Apply.")
                .font(.caption).foregroundStyle(library.failed ? .orange : .secondary)
                .lineLimit(expanded ? 2 : 1).frame(maxWidth: .infinity, alignment: .leading)
            if expanded {
                if let choice {
                    WallpaperControlButton(title: "Preview Selected Wallpaper", systemImage: "eye", showsTitle: false, accent: accent) {
                        previewWallpaper = choice
                    }.help("Preview the full composition and image credits")
                }
                WallpaperControlButton(title: "Undo", systemImage: "arrow.uturn.backward", accent: accent) {
                    library.undo()
                }.disabled(!library.canUndo || library.busy)
                    .help("Restore the previous wallpaper on the affected displays")
            }
            WallpaperControlButton(title: "Shuffle", systemImage: "shuffle", showsTitle: expanded, accent: accent) {
                shuffleVisibleWallpapers()
            }.disabled(library.busy || wallpapers.isEmpty)
                .help("Apply a random wallpaper matching the current filters, preferring favorites")
            applyButton
        }
    }
    @ViewBuilder private var applyButton: some View {
        if #available(macOS 26.0, *), !performance.lowImpact, !performance.reduceTransparency {
            Button("Apply", action: applySelection).buttonStyle(.glassProminent)
                .disabled(choice == nil || library.busy)
                .accessibilityLabel("Apply selected wallpaper")
        } else {
            Button("Apply", action: applySelection).buttonStyle(.borderedProminent)
                .disabled(choice == nil || library.busy)
                .accessibilityLabel("Apply selected wallpaper")
        }
    }
    private func applySelection() { if let choice { library.apply(choice) } }
    private func card(_ wallpaper: Wallpaper) -> some View {
        let isSelected = selected == wallpaper.id
        let isFavorite = library.favorites.contains(wallpaper.id)
        return VStack(alignment: .leading, spacing: 4) {
            Button { selected = wallpaper.id } label: {
                WallpaperThumbnail(url: wallpaper.previewURL)
                    .frame(height: expanded ? 105 : 55).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? accent : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 0.5))
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette)
                                .foregroundStyle(.white, accent).font(.system(size: expanded ? 18 : 14, weight: .semibold))
                                .padding(expanded ? 8 : 5).accessibilityHidden(true)
                        }
                    }
            }.buttonStyle(.plain).accessibilityLabel(wallpaper.name)
                .accessibilityValue(wallpaper.displayRelease)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .help("\(wallpaper.name) · \(wallpaper.displayRelease)")
                .contextMenu {
                    Button("Preview and Credits") { previewWallpaper = wallpaper }
                    Button("Apply Wallpaper") { library.apply(wallpaper) }.disabled(library.busy)
                    Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") { library.toggleFavorite(wallpaper) }
                }
            HStack(spacing: 4) {
                Text(wallpaper.name).font(expanded ? .callout.weight(.medium) : .caption.weight(.medium)).lineLimit(1)
                Spacer(minLength: 0)
                Button { library.toggleFavorite(wallpaper) } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart").frame(width: 22, height: 22)
                }.buttonStyle(.borderless).foregroundStyle(isFavorite ? accent : .secondary)
                    .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                    .accessibilityLabel("\(isFavorite ? "Remove" : "Add") \(wallpaper.name) \(isFavorite ? "from" : "to") favorites")
                    .accessibilityValue(isFavorite ? "Favorite" : "Not a favorite")
            }
            if expanded {
                HStack(spacing: 4) {
                    Text(wallpaper.displayRelease).lineLimit(1)
                    if library.lastApplied == wallpaper.id {
                        Spacer(minLength: 0)
                        Text("Current").fontWeight(.medium)
                    }
                }.font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// Match the notch's shared control material without putting glass over photos.
private struct WallpaperControlButton: View {
    let title: String
    let systemImage: String
    var showsTitle = true
    var selected = false
    let accent: Color
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        Button(action: action) {
            Group {
                if showsTitle { Label(title, systemImage: systemImage) }
                else { Image(systemName: systemImage) }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(selected ? accent : .primary)
            .padding(.horizontal, showsTitle ? 10 : 0)
            .frame(minWidth: NotchHeaderMetrics.controlHeight, minHeight: NotchHeaderMetrics.controlHeight)
            .contentShape(Capsule())
            .liquidGlassCapsule(tint: selected ? accent : .white)
            .opacity(isEnabled ? 1 : 0.4)
        }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// NSSearchField supplies native clear/cancel behavior and the current Mac style.
private struct WallpaperSearchField: NSViewRepresentable {
    @Binding var text: String
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search Wallpapers"
        field.controlSize = .small
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Search wallpapers")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

private struct WallpaperThumbnail: View {
    let url: URL
    var contentMode: ContentMode = .fill
    var detail = false
    @State private var image: NSImage?
    @State private var failed = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.secondary.opacity(0.12)
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: failed ? "photo.badge.exclamationmark" : "photo")
                        if failed { Text("Preview unavailable").font(.caption2) }
                    }.foregroundStyle(.secondary)
                }
            }
        }
        .task(id: url) {
            image = nil; failed = false
            do { let result = try await WallpaperFileStore.shared.thumbnail(url, detail: detail); try Task.checkCancellation(); image = result }
            catch { if !Task.isCancelled { failed = true } }
        }
    }
}

private struct WallpaperPreviewSheet: View {
    let wallpaper: Wallpaper
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(wallpaper.name).font(.title3.weight(.semibold))
                    Text(wallpaper.displayRelease).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            WallpaperThumbnail(url: wallpaper.detailPreviewURL, contentMode: .fit, detail: true)
                .frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Full-composition preview of \(wallpaper.name)")
            Text(wallpaper.source.credit).font(.callout.weight(.medium)).textSelection(.enabled)
            Text(wallpaper.source.rights).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Link("Original Source", destination: wallpaper.source.pageURL)
                if let license = wallpaper.source.licenseURL { Link("Usage Guidelines", destination: license) }
                Spacer(minLength: 0)
                Text("Preview only · Desktop unchanged").foregroundStyle(.secondary)
            }.font(.caption)
        }
        .padding(20).frame(width: 560).controlSize(.small)
        .background(LiquidGlassSettingsBackground())
    }
}

struct WallpaperSettings: View {
    @Default(.showWallpapersTab) private var showTab
    @ObservedObject private var library = NotchWallpaperManager.shared
    @State private var importMessage: String?
    var body: some View {
        Form {
            Section {
                Toggle("Show Wallpapers tab in the notch", isOn: $showTab)
                Button("Open Wallpaper Library…") { NotchWallpaperWindowController.shared.show() }
                Button("Import MacScapes Favorites") {
                    library.importMacScapesFavorites()
                    importMessage = library.status
                }
                if let importMessage { Text(importMessage).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("Wallpapers") } footer: {
                Text("Your MacScapes library, built into Notchscape. Collection, favorites, display selection, and optional rotation are managed together in the library. Importing favorites never changes the original app.")
            }
            Section {
                LabeledContent("Privacy", value: "No analytics or account")
                LabeledContent("Automatic rotation", value: library.rotation.title)
            } header: { Text("On Your Mac") } footer: {
                Text("Previews and selected images are downloaded on demand. Archive thumbnails use the wsrv.nl image proxy; full images come from the listed archives. Originals remain the property of their rights holders. Only the selected display’s current desktop is changed; this does not replace the lock screen, screen saver, or every Space. Rotation pauses while locked or in Presentation or Travel Mode. It does not sync with or control a separately running MacScapes app.")
            }
        }.navigationTitle("Wallpapers")
    }
}
