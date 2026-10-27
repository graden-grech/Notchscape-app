import Defaults
import SwiftUI
import UniformTypeIdentifiers

enum PresetAccentColor: String, CaseIterable, Identifiable {
    case blue = "Blue"
    case purple = "Purple"
    case pink = "Pink"
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case graphite = "Graphite"

    var id: String { self.rawValue }

    var color: Color {
        switch self {
        case .blue: return Color(red: 0.0, green: 0.478, blue: 1.0)
        case .purple: return Color(red: 0.686, green: 0.322, blue: 0.871)
        case .pink: return Color(red: 1.0, green: 0.176, blue: 0.333)
        case .red: return Color(red: 1.0, green: 0.271, blue: 0.227)
        case .orange: return Color(red: 1.0, green: 0.584, blue: 0.0)
        case .yellow: return Color(red: 1.0, green: 0.8, blue: 0.0)
        case .green: return Color(red: 0.4, green: 0.824, blue: 0.176)
        case .graphite: return Color(red: 0.557, green: 0.557, blue: 0.576)
        }
    }
}

struct HomeLayoutSettings: View {
    @Default(.homeWidgetOrder) private var order
    @Default(.hiddenHomeWidgets) private var hidden
    @Default(.weatherTilePosition) private var legacyWeatherPosition
    @Default(.weatherOnLiveTab) private var weatherOnLiveTab
    @Default(.weatherEnabled) private var weatherEnabled
    @Default(.showCalendar) private var showCalendar
    @State private var dragged: HomeWidget?

    private var widgets: [HomeWidget] { HomeLayoutPolicy.normalized(order, legacyWeatherPosition: legacyWeatherPosition.rawValue) }

    var body: some View {
        ForEach(Array(widgets.enumerated()), id: \.element) { index, widget in
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                    .help("Drag to reorder \(widget.title)")
                    .onDrag {
                        order = widgets; dragged = widget
                        let provider = NSItemProvider()
                        provider.registerDataRepresentation(forTypeIdentifier: UTType.notchHomeWidget.identifier, visibility: .ownProcess) { completion in
                            completion(Data(widget.rawValue.utf8), nil); return nil
                        }
                        return provider
                    }
                Toggle(isOn: visibility(widget)) {
                    Label(widget.title, systemImage: widget.symbol)
                }
                .toggleStyle(CompactSwitchToggleStyle())
                Spacer()
                Button { order = HomeLayoutPolicy.moved(widget, by: -1, in: widgets) } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(index == 0)
                .help("Move \(widget.title) earlier")
                .accessibilityLabel("Move \(widget.title) earlier")
                Button { order = HomeLayoutPolicy.moved(widget, by: 1, in: widgets) } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(index == widgets.count - 1)
                .help("Move \(widget.title) later")
                .accessibilityLabel("Move \(widget.title) later")
            }
            .buttonStyle(.borderless)
            .onDrop(of: [.notchHomeWidget], delegate: HomeTileReorderDelegate(target: widget, order: $order, dragged: $dragged))
        }
        Button("Reset Home layout") { order = []; hidden = [] }
        Text("Drag the handles to reorder tiles, or right-click Home and choose Edit Home to move the tiles directly. Switch a tile off to hide it. Showing Weather here moves it from Live. The arrows are an accessible alternative to dragging.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func visibility(_ widget: HomeWidget) -> Binding<Bool> {
        Binding(get: {
            !hidden.contains(widget) && (widget != .weather || (weatherEnabled && !weatherOnLiveTab))
                && (widget != .calendar || showCalendar)
        }, set: { enabled in
            if enabled {
                hidden.remove(widget)
                if widget == .weather { weatherEnabled = true; weatherOnLiveTab = false }
                if widget == .calendar { showCalendar = true }
            } else { hidden.insert(widget) }
        })
    }
}

struct SeasonalThemeSettings: View {
    @Default(.automaticSeasonalThemes) private var automatic
    @Default(.seasonHemisphere) private var hemisphere
    @Default(.seasonalHalloween) private var halloween
    @Default(.seasonalChristmas) private var christmas
    @Default(.seasonalEaster) private var easter
    @Default(.appTheme) private var theme

