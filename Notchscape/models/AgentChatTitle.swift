import Foundation
import SQLite3

/// Titles are display data, never paths to execute or instructions to interpret.
enum AgentChatTitlePolicy {
    static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0)
        }.map(String.init).joined()
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard text.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else { return nil }
        return String(text.prefix(160))
    }

    static func explicit(in object: [String: Any]) -> String? {
        for key in ["thread_name", "session_title", "chat_title", "conversation_title", "title"] {
            if let title = clean(object[key] as? String) { return title }
        }
        for key in ["thread", "session", "conversation"] {
            if let metadata = object[key] as? [String: Any],
               let title = clean(metadata["name"] as? String) ?? clean(metadata["title"] as? String) { return title }
        }
        return nil
    }

    static func fallback(provider: String, cwd: String?) -> String {
        if let cwd, cwd.hasPrefix("/"), let folder = clean(URL(fileURLWithPath: cwd).lastPathComponent) {
            return folder
        }
        return "\(provider) chat"
    }

    static func validSessionID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 160 && id.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || "-_:".unicodeScalars.contains($0)
        }
    }
}

/// Best-effort adapters for optional local metadata, not a dependency on a
/// provider's private database schema. Never query messages or mutate the store.
enum AgentChatTitleStore {
    static func codexTitle(sessionID: String, home: URL) -> String? {
        guard AgentChatTitlePolicy.validSessionID(sessionID) else { return nil }
        let index = home.appendingPathComponent("session_index.jsonl")
        for row in jsonLines(index, limit: 512 * 1024).reversed() {
            if row["id"] as? String == sessionID,
               let title = AgentChatTitlePolicy.clean(row["thread_name"] as? String) { return title }
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []
        let databases: [(Int, URL)] = files.compactMap { url in
            let name = url.lastPathComponent
            guard name.hasPrefix("state_"), name.hasSuffix(".sqlite"),
                  let version = Int(name.dropFirst(6).dropLast(7)) else { return nil }
            return (version, url)
        }
        for (_, database) in databases.sorted(by: { $0.0 > $1.0 }).prefix(3) {
            if let title = databaseTitle(sessionID: sessionID, database: database) { return title }
        }
        return nil
    }

    static func databaseTitle(sessionID: String, database: URL) -> String? {
        guard AgentChatTitlePolicy.validSessionID(sessionID) else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 30)
        // Older versions have title but no name column. Both queries select
        // just one matching chat; never pick another chat by working directory.
        for query in [
            "SELECT substr(COALESCE(NULLIF(trim(name), ''), title), 1, 512) FROM threads WHERE id = ? LIMIT 1",
            "SELECT substr(title, 1, 512) FROM threads WHERE id = ? LIMIT 1"
        ] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            let bound = sessionID.withCString { sqlite3_bind_text(statement, 1, $0, -1, transient) }
            if bound == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW,
               let bytes = sqlite3_column_text(statement, 0),
               let title = AgentChatTitlePolicy.clean(String(cString: bytes)) { return title }
        }
        return nil
    }

    static func claudeTitle(sessionID: String, transcriptPath: String?, projects: URL) -> String? {
        guard AgentChatTitlePolicy.validSessionID(sessionID), let transcriptPath,
              transcriptPath.utf8.count <= 4096 else { return nil }
        let transcript = URL(fileURLWithPath: transcriptPath).resolvingSymlinksInPath().standardizedFileURL
        let root = projects.resolvingSymlinksInPath().standardizedFileURL
        guard transcript.path.hasPrefix(root.path + "/"),
              transcript.lastPathComponent == sessionID + ".jsonl" else { return nil }
        let index = transcript.deletingLastPathComponent().appendingPathComponent("sessions-index.json")
        if let size = try? index.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1024 * 1024,
           let data = try? Data(contentsOf: index),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let entries = object["entries"] as? [[String: Any]],
           let row = entries.last(where: { $0["sessionId"] as? String == sessionID }),
           let title = AgentChatTitlePolicy.clean(row["customTitle"] as? String)
                ?? AgentChatTitlePolicy.clean(row["summary"] as? String) { return title }
        // Only dedicated title records are used; prompts and tool text are not
        // substitutes for a chat name. The tail read is bounded, not a log scan.
        for row in jsonLines(transcript, limit: 128 * 1024).reversed() {
            if row["type"] as? String == "custom-title",
               row["sessionId"] as? String == sessionID,
               let title = AgentChatTitlePolicy.clean(row["customTitle"] as? String) { return title }
        }
        return nil
    }

    private static func jsonLines(_ url: URL, limit: Int) -> [[String: Any]] {
        guard let file = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? file.close() }
        guard let size = try? file.seekToEnd() else { return [] }
        let offset = size > UInt64(limit) ? size - UInt64(limit) : 0
        guard (try? file.seek(toOffset: offset)) != nil,
              let data = try? file.read(upToCount: limit) else { return [] }
        var lines = data.split(separator: 10, omittingEmptySubsequences: false)
        if offset > 0, !lines.isEmpty { lines.removeFirst() } // Skip a partial record.
        return lines.compactMap { line in
            guard !line.isEmpty, line.count <= 16 * 1024 else { return nil }
            return (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
        }
    }
}

/// No file I/O on the main actor, no polling loop, at most 64 cached sessions.
actor AgentChatTitleResolver {
    private struct Entry { let title: String?; let expires: Date }
    private var cache: [String: Entry] = [:]
    private let codexHome: URL
    private let claudeProjects: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configured = ProcessInfo.processInfo.environment["CODEX_HOME"]
        codexHome = configured.flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? home.appendingPathComponent(".codex")
        claudeProjects = home.appendingPathComponent(".claude/projects")
    }

    func resolve(provider: String, sessionID: String, transcriptPath: String?) -> String? {
        let now = Date()
        let key = provider + ":" + sessionID
        if let entry = cache[key], entry.expires > now { return entry.title }
        let title: String?
        if provider.localizedCaseInsensitiveContains("codex") {
            title = AgentChatTitleStore.codexTitle(sessionID: sessionID, home: codexHome)
        } else if provider.localizedCaseInsensitiveContains("claude") {
            title = AgentChatTitleStore.claudeTitle(sessionID: sessionID, transcriptPath: transcriptPath, projects: claudeProjects)
        } else { title = nil }
        cache = cache.filter { $0.value.expires > now }
        if cache.count >= 64, let oldest = cache.min(by: { $0.value.expires < $1.value.expires })?.key { cache[oldest] = nil }
        cache[key] = Entry(title: title, expires: now.addingTimeInterval(title == nil ? 5 : 30))
        return title
    }
}
