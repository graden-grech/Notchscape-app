import Foundation
import SQLite3

@main
struct AgentChatTitleTests {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message); count += 1
    }
    static func main() throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--local-smoke" {
            let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
            guard let title = AgentChatTitleStore.codexTitle(sessionID: CommandLine.arguments[2], home: home) else {
                throw NSError(domain: "No local title metadata for that exact session", code: 3)
            }
            check(title != "/" && title != "Codex chat", "Real chat name rather than a fallback")
            print("Read-only live Codex title lookup passed (\(title.count) characters; title not logged)")
            return
        }
        for invalid in ["", " ", "/", "///", "\\\\", "<>/", "—", "\0\t"] {
            check(AgentChatTitlePolicy.clean(invalid) == nil, "No slash/punctuation-only chat labels")
        }
        check(AgentChatTitlePolicy.clean("  My\n chat\t title\0 ") == "My chat title", "Control characters and whitespace normalize")
        check(AgentChatTitlePolicy.clean("修正 / Weather 🌦️") == "修正 / Weather 🌦️", "Real Unicode names and meaningful slashes remain")
        check(AgentChatTitlePolicy.clean(String(repeating: "🍎a", count: 200))?.count == 160, "Titles are bounded without splitting characters")
        check(AgentChatTitlePolicy.explicit(in: ["thread_name": "Real chat", "cwd": "/"]) == "Real chat", "Hook title wins over cwd")
        check(AgentChatTitlePolicy.explicit(in: ["session_title": "/", "chat_title": "Fix weather"]) == "Fix weather", "Invalid earlier field does not mask a valid name")
        check(AgentChatTitlePolicy.explicit(in: ["thread": ["name": "Renamed chat"]]) == "Renamed chat", "Nested title metadata")
        check(AgentChatTitlePolicy.explicit(in: ["tool_input": ["title": "Not a chat title"], "prompt": "Not a title either"]) == nil, "Never use tool or prompt content as a title")
        check(AgentChatTitlePolicy.fallback(provider: "Codex", cwd: "/") == "Codex chat", "Root cwd is not a slash label")
        check(AgentChatTitlePolicy.fallback(provider: "Claude Code", cwd: nil) == "Claude Code chat", "Provider-specific empty fallback")
        check(AgentChatTitlePolicy.fallback(provider: "Codex", cwd: "/work/Weather") == "Weather", "Readable project fallback")
        for id in ["", "../secret", "x' OR 1=1 --", String(repeating: "a", count: 161)] {
            check(!AgentChatTitlePolicy.validSessionID(id), "Invalid session cannot select another chat or traverse directories")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Notchscape-title-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let index = root.appendingPathComponent("session_index.jsonl")
        try Data("{\"id\":\"a\",\"thread_name\":\"Old name\"}\n{\"id\":\"b\",\"thread_name\":\"Other chat\"}\n{\"id\":\"a\",\"thread_name\":\"Renamed chat\"}\n".utf8).write(to: index)
        check(AgentChatTitleStore.codexTitle(sessionID: "a", home: root) == "Renamed chat", "Newest matching title, not another chat in the same project")
        check(AgentChatTitleStore.codexTitle(sessionID: "missing", home: root) == nil, "No guess from another session")
        let database = root.appendingPathComponent("state_5.sqlite")
        try fixture(database, sql: "CREATE TABLE threads (id TEXT PRIMARY KEY, name TEXT, title TEXT); INSERT INTO threads VALUES ('c', 'Custom name', 'Old automatic title'), ('d', NULL, 'Automatic title');")
        let original = try Data(contentsOf: database)
        check(AgentChatTitleStore.codexTitle(sessionID: "c", home: root) == "Custom name", "Read-only named-chat lookup")
        check(AgentChatTitleStore.codexTitle(sessionID: "d", home: root) == "Automatic title", "Title fallback when no custom name")
        check(AgentChatTitleStore.databaseTitle(sessionID: "x' OR 1=1 --", database: database) == nil, "SQL-like session rejected")
        let afterLookup = try Data(contentsOf: database)
        check(afterLookup == original, "Metadata database is never modified")
        let older = root.appendingPathComponent("older.sqlite")
        try fixture(older, sql: "CREATE TABLE threads (id TEXT PRIMARY KEY, title TEXT); INSERT INTO threads VALUES ('a', 'Older schema title');")
        check(AgentChatTitleStore.databaseTitle(sessionID: "a", database: older) == "Older schema title", "Older schemas remain supported")
        check(AgentChatTitleStore.databaseTitle(sessionID: "a", database: root.appendingPathComponent("absent.sqlite")) == nil, "Missing database is unavailable, not created")
        check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("absent.sqlite").path), "Read-only open never creates a database")
        let projects = root.appendingPathComponent("projects")
        let project = projects.appendingPathComponent("test")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let transcript = project.appendingPathComponent("claude-session.jsonl")
        try Data("{\"type\":\"user\",\"message\":\"Private prompt never used\"}\n{\"type\":\"custom-title\",\"sessionId\":\"claude-session\",\"customTitle\":\"Claude chat name\"}\n".utf8).write(to: transcript)
        check(AgentChatTitleStore.claudeTitle(sessionID: "claude-session", transcriptPath: transcript.path, projects: projects) == "Claude chat name", "Dedicated Claude title record")
        check(AgentChatTitleStore.claudeTitle(sessionID: "other-session", transcriptPath: transcript.path, projects: projects) == nil, "Transcript belongs to the exact session")
        check(AgentChatTitleStore.claudeTitle(sessionID: "claude-session", transcriptPath: transcript.path, projects: root.appendingPathComponent("unrelated")) == nil, "Cannot read arbitrary hook-supplied files")
        let claudeIndex = project.appendingPathComponent("sessions-index.json")
        try Data(#"{"entries":[{"sessionId":"claude-session","customTitle":"Indexed Claude name","summary":"Summary"}]}"#.utf8).write(to: claudeIndex)
        check(AgentChatTitleStore.claudeTitle(sessionID: "claude-session", transcriptPath: transcript.path, projects: projects) == "Indexed Claude name", "Claude index custom name precedes summary")
        // A partial leading record and an oversized record cannot break the tail parser.
        try (Data(repeating: 120, count: 600_000) + Data("\n{\"id\":\"a\",\"thread_name\":\"Tail title\"}\n".utf8)).write(to: index)
        check(AgentChatTitleStore.codexTitle(sessionID: "a", home: root) == "Tail title", "Bounded tail lookup skips partial records")
        print("\(count) AI chat-title checks passed")
    }

    static func fixture(_ url: URL, sql: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw NSError(domain: "Fixture", code: 1) }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw NSError(domain: "Fixture", code: 2) }
    }
}
