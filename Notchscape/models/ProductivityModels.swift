import Foundation
import CoreFoundation

enum NotchTool: String, CaseIterable, Identifiable {
    case clipboard, notes, devices, capture, utilities
    var id: Self { self }
    var title: String {
        switch self { case .clipboard: "Clipboard"; case .notes: "Notes"; case .devices: "Devices"; case .capture: "Text Capture"; case .utilities: "Utilities" }
    }
    var symbol: String {
        switch self { case .clipboard: "doc.on.clipboard"; case .notes: "note.text"; case .devices: "airpodspro"; case .capture: "text.viewfinder"; case .utilities: "eyedropper.halffull" }
    }
}

struct ClipboardEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var text: String?
    var image: Data?
    var source = ""
    var pinned = false
    // Optional additions keep snapshots written before boards/sensitivity readable.
    var boardID: UUID?
    var sensitive: Bool?
    var kind: ClipboardContentKind?
    var sensitiveExpiresAt: Date?
    var title: String { text.map { String($0.prefix(160)) } ?? "Copied image" }
    var byteCount: Int { (text?.utf8.count ?? 0) + (image?.count ?? 0) }
    var expiresAt: Date? { sensitive == true ? sensitiveExpiresAt.map { min($0, date.addingTimeInterval(600)) } : nil }
}

struct ClipboardBoard: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    static func validName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return trimmed
    }
}

enum ClipboardContentKind: String, Codable, CaseIterable, Identifiable {
    case text = "Text", link = "Links", image = "Images", color = "Colors", code = "Code"
    var id: Self { self }
    var symbol: String {
        switch self { case .text: "doc.text"; case .link: "link"; case .image: "photo"; case .color: "paintpalette"; case .code: "curlybraces" }
    }
    static func classify(text: String?, image: Data?) -> Self {
        if image != nil { return .image }
        let value = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if value.utf8.count <= 16_384, let url = URLComponents(string: value),
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
           !value.contains(where: \.isWhitespace) { return .link }
        if value.range(of: #"^(?:#[0-9a-fA-F]{3,4}|#[0-9a-fA-F]{6}|#[0-9a-fA-F]{8}|(?:rgb|hsl)a?\([^\n]{1,100}\))$"#, options: .regularExpression) != nil { return .color }
        let prefix = String(value.prefix(500))
        if ["{", "[", "import ", "func ", "function ", "const ", "let ", "class ", "def ", "SELECT ", "#!/"].contains(where: prefix.hasPrefix) { return .code }
        return .text
    }
}

enum ClipboardDateFilter: String, CaseIterable, Identifiable {
    case any = "Any Time", today = "Today", yesterday = "Yesterday", week = "This Week"
    var id: Self { self }
    func includes(_ date: Date, now: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .any: true
        case .today: calendar.isDate(date, inSameDayAs: now)
        case .yesterday: calendar.date(byAdding: .day, value: -1, to: now).map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        case .week: calendar.dateInterval(of: .weekOfYear, for: now)?.contains(date) == true
        }
    }
}

enum ClipboardSearch {
    /// Exact matching covers the whole copy. Loose matching is bounded to its
    /// beginning and app name, so huge copies never create an unbounded fuzzy index.
    static func matches(_ entry: ClipboardEntry, query: String) -> Bool {
        let query = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !query.isEmpty else { return true }
        let text = entry.sensitive == true ? "" : entry.text ?? ""
        if text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            || entry.source.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil { return true }
        guard query.count >= 3 else { return false }
        let haystack = (entry.source + " " + String(text.prefix(8_000))).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let words = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).split(whereSeparator: \.isWhitespace)
        return words.allSatisfy { word in
            var remaining = word.makeIterator(), next = remaining.next()
            for character in haystack {
                if character == next { next = remaining.next(); if next == nil { return true } }
            }
            return false
        }
    }
}

enum ClipboardTransform: String, CaseIterable, Identifiable {
    case uppercase = "UPPERCASE", lowercase = "lowercase", titleCase = "Title Case", trim = "Trim Edges"
    case sortLines = "Sort Lines", uniqueLines = "Remove Duplicate Lines"
    case prettyJSON = "Format JSON", minifyJSON = "Minify JSON"
    case base64Encode = "Base64 Encode", base64Decode = "Base64 Decode"
    case urlEncode = "URL Encode", urlDecode = "URL Decode"
    var id: Self { self }
    func apply(to input: String) -> String? {
        guard input.utf8.count <= 50_000 else { return nil }
        switch self {
        case .uppercase: return input.uppercased()
        case .lowercase: return input.lowercased()
        case .titleCase: return input.capitalized
        case .trim: return input.trimmingCharacters(in: .whitespacesAndNewlines)
        case .sortLines: return input.components(separatedBy: "\n").sorted().joined(separator: "\n")
        case .uniqueLines:
            var seen = Set<String>()
            return input.components(separatedBy: "\n").filter { seen.insert($0).inserted }.joined(separator: "\n")
        case .prettyJSON, .minifyJSON:
            guard let object = try? JSONSerialization.jsonObject(with: Data(input.utf8), options: [.fragmentsAllowed]),
                  let result = try? JSONSerialization.data(withJSONObject: object, options: self == .prettyJSON ? [.prettyPrinted, .sortedKeys, .fragmentsAllowed] : [.sortedKeys, .fragmentsAllowed]) else { return nil }
            return String(data: result, encoding: .utf8)
        case .base64Encode: return Data(input.utf8).base64EncodedString()
        case .base64Decode: return Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { String(data: $0, encoding: .utf8) }
        case .urlEncode: return input.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        case .urlDecode: return input.removingPercentEncoding
        }
    }
}

