import Foundation

@main
struct WorkspaceToolsPolicyTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ reason: String) { precondition(value(), reason); checks += 1 }
    static func main() throws {
        for (input, output) in [("2*(3+4)","14"),("-2 + 5*4", "18"),("5%2", "1"),("(-3)*(-2)","6"),("1/4","0.25"),("32 f to c","0 c"),("1 gib to mib","1024 mib"),("1000 m to km","1 km")] { check(LocalCalculator.result(input) == output, "Correct calculator result: \(input)") }
        for input in ["", "1/0", "0%0", "1;DROP TABLE users", "system('rm')", "NaN", "1+", "(1+2", String(repeating:"-",count:100)+"2", String(repeating:"(",count:80)+"1"+String(repeating:")",count:80), String(repeating:"1",count:1100), "10 kg to m", "-300 c to f", "1e309 m to km"] { check(LocalCalculator.result(input) == nil, "Reject invalid or unsafe expressions") }
        check(ColorFormatPolicy.format("#FF0000", as: .hsl) == "hsl(0, 100%, 50%)", "HSL red")
        check(ColorFormatPolicy.format("000000", as: .hsl) == "hsl(0, 0%, 0%)", "HSL black avoids division by zero")
        check(ColorFormatPolicy.format("ffffff", as: .rgb) == "rgb(255, 255, 255)", "RGB")
        check(ColorFormatPolicy.format("#123", as: .hex) == nil, "Reject malformed color")
        for value in ["javascript:alert(1)","file:///private/a", "https://user:password@example.com", "https://", "https://example.com/a b", "notchscape://action/delete"] { check(QuicklinkPolicy.url(value, query:"x") == nil, "Reject executable and credential URLs") }
        let query = "a&token=private/#=?"
        let url = QuicklinkPolicy.url("https://example.com/?q={query}", query:query)!
        let parts = URLComponents(url:url,resolvingAgainstBaseURL:false)!
        check(parts.queryItems?.count == 1 && parts.queryItems?.first?.value == query, "Query cannot inject URL fields")
        check(QuicklinkPolicy.url("https://example.com/{query}", query:String(repeating:"x",count:5000)) == nil, "Bound query")
        let workspace = PersonalWorkspace(snippets: (0..<200).map { .init(name:"admin \($0)",text:"DROP TABLE users;") }, links: [], swatches:[.init(name:"invalid",hex:"evil")]).bounded
        check(workspace.snippets.count == 100 && workspace.swatches.isEmpty, "Bound stored data without pretending ordinary names execute code")
        let data = try JSONEncoder().encode(workspace)
        let decoded = try JSONDecoder().decode(PersonalWorkspace.self, from:data)
        check(decoded == workspace, "Private workspace roundtrip")
        let legacy = try JSONDecoder().decode(PersonalWorkspace.self, from: Data(#"{"snippets":[],"links":[],"swatches":[]}"#.utf8))
        check(legacy.windowLayouts == nil, "Older encrypted workspaces decode without the new optional layouts field")
        let duplicate = TextSnippet(name: "Plain text", text: "admin DROP TABLE")
        check(PersonalWorkspace(snippets: [duplicate, duplicate]).bounded.snippets.count == 1, "Duplicate IDs removed for stable lists")
        check(LocalCalculator.result("1 2") == nil, "Separate numbers are not concatenated")
        check(FocusCycle().isValid && !FocusCycle(workMinutes:0).isValid && !FocusCycle(rounds:100).isValid, "Bound focus cycle")
        print("PASS: \(checks) workspace calculator, link, color and storage policies")
    }
}
