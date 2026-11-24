import SwiftUI

/// Native, locally persisted desktop scenery. Layouts are scoped to the theme ID
/// supplied by the caller and kept deliberately small and bounded.
struct DesktopSnowSceneryEditor: View {
    let theme: String

    @AppStorage("desktopSnowSceneryEnabled") private var sceneryEnabled = false
    @AppStorage("desktopSnowSceneryPetEnabled") private var petEnabled = false
    @AppStorage("desktopSnowSceneryLayouts") private var layoutsData = Data()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var dragPreview: (id: UUID, x: Double)?

    private var items: [DesktopSnowSceneryItem] { layouts[theme] ?? DesktopSnowSceneryItem.defaults(for: theme) }
    private var selected: DesktopSnowSceneryItem? { items.first { $0.id == selectedID } }
    private var layouts: [String: [DesktopSnowSceneryItem]] {
        (try? JSONDecoder().decode([String: [DesktopSnowSceneryItem]].self, from: layoutsData)) ?? [:]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Snowy Desktop Scenery", systemImage: "mountain.2.fill").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Toggle("Show desktop scenery", isOn: $sceneryEnabled)
            Text("Arrange objects along the bottom of the screen. Each season saves its own layout.")
                .font(.callout).foregroundStyle(.secondary)
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [.init(red: 0.11, green: 0.19, blue: 0.32), .init(red: 0.32, green: 0.47, blue: 0.59)], startPoint: .top, endPoint: .bottom))
                Circle().fill(.white.opacity(0.7)).frame(width: 48, height: 48).blur(radius: 1).offset(x: 300, y: -55)
                ForEach(0..<14, id: \.self) { index in
                    Circle().fill(.white.opacity(0.8)).frame(width: index.isMultiple(of: 3) ? 3 : 2).offset(x: CGFloat((index * 67) % 390), y: -CGFloat((index * 29) % 75))
                }
                Rectangle().fill(LinearGradient(colors: [.white, Color(red: 0.79, green: 0.9, blue: 0.96)], startPoint: .top, endPoint: .bottom)).frame(height: 25)
                    .overlay(alignment: .top) { Capsule().fill(.white).frame(height: 5).padding(.horizontal, 10) }
                ForEach(items) { item in
                    DesktopSnowSceneryGlyph(kind: item.kind, flipped: item.flipped)
                        .frame(width: item.kind == .cabin ? 58 : 40, height: 64)
                        .position(x: 12 + position(of: item) * 390, y: 106)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 3)
                            .onChanged { value in
                                selectedID = item.id
                                dragPreview = (item.id, dragPosition(of: item, translation: value.translation.width))
                            }
                            .onEnded { value in
                                update(item.id) { $0.x = dragPosition(of: item, translation: value.translation.width) }
                                dragPreview = nil
                            })
                        .onTapGesture { selectedID = item.id }
                        .overlay { if selectedID == item.id { RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [3])).padding(-3) } }
                        .accessibilityElement().accessibilityLabel("\(item.kind.title), position \(Int(item.x * 100)) percent").accessibilityAddTraits(.isButton)
                        .accessibilityAction { selectedID = item.id }
                }
                if petEnabled {
                    Image(systemName: "hare.fill").foregroundStyle(.white).offset(x: 24, y: -21)
                }
            }
            .frame(height: 132).clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.24)))
            HStack(spacing: 8) {
                ForEach(DesktopSnowSceneryKind.allCases) { kind in
                    Button { add(kind) } label: { Label(kind.title, systemImage: kind.symbol).labelStyle(.titleAndIcon).font(.caption) }.buttonStyle(.bordered)
                        .disabled(items.count >= 12).accessibilityLabel("Add \(kind.title)")
                }
                Spacer(minLength: 0)
                Button("Reset", systemImage: "arrow.counterclockwise") { save(DesktopSnowSceneryItem.defaults(for: theme)); selectedID = nil }.buttonStyle(.bordered)
            }
            if let item = selected {
                HStack(spacing: 12) {
                    Text(item.kind.title).font(.subheadline.weight(.medium)).frame(width: 72, alignment: .leading)
                    Slider(value: Binding(get: { item.x }, set: { value in update(item.id) { $0.x = value } }), in: 0.04...0.96).accessibilityLabel("Scenery item horizontal position")
                    Button("Flip", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") { update(item.id) { $0.flipped.toggle() } }.buttonStyle(.bordered).accessibilityLabel("Flip selected item")
                    Button(role: .destructive) { save(items.filter { $0.id != item.id }); selectedID = nil } label: { Label("Remove", systemImage: "trash") }.buttonStyle(.bordered).accessibilityLabel("Remove selected item")
                }
            } else {
                Text("Select an item to adjust its position, flip it, or remove it.").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Add a small wandering pet", isOn: $petEnabled)
                .font(.callout)
            Text("The pet is opt-in. In low-impact mode it stays still.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 456)
        .onAppear { if selectedID == nil { selectedID = items.first?.id } }
    }

    private func add(_ kind: DesktopSnowSceneryKind) {
        guard items.count < 12 else { return }
        var next = items
        let item = DesktopSnowSceneryItem(kind: kind, x: [0.22, 0.5, 0.78][next.count % 3])
        next.append(item); save(next); selectedID = item.id
    }
    private func update(_ id: UUID, change: (inout DesktopSnowSceneryItem) -> Void) {
        var next = items
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        change(&next[index]); save(next)
    }
    private func save(_ value: [DesktopSnowSceneryItem]) {
        var all = layouts
        all[theme] = Array(value.prefix(12))
        if all.count > 6, let other = all.keys.first(where: { $0 != theme }) { all.removeValue(forKey: other) }
        layoutsData = (try? JSONEncoder().encode(all)) ?? Data()
    }

    private func position(of item: DesktopSnowSceneryItem) -> Double {
        dragPreview?.id == item.id ? (dragPreview?.x ?? item.x) : item.x
    }

    private func dragPosition(of item: DesktopSnowSceneryItem, translation: CGFloat) -> Double {
        min(0.96, max(0.04, item.x + translation / 390))
    }
}

/// Click-through overlay for a bounded desktop bottom strip. Use the same
/// theme ID as the editor; the host controls whether this view is installed.
struct DesktopSnowSceneLayer: View {
    let theme: String
    var lowImpact: Bool = false
    @AppStorage("desktopSnowSceneryEnabled") private var sceneryEnabled = false
    @AppStorage("desktopSnowSceneryPetEnabled") private var petEnabled = false
    @AppStorage("desktopSnowSceneryLayouts") private var layoutsData = Data()

    private var items: [DesktopSnowSceneryItem] {
        let all = (try? JSONDecoder().decode([String: [DesktopSnowSceneryItem]].self, from: layoutsData)) ?? [:]
        return Array((all[theme] ?? DesktopSnowSceneryItem.defaults(for: theme)).prefix(12))
    }
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                if sceneryEnabled {
                    ForEach(items) { item in
                        DesktopSnowSceneryGlyph(kind: item.kind, flipped: item.flipped)
                            .frame(width: item.kind == .cabin ? 58 : 40, height: min(proxy.size.height, 64), alignment: .bottom)
                            .position(x: 12 + item.x * max(0, proxy.size.width - 24), y: proxy.size.height - min(proxy.size.height, 64) / 2 - 2)
                    }
                }
                if petEnabled {
                    if lowImpact {
                        pet(x: 26)
                    } else {
                        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                            let pace = (1 + sin(timeline.date.timeIntervalSinceReferenceDate / 5)) / 2
                            pet(x: 26 + pace * min(190, max(0, proxy.size.width - 52)))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .transaction { $0.animation = nil }
    }

    private func pet(x: CGFloat) -> some View {
        Image(systemName: "hare.fill")
            .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 2)
            .offset(x: x, y: -5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

private enum DesktopSnowSceneryKind: String, Codable, CaseIterable, Identifiable {
    case tree, cabin, snowman, lantern
    var id: Self { self }
    var title: String { switch self { case .tree: "Tree"; case .cabin: "Cabin"; case .snowman: "Snowman"; case .lantern: "Lantern" } }
    var symbol: String { switch self { case .tree: "tree.fill"; case .cabin: "house.fill"; case .snowman: "snowman.fill"; case .lantern: "lamp.table.fill" } }
}

private struct DesktopSnowSceneryItem: Codable, Identifiable {
    private static let winter = [Self(kind: .tree, x: 0.17), Self(kind: .cabin, x: 0.49), Self(kind: .snowman, x: 0.78)]
    private static let holiday = [Self(kind: .lantern, x: 0.15), Self(kind: .tree, x: 0.3), Self(kind: .cabin, x: 0.68)]
    private static let woodland = [Self(kind: .tree, x: 0.15), Self(kind: .tree, x: 0.76), Self(kind: .lantern, x: 0.8)]

    static func defaults(for theme: String) -> [Self] {
        switch theme {
        case "winterDawn": winter
        case "holidayNight": holiday
        default: woodland
        }
    }

    var id = UUID()
    var kind: DesktopSnowSceneryKind
    var x: Double
    var flipped = false
    init(kind: DesktopSnowSceneryKind, x: Double, flipped: Bool = false) { self.kind = kind; self.x = min(1, max(0, x)); self.flipped = flipped }
}

private struct DesktopSnowSceneryGlyph: View {
    let kind: DesktopSnowSceneryKind
    let flipped: Bool
    var body: some View {
        ZStack(alignment: .bottom) {
            switch kind {
            case .tree:
                VStack(spacing: -4) {
                    treeTier(width: 15, height: 17, color: Color(red: 0.2, green: 0.58, blue: 0.42))
                    treeTier(width: 25, height: 20, color: Color(red: 0.13, green: 0.46, blue: 0.34))
                    treeTier(width: 36, height: 25, color: Color(red: 0.1, green: 0.36, blue: 0.29))
                }.overlay(alignment: .top) { Image(systemName: "sparkle").font(.system(size: 9, weight: .bold)).foregroundStyle(.yellow).offset(y: -3) }
            case .cabin:
                VStack(spacing: -1) {
                    UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 2).fill(Color(red: 0.55, green: 0.3, blue: 0.23)).frame(width: 54, height: 30)
                        .overlay(alignment: .bottom) { HStack(spacing: 9) { window; RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.26, green: 0.17, blue: 0.16)).frame(width: 11, height: 18); window } }
                    Image(systemName: "house.fill").font(.system(size: 58, weight: .regular)).foregroundStyle(Color(red: 0.68, green: 0.39, blue: 0.28)).overlay(alignment: .top) { Image(systemName: "snowflake").font(.system(size: 13, weight: .medium)).foregroundStyle(.white).offset(y: 6) }
                }
            case .snowman:
                VStack(spacing: -4) {
                    Circle().fill(.white).frame(width: 18, height: 18).overlay(alignment: .top) { Capsule().fill(Color(red: 0.2, green: 0.29, blue: 0.43)).frame(width: 19, height: 5).offset(y: -5) }.overlay(alignment: .center) { HStack(spacing: 4) { Circle().fill(.black).frame(width: 2, height: 2); Circle().fill(.black).frame(width: 2, height: 2) }.offset(y: 1) }
                    Circle().fill(.white).frame(width: 32, height: 30).overlay(alignment: .center) { VStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Color(red: 0.32, green: 0.4, blue: 0.48)).frame(width: 3, height: 3) } } }
                }.shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            case .lantern:
                VStack(spacing: 1) {
                    Capsule().fill(Color(red: 0.35, green: 0.26, blue: 0.19)).frame(width: 12, height: 3)
                    RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.3, green: 0.24, blue: 0.2)).frame(width: 13, height: 19).overlay { RoundedRectangle(cornerRadius: 2).fill(Color(red: 1, green: 0.72, blue: 0.3).opacity(0.9)).frame(width: 7, height: 12).shadow(color: .orange, radius: 6) }
                    Capsule().fill(Color(red: 0.35, green: 0.26, blue: 0.19)).frame(width: 15, height: 3)
                    Capsule().stroke(Color(red: 0.35, green: 0.26, blue: 0.19), lineWidth: 1.4).frame(width: 9, height: 9).padding(.top, -2)
                }
            }
        }
        .scaleEffect(x: flipped ? -1 : 1, y: 1)
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
        .accessibilityHidden(true)
    }
    private var window: some View { RoundedRectangle(cornerRadius: 2).fill(Color(red: 1, green: 0.79, blue: 0.43)).frame(width: 8, height: 10).shadow(color: .orange.opacity(0.7), radius: 4) }
    private func treeTier(width: CGFloat, height: CGFloat, color: Color) -> some View {
        TreeTier().fill(color).frame(width: width, height: height).overlay(alignment: .top) { Ellipse().fill(.white.opacity(0.9)).frame(width: width * 0.65, height: 3).offset(y: 2) }
    }
}

private struct TreeTier: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(); path.move(to: CGPoint(x: rect.midX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); path.closeSubpath(); return path
    }
}
