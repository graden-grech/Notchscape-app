import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

private func appearanceHex(_ color: NSColor) -> String? {
    guard let color = color.usingColorSpace(.sRGB) else { return nil }
    let components = [color.redComponent, color.greenComponent, color.blueComponent]
    guard components.allSatisfy(\.isFinite) else { return nil }
    let values = components.map { Int((min(1, max(0, $0)) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", values[0], values[1], values[2])
}

@MainActor
final class AppearanceRecipes: ObservableObject {
    static let shared = AppearanceRecipes()
    @Published private(set) var saved: [AppearanceRecipe] = []
    @Published private(set) var undo: AppearanceRecipeUndo?
    @Published var pending: AppearanceRecipe?
    @Published var message: String?
    private var themes: Set<String> { Set(AppTheme.allCases.map(\.rawValue)) }
    private var icons: Set<String> { Set(AppIconVariant.allCases.map(\.rawValue)) }
    private init() {
        if let data = UserDefaults.standard.data(forKey: "appearance.recipes") {
            saved = AppearanceRecipe.decodeSaved(data, themes: themes, icons: icons)
        }
    }
    func current(name: String) -> AppearanceRecipe {
        let hex = appearanceHex(.resolvedAccent(theme: Defaults[.appTheme], customEnabled: Defaults[.useCustomAccentColor], customData: Defaults[.customAccentColorData]))
        return .init(name: name, theme: Defaults[.appTheme].rawValue, accentHex: Defaults[.useCustomAccentColor] ? hex : nil,
            icon: Defaults[.appIconVariant].rawValue, followsThemeIcon: Defaults[.appIconFollowsTheme],
            homeOrder: HomeLayoutPolicy.normalized(Defaults[.homeWidgetOrder], legacyWeatherPosition: Defaults[.weatherTilePosition].rawValue).map(\.rawValue),
            hiddenWidgets: Defaults[.hiddenHomeWidgets].map(\.rawValue).sorted(), showsThemeDetails: Defaults[.themeDetailsEnabled])
    }
    func save(_ value: AppearanceRecipe) {
        guard WorkspaceAccess.privateToolsAllowed, value.valid(themes: themes, icons: icons), saved.count < AppearanceRecipe.maximumSaved else { return }
        var value = value; value.id = UUID(); value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.append(value); persist(); message = "Saved \(value.name). Your current appearance was not changed."
    }
    func remove(_ id: UUID) { guard WorkspaceAccess.privateToolsAllowed else { return }; saved.removeAll { $0.id == id }; persist() }
    private func persist() { if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: "appearance.recipes") } }
    func apply(_ value: AppearanceRecipe) {
        guard WorkspaceAccess.privateToolsAllowed, value.valid(themes: themes, icons: icons), let theme = AppTheme(rawValue: value.theme), let icon = AppIconVariant(rawValue: value.icon) else { return }
        undo = .init(recipe: current(name: "Before appearance preset"), automaticSeasonal: Defaults[.automaticSeasonalThemes],
                     customAccentEnabled: Defaults[.useCustomAccentColor], customAccentData: Defaults[.customAccentColorData])
        write(value, theme: theme, icon: icon)
        pending = nil; message = "Applied \(value.name). Permissions, accounts, recording, and display settings were not changed."
    }
    private func write(_ value: AppearanceRecipe, theme: AppTheme, icon: AppIconVariant) {
        Defaults[.automaticSeasonalThemes] = false
        Defaults[.appTheme] = theme; Defaults[.appIconFollowsTheme] = value.followsThemeIcon
        if let variant = theme.whiteHouseVariant { Defaults[.whiteHousePreferredVariant] = variant }
        Defaults[.appIconVariant] = value.followsThemeIcon ? theme.matchingIcon : icon
        Defaults[.appIconVariant].apply()
        if let hex = value.accentHex, let (r,g,b) = AppearanceRecipe.rgb(hex),
           let data = try? NSKeyedArchiver.archivedData(withRootObject: NSColor(srgbRed: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, alpha: 1), requiringSecureCoding: true) {
            Defaults[.customAccentColorData] = data; Defaults[.useCustomAccentColor] = true
        } else { Defaults[.useCustomAccentColor] = false }
        Defaults[.homeWidgetOrder] = HomeLayoutPolicy.normalized(value.homeOrder.compactMap(HomeWidget.init(rawValue:)), legacyWeatherPosition: "end")
        Defaults[.hiddenHomeWidgets] = Set(value.hiddenWidgets.compactMap(HomeWidget.init(rawValue:)))
        Defaults[.themeDetailsEnabled] = value.showsThemeDetails
    }
    func restore() {
        guard WorkspaceAccess.privateToolsAllowed, let snapshot = undo,
              let theme = AppTheme(rawValue: snapshot.recipe.theme), let icon = AppIconVariant(rawValue: snapshot.recipe.icon) else { return }
        write(snapshot.recipe, theme: theme, icon: icon)
        Defaults[.appIconVariant] = icon
        icon.apply()
        Defaults[.customAccentColorData] = snapshot.customAccentData
        Defaults[.useCustomAccentColor] = snapshot.customAccentEnabled
        // Set last, after appearance values: the scheduler can resume its normal
        // behavior if it was previously enabled. It is never exported/imported.
        Defaults[.automaticSeasonalThemes] = snapshot.automaticSeasonal
        undo = nil; pending = nil; message = "Restored your previous appearance and seasonal-switching preference."
    }
    func importFile() {
        guard WorkspaceAccess.privateToolsAllowed else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        panel.begin { [weak self] result in
            Task { @MainActor in
                guard let self, WorkspaceAccess.privateToolsAllowed, result == .OK, let url = panel.url else { return }
                do {
                    let data = try await Task.detached(priority: .userInitiated) {
                        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                        guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= AppearanceRecipe.maximumBytes else { throw CocoaError(.fileReadTooLarge) }
                        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
                        return try file.read(upToCount: AppearanceRecipe.maximumBytes + 1) ?? Data()
                    }.value
                    guard WorkspaceAccess.privateToolsAllowed else { return }
                    self.pending = try AppearanceRecipe.decode(data, themes: self.themes, icons: self.icons)
                } catch { self.message = "This preset is unsupported or invalid. Nothing was changed." }
            }
        }
    }
    func export(_ value: AppearanceRecipe) {
        guard WorkspaceAccess.privateToolsAllowed, value.valid(themes: themes, icons: icons) else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Notchscape-Appearance.json"
        panel.begin { [weak self] result in
            guard WorkspaceAccess.privateToolsAllowed, result == .OK, let url = panel.url else { return }
            do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(value).write(to: url, options: .atomic) }
            catch { self?.message = "The preset couldn’t be exported." }
        }
    }
}

