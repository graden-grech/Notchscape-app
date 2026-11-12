import Foundation

@main
struct ClipboardProPolicyTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ reason: String) {
        precondition(condition(), reason); checks += 1
    }
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let legacyJSON = #"{"id":"00000000-0000-0000-0000-000000000001","date":0,"text":"Preserve this copy","source":"Fixture","pinned":true}"#
        let legacy = try JSONDecoder().decode(ClipboardEntry.self, from: Data(legacyJSON.utf8))
        check(legacy.boardID == nil && legacy.sensitive == nil && legacy.kind == nil, "Old encrypted clipboard records decode without new fields")
        let prepared = ClipboardPolicy.prepared(legacy)
        check(prepared.id == legacy.id && prepared.text == legacy.text && prepared.pinned, "Classification preserves IDs, content and pin state")
        check(prepared.sensitive == false && prepared.kind == .text, "Ordinary old copies receive safe metadata")
        let board = ClipboardBoard(name: "School")
        let entry = ClipboardEntry(date: now, text: "Test", source: "Fixture", pinned: true, boardID: board.id, sensitive: false, kind: .text)
        let entryRoundTrip = try JSONDecoder().decode(ClipboardEntry.self, from: JSONEncoder().encode(entry))
        let boardRoundTrip = try JSONDecoder().decode(ClipboardBoard.self, from: JSONEncoder().encode(board))
        check(entryRoundTrip == entry, "Board metadata survives Codable round trip")
        check(boardRoundTrip == board, "Board round trip")
        check(ClipboardBoard.validName("  School  ") == "School", "Board name trims outer whitespace")
        for name in ["", "  ", "Bad\nName", "Bad\0Name", String(repeating: "x", count: 41)] {
            check(ClipboardBoard.validName(name) == nil, "Board names are bounded plain text")
        }
        check(ClipboardBoard.validName("admin DROP TABLE") != nil, "Ordinary names are data, never interpreted as commands")
        for value in ["123456", "4111 1111 1111 1111", "sk-proj-" + String(repeating: "a", count: 25), "ghp_" + String(repeating: "b", count: 25), "-----BEGIN PRIVATE KEY-----\nfixture\n-----END PRIVATE KEY-----"] {
            check(ClipboardPolicy.detectsSensitive(value), "Detect synthetic sensitive token/card/code patterns")
        }
        for value in ["Schedule for tomorrow", "4111 1111 1111 1112", "1111111111111111", "https://example.org/school"] {
            check(!ClipboardPolicy.detectsSensitive(value), "Do not indiscriminately mark ordinary text or invalid cards")
        }
        let sensitive = ClipboardPolicy.captured(ClipboardEntry(date: now.addingTimeInterval(-599), text: "123456", pinned: true, boardID: board.id))
        check(ClipboardPolicy.retained([sensitive], now: now, days: 30).count == 1, "Sensitive pin exists before its short expiry")
        check(ClipboardPolicy.retained([sensitive], now: now.addingTimeInterval(1), days: 30).isEmpty, "Sensitive copies expire at ten minutes despite pin/board")
        let oldSensitive = ClipboardEntry(date: now.addingTimeInterval(-601), text: "123456", pinned: true)
        let migratedSensitive = ClipboardPolicy.prepared(oldSensitive)
        check(migratedSensitive.sensitive == true && migratedSensitive.expiresAt == nil, "Legacy sensitive copies are hidden without assigning destructive expiry")
        check(ClipboardPolicy.retained([migratedSensitive], now: now, days: 30).count == 1, "Migration preserves existing pinned records")
        let normalPin = ClipboardEntry(date: now.addingTimeInterval(-31*86400), text: "Keep my pin", pinned: true)
        check(ClipboardPolicy.retained([normalPin], now: now, days: 1) == [normalPin], "Normal pin age semantics stay unchanged")
        let futurePin = ClipboardEntry(date: now.addingTimeInterval(3600), text: "Clock rollback must preserve this", pinned: true)
        check(ClipboardPolicy.removingExpiredSensitive([normalPin, futurePin, migratedSensitive], now: now) == [normalPin, futurePin, migratedSensitive], "Wake/clock expiry never applies general age or future-date pruning to saved copies")
        check(ClipboardPolicy.removingExpiredSensitive([normalPin, sensitive], now: now.addingTimeInterval(1)) == [normalPin], "Wake/clock expiry removes only an explicit expired sensitive capture")
        check(!ClipboardSearch.matches(sensitive, query: "123456"), "Hidden sensitive payload cannot leak through search")
        let fullText = ClipboardEntry(text: String(repeating: "x", count: 10_000) + " exact ending needle", source: "École")
        check(ClipboardSearch.matches(fullText, query: "ending needle"), "Exact search covers content beyond the old title and fuzzy bound")
        check(ClipboardSearch.matches(fullText, query: "ecole"), "App search ignores case and diacritics")
        check(ClipboardSearch.matches(ClipboardEntry(text: "project calendar"), query: "prjct"), "Loose search tolerates skipped letters")
        check(!ClipboardSearch.matches(ClipboardEntry(text: "abc"), query: "zzzz"), "Unmatched searches remain empty")
        let classifications: [(String, ClipboardContentKind)] = [("https://example.org/a", .link), ("#a1b2c3", .color), ("rgb(1, 2, 3)", .color), ("{\"a\":1}", .code), ("ordinary sentence", .text)]
        for (text, kind) in classifications { check(ClipboardContentKind.classify(text: text, image: nil) == kind, "Classify content kinds locally") }
        check(ClipboardContentKind.classify(text: nil, image: Data([0])) == .image, "Images remain images")
        check(ClipboardContentKind.classify(text: "https://example.org some text", image: nil) == .text, "A sentence containing a URL is not misclassified as a link")
        let values: [(ClipboardTransform, String, String)] = [(.uppercase, "hello", "HELLO"), (.lowercase, "HELLO", "hello"), (.titleCase, "hello world", "Hello World"), (.trim, " \nhello \t", "hello"), (.sortLines, "b\na", "a\nb"), (.uniqueLines, "b\na\nb", "b\na"), (.base64Encode, "hello", "aGVsbG8="), (.base64Decode, "aGVsbG8=", "hello"), (.urlEncode, "a&b", "a%26b"), (.urlDecode, "a%26b", "a&b"), (.minifyJSON, "{ \"b\": 2, \"a\": 1 }", "{\"a\":1,\"b\":2}")]
        for (transform, input, result) in values { check(transform.apply(to: input) == result, "Text transform produces the expected preview") }
        check(ClipboardTransform.prettyJSON.apply(to: "{\"a\":1}")?.contains("\n") == true, "Pretty JSON is formatted")
        check(ClipboardTransform.prettyJSON.apply(to: "invalid") == nil, "Invalid JSON has no output")
        check(ClipboardTransform.base64Decode.apply(to: "%%") == nil, "Invalid Base64 has no output")
        check(ClipboardTransform.urlDecode.apply(to: "%QQ") == nil, "Invalid URL escapes have no output")
        check(ClipboardTransform.uppercase.apply(to: String(repeating: "🍎", count: 13_000)) == nil, "Transform work uses a byte bound")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        check(ClipboardDateFilter.today.includes(now, now: now, calendar: calendar), "Today filter")
        check(!ClipboardDateFilter.today.includes(now.addingTimeInterval(-86400), now: now, calendar: calendar), "Previous day is not today")
        check(ClipboardDateFilter.yesterday.includes(now.addingTimeInterval(-86400), now: now, calendar: calendar), "Yesterday filter")
        print("PASS: \(checks) clipboard migration, privacy, retention, filtering and transform checks (synthetic data only)")
    }
}
