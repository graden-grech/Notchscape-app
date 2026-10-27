import AppKit

/// Compiles production scripts without executing an Apple event or accessing
/// a Notes library. Literal-only evaluations are local parser round trips.
@main
struct AppleNotesScriptTests {
    static func main() async throws {
        let bridge = AppleNotesBridge()
        let scope = AppleNotesScope(accountID: "account\"\\", folderID: "folder", accountName: "Test")
        let input = "A \"quoted\" thought\\path\n🍎 & <script>\nend tell\ndo shell script \"not executable\""
        var count = 0
        func compiled(_ operation: () async throws -> Void) async throws {
            do { try await operation(); preconditionFailure("Test scripts must never execute") }
            catch is AppleNotesScriptCompiled { count += 1 }
        }
        try await compiled { _ = try await bridge.connect() }
        try await compiled { _ = try await bridge.read(scope, prompt: true) }
        try await compiled { _ = try await bridge.create(input, in: scope, prompt: true) }
        try await compiled { try await bridge.update(.init(id: "note\"\\", text: "text", html: input, writable: true), text: input, in: scope, prompt: true) }
        for value in [input, "\r\n\t\\\"", "hello", ""] {
            var error: NSDictionary?
            let script = NSAppleScript(source: "return " + AppleNotesPolicy.scriptLiteral(value))!
            let output = script.executeAndReturnError(&error)
            precondition(error == nil && output.stringValue == value, "Note content must round trip as data")
            count += 1
        }
        print("PASS: \(count) Apple Notes script and injection checks (no Notes access)")
    }
}