struct AppearanceRecipesView: View {
    @ObservedObject private var recipes = AppearanceRecipes.shared
    @Default(.appTheme) private var theme
    @State private var editorPresented = false
    @State private var delete: AppearanceRecipe?
    var body: some View {
        Section {
            LabeledContent("Current theme", value: theme.title)
            HStack {
                Button("Create Appearance…") { editorPresented = true }.disabled(recipes.saved.count >= AppearanceRecipe.maximumSaved)
                Button("Import…") { recipes.importFile() }
                Spacer(minLength: 8)
                Button("Export Current…") { recipes.export(recipes.current(name: "My Appearance")) }
            }
            ForEach(recipes.saved) { value in
                HStack(spacing: 10) {
                    Image(systemName: AppTheme(rawValue: value.theme)?.symbol ?? "paintpalette")
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(value.name).lineLimit(1)
                        Text(AppTheme(rawValue: value.theme)?.title ?? value.theme).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Preview…") { recipes.pending = value }
                    Menu {
                        Button("Export…") { recipes.export(value) }
                        Button("Remove…", role: .destructive) { delete = value }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("More actions for \(value.name)")
                }
            }
            if recipes.undo != nil { Button("Undo Last Appearance") { recipes.restore() } }
            if let message = recipes.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        } header: { Text("Saved Appearances") } footer: {
            Text("Save up to 20 appearances with a theme, accent, icon choice, and Home layout. Imports are previewed before applying. No private content, accounts, permissions, or display settings are shared. Applying pauses seasonal switching; Undo restores its previous setting.")
        }
        .sheet(isPresented: $editorPresented) { AppearanceRecipeEditor() }
        .sheet(item: $recipes.pending) { value in
            AppearanceRecipePreview(value: value)
        }
        .confirmationDialog("Remove saved appearance?", isPresented: Binding(get: { delete != nil }, set: { if !$0 { delete = nil } })) {
            Button("Remove", role: .destructive) { if let delete { recipes.remove(delete.id) }; delete = nil }
        } message: { Text("Your current appearance will not change. An exported file is not removed.") }
    }
}

private struct AppearanceRecipeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var recipes = AppearanceRecipes.shared
    @State private var name = "My Appearance"
    @State private var base = Defaults[.appTheme]
    @State private var lastWhiteHouseVariant = Defaults[.whiteHousePreferredVariant]
    @State private var custom = Defaults[.useCustomAccentColor]
    @State private var accent = Color(nsColor: .effectiveAccent)
    @State private var followsIcon = Defaults[.appIconFollowsTheme]
    @State private var icon = Defaults[.appIconVariant]
    @State private var details = Defaults[.themeDetailsEnabled]
    @State private var order = HomeLayoutPolicy.normalized(Defaults[.homeWidgetOrder], legacyWeatherPosition: Defaults[.weatherTilePosition].rawValue)
    @State private var hidden = Defaults[.hiddenHomeWidgets]
    private var tint: Color { custom ? accent : Color(nsColor: base.accentColor ?? .controlAccentColor) }
    private var themeSelection: Binding<AppTheme> {
        Binding(get: { base.isWhiteHouse ? .whiteHouse : base }, set: { selected in
            if let variant = base.whiteHouseVariant { lastWhiteHouseVariant = variant }
            base = selected.isWhiteHouse ? AppTheme(rawValue: lastWhiteHouseVariant.rawValue) ?? .whiteHouse : selected
        })
    }
    private var whiteHouseStyle: Binding<WhiteHouseStyle> {
        Binding(get: { base.whiteHouseVariant?.style ?? .neutral }, set: { style in
            let variant = (base.whiteHouseVariant ?? lastWhiteHouseVariant).selecting(style: style)
            base = AppTheme(rawValue: variant.rawValue) ?? .whiteHouse
        })
    }
    private var whiteHouseScene: Binding<WhiteHouseScene> {
        Binding(get: { base.whiteHouseVariant?.scene ?? .exterior }, set: { scene in
            let variant = (base.whiteHouseVariant ?? lastWhiteHouseVariant).selecting(scene: scene)
            base = AppTheme(rawValue: variant.rawValue) ?? .whiteHouse
        })
    }
    private var whiteHouseChristmas: Binding<Bool> {
        Binding(get: { base.whiteHouseVariant?.isChristmas ?? false }, set: { christmas in
            let variant = (base.whiteHouseVariant ?? lastWhiteHouseVariant).selecting(christmas: christmas)
            base = AppTheme(rawValue: variant.rawValue) ?? .whiteHouse
        })
    }
    private var draft: AppearanceRecipe {
        let hex = appearanceHex(NSColor(accent))
        return .init(name: name, theme: base.rawValue, accentHex: custom ? hex : nil,
                     icon: followsIcon ? base.matchingIcon.rawValue : icon.rawValue, followsThemeIcon: followsIcon,
                     homeOrder: order.map(\.rawValue), hiddenWidgets: hidden.map(\.rawValue).sorted(), showsThemeDetails: details)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Create Appearance").font(.title2.weight(.semibold)); Spacer() }.padding(20)
            Form {
                Section {
                    TextField("Name", text: $name).onChange(of: name) { _, value in
                        if value.count > 80 { name = String(value.prefix(80)) }
                    }
                    AppearanceRecipeSample(value: draft)
                }
                Section("Style") {
                    Picker("Theme", selection: themeSelection) {
                        ForEach(AppTheme.allCases.filter { !$0.isWhiteHouse || $0 == .whiteHouse }) {
                            Text($0.isWhiteHouse ? "White House" : $0.title).tag($0)
                        }
                    }
                    if base.isWhiteHouse {
                        Picker("White House accent style", selection: whiteHouseStyle) {
                            ForEach(WhiteHouseStyle.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("White House room or view", selection: whiteHouseScene) {
                            ForEach(WhiteHouseScene.allCases) { Text($0.title).tag($0) }
                        }
                        Toggle("White House Christmas decorations", isOn: whiteHouseChristmas)
                    }
                    Toggle("Use a custom accent", isOn: $custom)
                    if custom { ColorPicker("Accent color", selection: $accent, supportsOpacity: false) }
                    Toggle("Let the theme choose the app icon", isOn: $followsIcon)
                    if !followsIcon {
                        Picker("App icon", selection: $icon) { ForEach(AppIconVariant.allCases) { Text($0.title).tag($0) } }
                    }
                    Toggle("Quiet scene detail", isOn: $details)
                }
                Section {
                    ForEach(Array(order.enumerated()), id: \.element) { index, widget in
                        HStack(spacing: 10) {
                            Label(widget.title, systemImage: widget.symbol)
                            Spacer()
                            Button { order = HomeLayoutPolicy.moved(widget, by: -1, in: order) } label: { Image(systemName: "chevron.up") }
                                .disabled(index == 0).accessibilityLabel("Move \(widget.title) earlier")
                            Button { order = HomeLayoutPolicy.moved(widget, by: 1, in: order) } label: { Image(systemName: "chevron.down") }
                                .disabled(index == order.count - 1).accessibilityLabel("Move \(widget.title) later")
                            Toggle("Show \(widget.title)", isOn: Binding(get: { !hidden.contains(widget) }, set: { visible in
                                if visible { hidden.remove(widget) } else { hidden.insert(widget) }
                            })).labelsHidden().accessibilityLabel("Show \(widget.title)")
                        }.buttonStyle(.borderless)
                    }
                } header: { Text("Home Tiles") } footer: {
                    Text("Reorder with the arrows and choose visible tiles. Applying this appearance never enables Calendar or Weather if their feature switches are off.")
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Text("Saves locally; does not apply yet.").font(.caption).foregroundStyle(.secondary)
                Button("Save Appearance") { recipes.save(draft); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!draft.valid(themes: Set(AppTheme.allCases.map(\.rawValue)), icons: Set(AppIconVariant.allCases.map(\.rawValue))) || recipes.saved.count >= AppearanceRecipe.maximumSaved)
            }.padding(20)
        }.frame(width: 620, height: 650).tint(tint)
            .toggleStyle(CompactSwitchToggleStyle()).controlSize(.small)
            .background(LiquidGlassSettingsBackground())
    }
}

private struct AppearanceRecipePreview: View {
    let value: AppearanceRecipe
    @ObservedObject private var recipes = AppearanceRecipes.shared
    private var theme: AppTheme { AppTheme(rawValue: value.theme) ?? .system }
    private var widgetNames: [String] { HomeLayoutPolicy.normalized(value.homeOrder.compactMap(HomeWidget.init(rawValue:)), legacyWeatherPosition: "end").map(\.title) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preview Appearance").font(.title2.weight(.semibold))
            Text(value.name).font(.headline)
            AppearanceRecipeSample(value: value)
            LabeledContent("Theme", value: theme.title)
            LabeledContent("Accent", value: value.accentHex ?? "Theme default")
            LabeledContent("App icon", value: value.followsThemeIcon ? "Follow theme" : AppIconVariant(rawValue: value.icon)?.title ?? value.icon)
            LabeledContent("Scene detail", value: value.showsThemeDetails ? "On" : "Off")
            Text("Home order: \(widgetNames.joined(separator: ", "))").font(.callout)
            Text("Hidden tiles: \(value.hiddenWidgets.isEmpty ? "None" : value.hiddenWidgets.compactMap(HomeWidget.init(rawValue:)).map(\.title).joined(separator: ", "))").font(.callout)
            Text("Applying turns off automatic seasonal switching. Calendar and Weather stay disabled if their feature switches are off. Permissions, accounts, private content, and display choices are unchanged.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { recipes.pending = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply Appearance") { recipes.apply(value) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 500).controlSize(.small)
            .background(LiquidGlassSettingsBackground())
    }
}

private struct AppearanceRecipeSample: View {
    let value: AppearanceRecipe
    private var theme: AppTheme { AppTheme(rawValue: value.theme) ?? .system }
    private var color: Color {
        if let hex = value.accentHex, let (r, g, b) = AppearanceRecipe.rgb(hex) { return Color(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255) }
        return Color(nsColor: theme.accentColor ?? .controlAccentColor)
    }
    var body: some View {
        ZStack(alignment: .leading) {
            Color.black
            HomeThemeScene(theme: theme, vaderArtwork: .lightsaber, detailsOverride: value.showsThemeDetails,
                           preserveEntirePhoto: true)
            LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
            HStack(spacing: 12) {
                ForEach(HomeLayoutPolicy.normalized(value.homeOrder.compactMap(HomeWidget.init(rawValue:)), legacyWeatherPosition: "end").filter { !value.hiddenWidgets.contains($0.rawValue) }) { widget in
                    Label(widget.title, systemImage: widget.symbol).font(.caption.weight(.medium))
                        .padding(9).background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                }
            }.foregroundStyle(.white).padding(12)
        }.aspectRatio(theme.isWhiteHouse ? 16.0 / 9.0 : 3.0, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topTrailing) { Circle().fill(color).frame(width: 12, height: 12).padding(10) }
            .accessibilityElement(children: .ignore).accessibilityLabel("Preview of \(theme.title), with chosen Home tile order and accent")
    }
}
