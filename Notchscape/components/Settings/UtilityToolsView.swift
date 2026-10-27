import AppKit
import SwiftUI

struct UtilityToolsView: View {
    var expanded = false
    @ObservedObject private var tools = LocalToolsManager.shared
    @State private var format: ColorFormat = .hex
    @State private var link = ""
    @State private var sampledColor: NSColor?
    @State private var sampler: NSColorSampler?
    @State private var sampling = false
    @State private var message: String?
    private var cleaned: String? { CleanLinkPolicy.clean(link) }
    private var hex: String? {
        guard let color = sampledColor?.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                      Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
    var body: some View {
        ScrollView { content }.scrollIndicators(expanded ? .automatic : .hidden)
            .task { await tools.load() }
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: expanded ? 18 : 8) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Clean Link", systemImage: "link").font(.headline)
                HStack {
                    TextField("Paste an http or https link", text: $link).textFieldStyle(.roundedBorder)
                    Button("Paste") { link = String((NSPasteboard.general.string(forType: .string) ?? "").prefix(16_384)); message = nil }
                }
                HStack {
                    Text(cleaned ?? (link.isEmpty ? "Remove known tracking tags without opening the link." : "Enter a valid web link without a username or password."))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(expanded ? 3 : 1).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button("Copy Clean Link") { if let cleaned { copy(cleaned); message = cleaned == link.trimmingCharacters(in: .whitespacesAndNewlines) ? "Copied. No safe changes needed." : "Copied without known tracking tags." } }
                        .disabled(cleaned == nil)
                }
            }
            Divider()
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9).fill(sampledColor.map(Color.init(nsColor:)) ?? Color.secondary.opacity(0.15))
                    .frame(width: 34, height: 34).overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.secondary.opacity(0.25)))
                    .accessibilityLabel(hex ?? "No sampled color")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen Color").font(.headline)
                    Text(hex.flatMap { ColorFormatPolicy.format($0, as: format) } ?? "Use Apple’s color sampler").font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Button("Pick Color…") { sample() }.disabled(sampling)
                Button("Copy") { if let hex, let value = ColorFormatPolicy.format(hex, as: format) { copy(value); message = "Copied \(format.rawValue)." } }.disabled(hex == nil)
            }
            HStack {
                Picker("Color format", selection: $format) { ForEach(ColorFormat.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
                Button("Save Swatch") { if let hex { tools.saveSwatch(hex) } }.disabled(hex == nil || !tools.loaded || tools.workspace.swatches.count >= 100)
            }
            if expanded, !tools.workspace.swatches.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], alignment: .leading) {
                    ForEach(tools.workspace.swatches) { swatch in
                        HStack {
                            Button(swatch.name) { if let value = ColorFormatPolicy.format(swatch.hex, as: format) { copy(value); message = "Copied saved swatch." } }.font(.caption.monospaced())
                            Button { tools.removeSwatch(swatch.id) } label: { Image(systemName: "xmark.circle") }.help("Remove swatch").accessibilityLabel("Remove \(swatch.name) swatch")
                        }
                    }
                }
            }
            Button { WorkspaceToolsWindowController.shared.show() } label: { Label("Calculator, Snippets, Quicklinks & Clocks…", systemImage: "command") }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary).accessibilityLabel(message) }
            if expanded {
                Text("These tools only run when you use them. Links are never opened or uploaded; signed links and functional query parameters are preserved. Color sampling uses the macOS picker, not background screen capture. Nothing here is added to saved history automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .onDisappear { link = ""; sampledColor = nil; message = nil }
    }
    private func copy(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
    private func sample() {
        sampling = true
        let picker = NSColorSampler(); sampler = picker
        picker.show { color in
            Task { @MainActor in
                sampling = false; sampler = nil
                guard WorkspaceAccess.privateToolsAllowed else { return }
                if let color { sampledColor = color; message = nil }
            }
        }
    }
}