enum ClipboardPolicy {
    static func recordingAllowed(enabled: Bool, loaded: Bool, locked: Bool, userPaused: Bool) -> Bool {
        enabled && loaded && !locked && !userPaused
    }
    static let privateTypes: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword"]
    static let excludedApps: Set<String> = ["com.1password.1password", "com.agilebits.onepassword7", "com.apple.Passwords", "com.bitwarden.desktop", "org.keepassxc.keepassxc", "com.lastpass.LastPass"]
    static func canCapture(types: Set<String>, source: String?, exclusions: Set<String>) -> Bool {
        types.isDisjoint(with: privateTypes) && !exclusions.contains(source ?? "")
    }
    // Best effort only. Private types and app exclusions remain the primary
    // boundary; arbitrary passwords and image contents cannot be detected here.
    static func detectsSensitive(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil { return true }
        if value.contains("-----BEGIN ") && value.contains("PRIVATE KEY-----") { return true }
        let token = #"(?:\b(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-(?:proj-|ant-)?[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{15,})|\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,})"#
        if value.range(of: token, options: .regularExpression) != nil { return true }
        // Bounded card candidates, validated by Luhn rather than digit count.
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\d)(?:\d[ -]?){12,18}\d(?!\d)"#) else { return false }
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).prefix(32) {
            guard let range = Range(match.range, in: value) else { continue }
            let digits = value[range].compactMap(\.wholeNumberValue)
            guard (13...19).contains(digits.count), Set(digits).count > 1 else { continue }
            let sum = digits.reversed().enumerated().reduce(0) { sum, item in
                let doubled = item.offset % 2 == 1 ? item.element * 2 : item.element
                return sum + (doubled > 9 ? doubled - 9 : doubled)
            }
            if sum % 10 == 0 { return true }
        }
        return false
    }
    static func prepared(_ item: ClipboardEntry) -> ClipboardEntry {
        var item = item
        if item.sensitive == nil { item.sensitive = item.text.map(detectsSensitive) ?? false }
        if item.kind == nil { item.kind = ClipboardContentKind.classify(text: item.text, image: item.image) }
        return item
    }
    static func captured(_ item: ClipboardEntry) -> ClipboardEntry {
        var item = prepared(item)
        if item.sensitive == true { item.sensitiveExpiresAt = item.date.addingTimeInterval(600) }
        return item
    }
    static func removingExpiredSensitive(_ items: [ClipboardEntry], now: Date) -> [ClipboardEntry] {
        items.filter { $0.expiresAt.map { $0 > now } ?? true }
    }
    static func retained(_ items: [ClipboardEntry], now: Date, days: Int) -> [ClipboardEntry] {
        var bytes = 0
        var ids = Set<UUID>()
        return Array(items.sorted { $0.pinned != $1.pinned ? $0.pinned : $0.date > $1.date }.filter {
            guard ids.insert($0.id).inserted, $0.date <= now,
                  $0.expiresAt.map({ $0 > now }) ?? true,
                  $0.pinned || now.timeIntervalSince($0.date) < Double(max(1, min(30, days))) * 86400,
                  $0.byteCount > 0, $0.byteCount <= 2_000_000 else { return false }
            guard bytes + $0.byteCount <= 12_000_000 else { return false }
            bytes += $0.byteCount
            return true
        }.prefix(150))
    }
}

struct QuickNote: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var modified = Date()
    var appleNote: AppleNoteLink?
    var isConflictCopy: Bool?
    var title: String {
        String(text.split(whereSeparator: \.isNewline).first.map(String.init)?.prefix(80) ?? "New note")
            + (isConflictCopy == true ? " (conflict copy)" : "")
    }
}

struct AppleNotesScope: Codable, Equatable {
    var accountID: String
    var folderID: String
    var accountName: String
}

struct AppleNoteLink: Codable, Equatable {
    var remoteID: String
    var baseText: String
}

struct AppleNotesState: Codable, Equatable {
    var scope: AppleNotesScope?
    var ignoredRemoteIDs: Set<String> = []
}

