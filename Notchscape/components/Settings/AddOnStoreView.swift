import Defaults
import SwiftUI

/// A native catalog for the features in this preview and the add-ons planned
/// next. Catalog navigation never enables a feature or starts a download.
struct AddOnStoreView: View {
    @State private var category = AddOnCategory.features
    @State private var search = ""
    @State private var selectedItem: AddOnCatalogueItem?
    var openSettings: (String) -> Void = { SettingsWindowController.shared.showWindow(section: $0) }

    private var items: [AddOnCatalogueItem] {
        AddOnCatalog.items(in: category, matching: search)
            .filter { $0.id != "face" || FaceUnlockManager.featureEnabled }
    }
    private var featured: AddOnCatalogueItem? {
        guard category == .features, search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return items.first { $0.id == "dock" }
    }
    private var gridItems: [AddOnCatalogueItem] { items.filter { $0.id != featured?.id } }

    var body: some View {
        catalogContent
        .navigationTitle("Add-ons")
        .sheet(item: $selectedItem) { item in
            AddOnDetailSheet(item: item, openSettings: openSettings)
        }
    }

    private var catalogContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                browseControls
                if let featured { featuredCard(featured) }
                availabilityNote
                if items.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 218, maximum: 360), spacing: 14)], alignment: .leading, spacing: 14) {
                        ForEach(gridItems) { card($0) }
                    }
                }
                footer
            }
            .padding(24)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Make room for what you love.").font(.title.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text("Choose the features and collections that feel at home on your Mac.")
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var browseControls: some View {
        VStack(spacing: 12) {
            Picker("Browse add-ons", selection: $category) {
                ForEach(AddOnCategory.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Browse add-ons")
            .controlSize(.regular)
            .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search add-ons", text: $search)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search add-ons")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear add-on search")
                }
            }
            .onChange(of: search) { _, value in if value.count > 256 { search = String(value.prefix(256)) } }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5) }
        }
    }

    private func featuredCard(_ item: AddOnCatalogueItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                AddOnArtwork(item: item, large: true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("NEW IN THIS PREVIEW").font(.caption2.weight(.semibold)).tracking(0.7).foregroundStyle(Color.accentColor)
                    Text("Your own little workspace.").font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.description).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { featurePills }
                VStack(alignment: .leading, spacing: 7) { featurePills }
            }
            NotchGlassControlGroup {
                HStack(spacing: 10) {
                    if let destination = item.settingsID {
                        Button("Set Up Dock…") { openSettings(destination) }
                            .notchGlassButton(prominent: true)
                    }
                    Button("See Details") { selectedItem = item }
                        .notchGlassButton()
                }
            }
            Text("Optional and off by default. Your macOS Dock stays as it is.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.accentColor.opacity(0.16), lineWidth: 0.5) }
    }

    @ViewBuilder private var featurePills: some View {
        Label("Pinned apps", systemImage: "app.badge").font(.caption)
        Label("Favorite folders", systemImage: "folder").font(.caption)
        Label("Widget cards", systemImage: "rectangle.grid.1x2").font(.caption)
    }

    private var availabilityNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(category == .installed
                 ? "Included features are shown below. No separately downloaded add-on packs are installed in this preview."
                 : "Features marked Included are already in this app preview. Separate downloads are still being prepared.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("No matching add-ons").font(.headline)
            Text("Try a feature name or a different category.").font(.callout).foregroundStyle(.secondary)
            Button("Clear Search") { search = "" }.notchGlassButton()
        }.frame(maxWidth: .infinity).padding(.vertical, 32)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your choices stay yours.").font(.callout.weight(.semibold))
            Text("Browsing never turns a feature on or requests access. Included features remain in the app when disabled. Future downloads will show their size, requirements and removal options before you install them.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func card(_ item: AddOnCatalogueItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                AddOnArtwork(item: item)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    AddOnStatus(item: item)
                }
                Spacer(minLength: 0)
            }
            Text(item.description).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            NotchGlassControlGroup {
                HStack(spacing: 8) {
                    Button("Details") { selectedItem = item }
                        .notchGlassButton()
                        .accessibilityLabel("Details for \(item.title)")
                    Spacer(minLength: 0)
                    if let destination = item.settingsID {
                        Button("Settings…") { openSettings(destination) }
                            .notchGlassButton()
                            .accessibilityLabel("Open \(item.title) settings")
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 182, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5) }
    }
}

private struct AddOnDetailSheet: View {
    let item: AddOnCatalogueItem
    let openSettings: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var snow = DesktopSnowManager.shared
    @Default(.desktopSnowEnabled) private var snowEnabled

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                AddOnArtwork(item: item, large: true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.title2.bold())
                    AddOnStatus(item: item)
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
                    .notchGlassButton(circular: true)
                    .frame(width: 30, height: 30)
                    .accessibilityLabel("Close add-on details")
                    .keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(item.description).font(.body).fixedSize(horizontal: false, vertical: true)
                    if item.id == "desktop-snow" { snowControls }
                    detailSection(item.availability == .notPublished ? "What’s planned" : "What’s included", symbol: "checklist") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(item.details.highlights, id: \.self) { highlight in
                                HStack(alignment: .firstTextBaseline, spacing: 9) {
                                    Image(systemName: "checkmark").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                                    Text(highlight).font(.callout).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    detailSection("Availability", symbol: "shippingbox") {
                        Text(item.availabilityExplanation).font(.callout).foregroundStyle(.secondary)
                        Text(item.plan).font(.callout).foregroundStyle(.secondary)
                    }
                    detailSection("Before you use it", symbol: "slider.horizontal.3") {
                        Text(item.details.requirements).font(.callout).foregroundStyle(.secondary)
                    }
                    detailSection("Privacy & control", symbol: "hand.raised") {
                        Text(item.details.privacy).font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack(spacing: 10) {
                if item.settingsID == nil {
                    Label("Download not available yet", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                NotchGlassControlGroup {
                    HStack(spacing: 10) {
                        Button("Done") { dismiss() }.notchGlassButton()
                        if let destination = item.settingsID {
                            Button("Open Settings…") {
                                dismiss()
                                openSettings(destination)
                            }
                            .notchGlassButton(prominent: true)
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                }
            }.padding(20)
        }
        .frame(minWidth: 460, idealWidth: 520, maxWidth: 640,
               minHeight: 400, idealHeight: 560, maxHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.title) details")
    }

    private var snowControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $snowEnabled) {
                Label("Enable Desktop Snow", systemImage: "snowflake")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityHint("Turns optional desktop snowfall on or off. Browsing this page does not enable it.")
            Text(snowEnabled ? snow.statusText : "Off. Turn it on when you want a little snow.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Free and included with this preview. Turn it off at any time; no download is needed.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detailSection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            content().fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AddOnStatus: View {
    let item: AddOnCatalogueItem
    private var symbol: String {
        switch item.availability {
        case .includedPreview: "checkmark.circle"
        case .notPublished: "clock"
        case .localPreviewOnly: "macbook"
        }
    }
    var body: some View {
        Label(item.status, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(item.availability == .localPreviewOnly ? Color.orange : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AddOnArtwork: View {
    let item: AddOnCatalogueItem
    var large = false
    var body: some View {
        Image(systemName: item.symbol)
            .font(.system(size: large ? 27 : 21, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: large ? 60 : 44, height: large ? 60 : 44)
            .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: large ? 16 : 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

