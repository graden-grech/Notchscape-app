import AppKit
import Defaults

@MainActor
final class AgentInsightsManager: ObservableObject {
    static let shared = AgentInsightsManager()
    @Published private(set) var readings: [AgentUsageReading] = []
    @Published private(set) var refreshing = false
    private var lastRefresh = Date.distantPast
    private init() {}

    func ingest(_ object: [String: Any], provider: String) {
        guard Defaults[.agentUsageEnabled],
              let reading = AgentUsageReading.decode(object, provider: provider, now: Date(), source: "Agent hook") else { return }
        readings.removeAll { $0.provider == provider }; readings.append(reading)
    }
    func refreshLocalUsage() async {
        guard Defaults[.agentUsageEnabled], !refreshing, Date().timeIntervalSince(lastRefresh) >= 30 else { return }
        refreshing = true; lastRefresh = Date()
        let result = await Task.detached(priority: .utility) { Self.readCodexUsage() }.value
        refreshing = false
        guard Defaults[.agentUsageEnabled], let result else { return }
        readings.removeAll { $0.provider == result.provider }; readings.append(result)
    }
    func clear() { readings = [] }
    func openAgent(_ provider: String) {
        let id = provider.localizedCaseInsensitiveContains("claude") ? "com.apple.Terminal" : "com.openai.codex"
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
    /// An opt-in, bounded read of usage events only. No credential/OAuth access,
    /// prompts, transcript display, network calls, or recursive file watching.
    private nonisolated static func readCodexUsage() -> AgentUsageReading? {
        let manager = FileManager.default
        let root = manager.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions", isDirectory: true)
        var candidates: [(URL, Date)] = []
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy/MM/dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
        for offset in 0..<7 {
            guard let day = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let folder = root.appendingPathComponent(formatter.string(from: day), isDirectory: true)
            let urls = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []
            for url in urls.prefix(200) where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey]), values.isSymbolicLink != true,
                      let date = values.contentModificationDate else { continue }
                candidates.append((url, date))
            }
        }
        for (url, modified) in candidates.sorted(by: { $0.1 > $1.1 }).prefix(8) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            guard let size = try? handle.seekToEnd() else { continue }
            try? handle.seek(toOffset: size > 262_144 ? size - 262_144 : 0)
            guard let data = try? handle.read(upToCount: 262_144), let tail = String(data: data, encoding: .utf8) else { continue }
            for line in tail.split(separator: "\n").reversed() {
                guard line.contains("token_count"), let json = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                      let payload = object["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                      var reading = AgentUsageReading.decode(payload, provider: "Codex", now: Date(), source: "Local Codex usage event") else { continue }
                reading.date = modified
                return reading
            }
        }
        return nil
    }
}