    var body: some View {
        Toggle("Automatically follow the seasons", isOn: $automatic)
        if automatic {
            Picker("Season schedule", selection: $hemisphere) {
                ForEach(SeasonHemisphere.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Include Halloween · October 15–31", isOn: $halloween)
            Toggle("Include Christmas · December 1–26", isOn: $christmas)
            Toggle("Include Easter · Palm Sunday through Easter Monday", isOn: $easter)
            LabeledContent("Current theme", value: theme.title)
        }
        Text(hemisphere == .northern
             ? "Fall: September–November. Winter: December–February. System: March–August. Holiday themes are optional. Selecting a theme yourself turns off automatic switching."
             : "Fall: March–May. Winter: June–August. System: September–February. Optional holiday themes still follow their calendar dates. Selecting a theme yourself turns off automatic switching.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

/// Architectural artwork stays on Home's content plane. Native segmented
/// controls and buttons are the only interactive layer; no video or pulse loop.
struct WhiteHouseThemeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Default(.appTheme) private var theme
    @Default(.whiteHousePreferredVariant) private var preferredVariant
    @Default(.useCustomAccentColor) private var customAccentEnabled
    @ObservedObject private var performance = AppPerformanceManager.shared

    private var variant: WhiteHouseThemeVariant { theme.whiteHouseVariant ?? preferredVariant }
    private var style: Binding<WhiteHouseStyle> {
        Binding(get: { variant.style }, set: { apply(variant.selecting(style: $0)) })
    }
    private var christmas: Binding<Bool> {
        Binding(get: { variant.isChristmas }, set: { apply(variant.selecting(christmas: $0)) })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("White House").font(.title2.weight(.semibold))
                    Text("Choose a view. Make the color yours.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Form {
                Section {
                    ZStack(alignment: .bottomLeading) {
                        HomeThemeScene(theme: theme, vaderArtwork: .lightsaber, preserveEntirePhoto: true)
                        LinearGradient(colors: [.black.opacity(0.76), .clear], startPoint: .leading, endPoint: .trailing)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(variant.scene.title).font(.title3.weight(.semibold))
                            Text(variant.style.subtitle + (variant.isChristmas ? " · Christmas" : "")).font(.caption).foregroundStyle(.white.opacity(0.85))
                        }
                        .foregroundStyle(.white).padding(16)
                    }
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityElement(children: .combine)
                    Picker("Photo & accent style", selection: style) {
                        ForEach(WhiteHouseStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Changes the photo décor and theme accent. Keeps your selected room and Christmas setting.")
                    Toggle("Christmas decorations", isOn: christmas)
                        .accessibilityHint("Adds festive trees and lights, plus snow outside. Keeps your room and color style.")
                    if customAccentEnabled {
                        Label("Your custom accent is still in use. Turn on Match theme in Appearance → Accent color to use this palette.", systemImage: "paintpalette")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("Appearance") } footer: {
                    Text("Neutral uses limestone, navy, and gold. Republican and Democrat also change the photos’ décor to red or blue. Christmas adds lights and trees to every room, plus snow outside. Your other themes stay unchanged.")
                }

                Section("Rooms & views") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(WhiteHouseScene.allCases) { scene in
                            sceneButton(scene)
                        }
                    }
                }

                Section {
                    Text("An independent architectural theme with imagined room details. Not an official White House or political-party product; no affiliation or endorsement is implied.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped).scrollContentBackground(.hidden)
        }
        .frame(width: 610, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .tint(.effectiveAccent)
        .transaction { if performance.suppressAnimations { $0.animation = nil; $0.disablesAnimations = true } }
        .onAppear { if let current = theme.whiteHouseVariant { preferredVariant = current } }
    }

    private func sceneButton(_ scene: WhiteHouseScene) -> some View {
        let selected = scene == variant.scene
        return Button { apply(variant.selecting(scene: scene)) } label: {
            VStack(alignment: .leading, spacing: 7) {
                Image(scene.backdropName(style: variant.style, christmas: variant.isChristmas))
                    .resizable().scaledToFit().aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                HStack {
                    Text(scene.title).font(.callout.weight(.medium))
                    Spacer(minLength: 4)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.effectiveAccent : .secondary)
                }
            }
            .padding(9)
            .background(Color.white.opacity(selected ? 0.08 : 0.025), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(selected ? Color.effectiveAccent : .white.opacity(0.12), lineWidth: selected ? 2 : 1) }
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(scene.title)
        .accessibilityHint("Changes the Home background. Keeps the selected accent style and Christmas setting.")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func apply(_ selection: WhiteHouseThemeVariant) {
        guard let selected = AppTheme(rawValue: selection.rawValue) else { return }
        // This never clears a custom accent, manual icon, Home layout, live
        // activity policy, or permissions. Each setting retains its own owner.
        Defaults[.automaticSeasonalThemes] = false
        preferredVariant = selection
        theme = selected
        if Defaults[.appIconFollowsTheme] {
            Defaults[.appIconVariant] = selected.matchingIcon
            selected.matchingIcon.apply()
        }
    }
}

struct StarWarsThemeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Default(.appTheme) private var theme
    @Default(.starWarsPreferredCharacter) private var preferredCharacter
    @Default(.starWarsVaderArtwork) private var vaderArtwork
    @Default(.lightsaberMusicBar) private var saberEnabled
    @Default(.lightsaberColorMode) private var colorMode
    @Default(.lightsaberCustomColorData) private var customColorData
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var performance = AppPerformanceManager.shared
    @State private var category: StarWarsThemeCategory = .jedi

    init() {
        _category = State(initialValue: Defaults[.appTheme].starWarsVariant?.category ?? .jedi)
    }

    private var variant: StarWarsThemeVariant { theme.starWarsVariant ?? .jedi }
    private var characterSceneAvailable: Bool { StarWarsArtworkAvailability.vaderSceneAvailable }
    private var bladeColor: Color { LightsaberColors.resolve(mode: colorMode, theme: theme, album: music.avgColor, customData: customColorData) }
    private var customColor: Binding<Color> {
        Binding(get: { LightsaberColors.resolve(mode: .custom, theme: theme, album: music.avgColor, customData: customColorData) }, set: { color in
            let saved = (NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)).withAlphaComponent(1)
            guard let data = try? NSKeyedArchiver.archivedData(withRootObject: saved, requiringSecureCoding: true) else { return }
            customColorData = data
            colorMode = .custom
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Star Wars").font(.title2.weight(.semibold))
                    Text("Choose your side. Make it yours.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Form {
                Section {
                    ZStack(alignment: .bottomLeading) {
                        HomeThemeScene(theme: theme, vaderArtwork: vaderArtwork, imageAlignment: .topTrailing)
                        LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(variant.title).font(.title3.weight(.semibold))
                            Text(variant.colorName + " · " + (category == .characters ? "Character palette" : "Home scene"))
                                .font(.caption).foregroundStyle(.white.opacity(0.75))
                        }.padding(16)
                    }
                    .frame(height: 120).clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityElement(children: .combine)
                    Picker("Theme style", selection: $category) {
                        ForEach(StarWarsThemeCategory.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: category) { _, selection in
                        switch selection {
                        case .jedi: apply(.jedi)
                        case .darkSide: apply(.darkSide)
                        case .characters: apply(preferredCharacter.category == .characters ? preferredCharacter : .luke)
                        }
                    }
                }

                if category == .characters {
                    Section("Choose a character") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(StarWarsThemeVariant.characters) { character in
                                Button { preferredCharacter = character; apply(character) } label: {
                                    HStack(spacing: 9) {
                                        Circle().fill(Color(nsColor: character.accentColor)).frame(width: 12, height: 12)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(character.title).font(.callout.weight(.medium))
                                            Text(character.colorName).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        if variant == character { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
                                    }
                                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.white.opacity(variant == character ? 0.09 : 0.035), in: RoundedRectangle(cornerRadius: 12))
                                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(variant == character ? Color(nsColor: character.accentColor).opacity(0.65) : .clear) }
                                    .contentShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(variant == character ? [.isSelected] : [])
                            }
                        }
                    }
                }

                if variant.supportsCharacterArtwork {
                    Section {
                        Picker("Right-side artwork", selection: $vaderArtwork) {
                            ForEach(StarWarsCharacterArtwork.allCases) { artwork in
                                Text(artwork == .character ? "Darth Vader" : artwork.title)
                                    .disabled(artwork == .character && !characterSceneAvailable)
                                    .tag(artwork)
                            }
                        }
                        .pickerStyle(.segmented)
                        .help("Choose the lightsaber or Darth Vader himself on the right side of Home.")
                    } header: { Text("Darth Vader artwork") } footer: {
                        Text("Keep the original lightsaber scenery, or show Vader inside the same volcanic scene beside the calendar. This choice is saved for Vader only and does not change the lightsaber music bar.")
                        if !characterSceneAvailable {
                            Label("Vader’s scene artwork is not available yet. The original lightsaber scene is shown.", systemImage: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Lightsaber music bar", isOn: $saberEnabled)
                    Group {
                        Picker("Blade color", selection: $colorMode) {
                            ForEach(LightsaberColorMode.allCases) { Text($0.title).tag($0) }
                        }
                        if colorMode == .custom {
                            ColorPicker("Choose any blade color", selection: customColor, supportsOpacity: false)
                        }
                        LightsaberTrack(progress: 0.64, tint: bladeColor, dragging: false, lowImpact: performance.lowImpact)
                            .frame(height: 20).padding(.vertical, 5).accessibilityLabel("Lightsaber color preview")
                    }.disabled(!saberEnabled)
                } header: { Text("Music") } footer: {
                    Text("Album cover follows the current artwork automatically. Custom color opens the macOS color picker. The blade shows playback progress and can be dragged to seek. Other themes keep the normal music bar.")
                }

                Section {
                    Text("Character presets use inspired colors and environments. Fan-made theme; not an official Star Wars product.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped).scrollContentBackground(.hidden)
        }
        .frame(width: 610, height: 650)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .tint(Color(nsColor: variant.accentColor))
        .toggleStyle(CompactSwitchToggleStyle())
        .onAppear {
            // Reopening a restored character theme must not replace it with a
            // different previously used character through the picker callback.
            if variant.category == .characters { preferredCharacter = variant }
            if !characterSceneAvailable && vaderArtwork == .character { vaderArtwork = .lightsaber }
        }
        .transaction { if performance.suppressAnimations { $0.animation = nil } }
    }

    private func apply(_ variant: StarWarsThemeVariant) {
        guard let selected = AppTheme(rawValue: variant.rawValue) else { return }
        Defaults[.automaticSeasonalThemes] = false
        theme = selected
        if Defaults[.appIconFollowsTheme] {
            Defaults[.appIconVariant] = selected.matchingIcon
            selected.matchingIcon.apply()
        }
    }
}

struct PerformanceSettingsSection: View {
    @Default(.performanceMode) private var mode
    @ObservedObject private var performance = AppPerformanceManager.shared
    var body: some View {
        Section("Performance") {
            Picker("Rendering mode", selection: $mode) {
                ForEach(AppPerformanceMode.allCases) { Text($0.title).tag($0) }
            }
            LabeledContent("Currently", value: performance.lowImpact ? "Low impact" : "Balanced")
            Text("Low impact simplifies glass, shadows and artwork effects, uses a static music indicator and refreshes media and system stats less often. Automatic enables it on battery or in macOS Low Power Mode. Reduce Motion is respected in every mode.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct QuickActionsSettings: View {
    @Default(.quickActions) private var actions
    @ObservedObject private var manager = QuickActionsManager.shared
    @State private var shortcutName = ""

    var body: some View {
        ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
            HStack(spacing: 8) {
                Label(action.name, systemImage: action.symbol).lineLimit(1)
                Spacer(minLength: 5)
                Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0).accessibilityLabel("Move \(action.name) earlier")
                Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index == actions.count - 1).accessibilityLabel("Move \(action.name) later")
                Button { actions.removeAll { $0.id == action.id } } label: { Image(systemName: "minus.circle") }
                    .accessibilityLabel("Remove \(action.name) from Quick Actions")
            }
            .buttonStyle(.borderless)
        }
        Button("Add app…", systemImage: "plus.app") { manager.addApplication() }
            .disabled(actions.count >= 6)
        HStack {
            if !manager.shortcutNames.isEmpty {
                Picker("Apple Shortcut", selection: $shortcutName) {
                    Text("Choose a shortcut").tag("")
                    ForEach(manager.shortcutNames, id: \.self) { Text($0).tag($0) }
                }
            } else {
                TextField("Exact name of an Apple Shortcut", text: $shortcutName)
            }
            Button("Add") { manager.addShortcut(shortcutName); shortcutName = "" }
                .disabled(shortcutName.isEmpty || actions.count >= 6)
        }
        HStack {
            Button("Refresh shortcut list") { Task { await manager.loadShortcuts() } }
                .disabled(manager.isLoading)
            if manager.isLoading { ProgressView().controlSize(.small) }
        }
        if let error = manager.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
        Text("Add up to six apps or Apple Shortcuts. They appear in the Quick Actions Home tile, which can be moved or hidden above. Shortcuts only run when you click them, and may request their own permissions.")
            .font(.caption).foregroundStyle(.secondary)
        .task { await manager.loadShortcuts() }
    }

    private func move(_ index: Int, by delta: Int) {
        guard actions.indices.contains(index + delta) else { return }
        actions.swapAt(index, index + delta)
    }
}

struct QuickActionsHomeTile: View {
    @Default(.quickActions) private var actions
    @ObservedObject private var manager = QuickActionsManager.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Quick Actions", systemImage: "bolt.fill").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(actions.prefix(6)) { action in
                    Button { manager.run(action) } label: {
                        VStack(spacing: 3) {
                            if manager.runningIDs.contains(action.id) {
                                ProgressView().controlSize(.small).frame(height: 18)
                            } else if let icon = manager.icon(for: action) {
                                Image(nsImage: icon).resizable().scaledToFit().frame(width: 18, height: 18)
                            } else {
                                Image(systemName: action.symbol).frame(height: 18)
                            }
                            Text(action.name).font(.system(size: 9, weight: .medium)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .liquidGlassCapsule()
                    .disabled(manager.runningIDs.contains(action.id))
                    .help("Run \(action.name)")
                    .accessibilityLabel("Run \(action.name)")
                }
            }
            if let error = manager.errorMessage {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 132, height: 130, alignment: .topLeading)
    }
}

struct AgentHistoryRows: View {
    let entries: [AgentHistoryEntry]
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    Image(systemName: entry.state.symbol)
                        .foregroundStyle(entry.state == .completed ? Color.green : entry.state == .usageLimited ? .red : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).font(.caption.weight(.semibold)).lineLimit(1)
                        Text("\(entry.provider) · \(entry.state.label)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(entry.endedAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct AgentHistorySettings: View {
    @Default(.agentHistoryEnabled) private var enabled
    @ObservedObject private var agents = AgentStatusManager.shared
    @State private var confirmClear = false
    var body: some View {
        Section("Recent AI activity") {
            Toggle("Keep local AI activity history", isOn: $enabled)
            if agents.history.isEmpty {
                Text(enabled ? "Finished tasks will appear here." : "History is off.").foregroundStyle(.secondary)
            } else {
                ScrollView { AgentHistoryRows(entries: agents.history) }.frame(maxHeight: 180)
                Button("Clear history", role: .destructive) { confirmClear = true }
                    .confirmationDialog("Clear the local AI activity history?", isPresented: $confirmClear) {
                        Button("Clear history", role: .destructive) { agents.clearHistory() }
                    }
            }
            Text("Keeps the latest 50 outcomes on this Mac: provider, project name, times and status. No prompts, replies or full folder paths are saved. Turning this off stops new recording; use Clear history to erase existing entries.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