enum AppleNotesPolicy {
    enum Resolution: Equatable { case unchanged, pull, push, conflict }
    static func normalized(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        while value.hasSuffix("\n") { value.removeLast() }
        return value
    }
    static func resolve(local: String, remote: String, base: String) -> Resolution {
        let local = normalized(local), remote = normalized(remote), base = normalized(base)
        if local == remote { return .unchanged }
        if local == base { return .pull }
        if remote == base { return .push }
        return .conflict
    }
    static func html(_ text: String) -> String {
        normalized(text).components(separatedBy: "\n").map {
            "<div>" + ($0.isEmpty ? "<br>" : $0.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")) + "</div>"
        }.joined()
    }
    /// Escaping occurs before compilation; note content is never executable code.
    static func scriptLiteral(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t") + "\""
    }
    static func supported(text: String, html: String) -> Bool {
        guard text.count <= 50_000, !text.contains("\0"), html.utf8.count <= 1_000_000 else { return false }
        // Never replace checklists, links, styled text, tables or embedded media
        // with a plain-text editor's output. Native Notes keeps those originals.
        let rich = #"(?i)<\s*(?:table|ul|ol|li|img|object|a|h[1-6]|b|strong|i|em|u|s|strike|del|blockquote)\b|font-weight\s*:|font-style\s*:|text-decoration\s*:|data-checked|Apple-dash"#
        return html.range(of: rich, options: .regularExpression) == nil
    }
}

enum NotePolicy {
    static func bounded(_ text: String) -> String { String(text.prefix(50_000)) }
}

struct AgentUsageReading: Equatable, Identifiable {
    var id: String { provider }
    var provider: String
    var remainingPercent: Double?
    var resetsAt: Date?
    var tokens: Int?
    var date: Date
    var source: String

    static func decode(_ object: [String: Any], provider: String, now: Date, source: String) -> Self? {
        let usage = object["usage"] as? [String: Any] ?? object
        let limits = usage["rate_limits"] as? [String: Any] ?? [:]
        let primary = limits["primary"] as? [String: Any] ?? [:]
        func number(_ value: Any?) -> Double? {
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
            return n.doubleValue
        }
        let remaining = number(usage["remaining_percent"]) ?? number(primary["used_percent"]).map { 100 - $0 }
        let reset = number(usage["resets_at"]) ?? number(primary["resets_at"])
        let info = usage["info"] as? [String: Any] ?? [:]
        let total = info["total_token_usage"] as? [String: Any] ?? [:]
        let tokenValue = number(usage["total_tokens"]) ?? number(total["total_tokens"])
        let validRemaining = remaining.flatMap { (0...100).contains($0) ? $0 : nil }
        let validTokens = tokenValue.flatMap { $0 >= 0 && $0 < Double(Int.max) ? Int($0) : nil }
        guard validRemaining != nil || validTokens != nil else { return nil }
        return .init(provider: provider, remainingPercent: validRemaining,
                     resetsAt: reset.flatMap { $0 > now.timeIntervalSince1970 && $0 < now.addingTimeInterval(31 * 86400).timeIntervalSince1970 ? Date(timeIntervalSince1970: $0) : nil },
                     tokens: validTokens, date: now, source: source)
    }
}

enum DeviceBatteryPolicy {
    static func percent(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, (0...100).contains(n.doubleValue) else { return nil }
        return n.intValue
    }
    static func address(_ value: String) -> String { value.lowercased().filter { $0.isHexDigit } }
    /// Optional fields from the built-in System Information Bluetooth report.
    /// Only battery numbers and their device address leave this decoder.
    static func report(_ object: Any) -> [String: [String: Int]] {
        var result: [String: [String: Int]] = [:]
        var visited = 0
        func walk(_ value: Any, depth: Int) {
            visited += 1
            guard depth < 12, visited < 2000 else { return }
            if let dictionary = value as? [String: Any] {
                if let raw = dictionary["device_address"] as? String, address(raw).count == 12 {
                    let keys = ["device_batteryLevelLeft": "left", "device_batteryLevelRight": "right",
                        "device_batteryLevelCase": "case", "device_batteryLevelMain": "battery", "device_batteryLevelSingle": "battery"]
                    var levels: [String: Int] = [:]
                    for (key, label) in keys {
                        if let number = percent(dictionary[key]) { levels[label] = number }
                        else if let text = dictionary[key] as? String,
                                let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")),
                                let validated = percent(NSNumber(value: number)) { levels[label] = validated }
                    }
                    if !levels.isEmpty { result[address(raw)] = levels }
                }
                for child in dictionary.values { walk(child, depth: depth + 1) }
            } else if let array = value as? [Any] {
                for child in array.prefix(200) { walk(child, depth: depth + 1) }
            }
        }
        walk(object, depth: 0)
        return result
    }
}
