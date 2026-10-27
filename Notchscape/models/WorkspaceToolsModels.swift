import Foundation

struct TextSnippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var text: String
}
struct NamedQuicklink: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var template: String
    var folderBookmark: Data?
}
struct SavedSwatch: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var hex: String
}
struct PersonalWorkspace: Codable, Equatable {
    var snippets: [TextSnippet] = []
    var links: [NamedQuicklink] = []
    var swatches: [SavedSwatch] = []
    var windowLayouts: [SavedWindowLayout]?
    var bounded: Self {
        func unique<T: Identifiable>(_ values: [T], limit: Int) -> [T] where T.ID == UUID {
            var seen = Set<UUID>(); return Array(values.prefix(1000).filter { seen.insert($0.id).inserted }.prefix(limit))
        }
        return .init(snippets: unique(snippets, limit: 100).map { .init(id: $0.id, name: String($0.name.prefix(80)), text: String($0.text.prefix(20_000))) },
              links: unique(links, limit: 100).filter { $0.name.count <= 80 && $0.template.utf8.count <= 16_384 && ($0.folderBookmark?.count ?? 0) <= 100_000 },
              swatches: unique(swatches, limit: 100).filter { $0.name.count <= 80 && ColorFormatPolicy.rgb($0.hex) != nil },
              windowLayouts: windowLayouts.map { unique($0.filter(\.isValid), limit: 20) })
    }
}

enum QuicklinkPolicy {
    static func url(_ template: String, query: String) -> URL? {
        guard template.utf8.count <= 16_384, query.utf8.count <= 4096 else { return nil }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let value = template.replacingOccurrences(of: "{query}", with: encoded)
        guard let parts = URLComponents(string: value), ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.user == nil, parts.password == nil, let host = parts.host, !host.isEmpty,
              !value.contains(where: { $0.isWhitespace }), let url = parts.url else { return nil }
        return url
    }
}

enum ColorFormat: String, CaseIterable, Identifiable { case hex = "Hex", rgb = "RGB", hsl = "HSL", swift = "Swift"; var id: Self { self } }
enum ColorFormatPolicy {
    static func rgb(_ value: String) -> (Int, Int, Int)? {
        let value = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard value.count == 6, value.allSatisfy(\.isHexDigit), let n = UInt32(value, radix: 16) else { return nil }
        return (Int(n >> 16), Int((n >> 8) & 255), Int(n & 255))
    }
    static func format(_ hex: String, as kind: ColorFormat) -> String? {
        guard let (r, g, b) = rgb(hex) else { return nil }
        switch kind {
        case .hex: return String(format: "#%02X%02X%02X", r, g, b)
        case .rgb: return "rgb(\(r), \(g), \(b))"
        case .swift: return String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", Double(r)/255, Double(g)/255, Double(b)/255)
        case .hsl:
            let a = Double(r)/255, c = Double(g)/255, d = Double(b)/255
            let hi = max(a, c, d), lo = min(a, c, d), delta = hi-lo, light = (hi+lo)/2
            let saturation = delta == 0 ? 0 : delta/(1-abs(2*light-1))
            var hue = 0.0
            if delta != 0 { hue = hi == a ? ((c-d)/delta).truncatingRemainder(dividingBy: 6) : hi == c ? (d-a)/delta+2 : (a-c)/delta+4; hue *= 60; if hue < 0 { hue += 360 } }
            return String(format: "hsl(%.0f, %.0f%%, %.0f%%)", hue, saturation*100, light*100)
        }
    }
}

/// Bounded arithmetic grammar. Never calls NSExpression, a shell, JavaScript or eval.
enum LocalCalculator {
    static func result(_ input: String, now: Date = Date()) -> String? {
        guard input.count <= 1024 else { return nil }
        // Whitespace separates tokens; it must not silently merge "1 2" to 12.
        let compactNumbers = input.range(of: #"[0-9.]\s+[0-9.]"#, options: .regularExpression) != nil
        guard !compactNumbers else { return nil }
        let words = input.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count == 4, words[2] == "to", let value = Double(words[0]), value.isFinite,
           let converted = convert(value, from: words[1], to: words[3]), converted.isFinite, abs(converted) < 1e300 { return number(converted) + " " + words[3] }
        if words.count == 3, words[0] == "today", let days = Int(words[1]), abs(Double(days)) < 36_600, words[2] == "days",
           let date = Calendar.current.date(byAdding: .day, value: days, to: now) { return date.formatted(date: .abbreviated, time: .omitted) }
        var parser = Parser(input)
        guard let value = try? parser.expression(), parser.position == parser.chars.count, value.isFinite, abs(value) < 1e300 else { return nil }
        return number(value)
    }
    static func number(_ value: Double) -> String { String(format: "%.12g", value == 0 ? 0 : value) }
    static func convert(_ value: Double, from: String, to: String) -> Double? {
        let units: [String: (String, Double)] = ["mm":("length",0.001),"cm":("length",0.01),"m":("length",1),"km":("length",1000),"in":("length",0.0254),"ft":("length",0.3048),"mi":("length",1609.344),"g":("mass",0.001),"kg":("mass",1),"lb":("mass",0.45359237),"oz":("mass",0.028349523125),"s":("time",1),"min":("time",60),"h":("time",3600),"day":("time",86400),"b":("bytes",1),"kb":("bytes",1000),"mb":("bytes",1e6),"gb":("bytes",1e9),"kib":("bytes",1024),"mib":("bytes",1048576),"gib":("bytes",1073741824)]
        if ["c","f","k"].contains(from), ["c","f","k"].contains(to) {
            let c = from == "f" ? (value-32)*5/9 : from == "k" ? value-273.15 : value
            guard c >= -273.15 else { return nil }; return to == "f" ? c*9/5+32 : to == "k" ? c+273.15 : c
        }
        guard let a = units[from], let b = units[to], a.0 == b.0 else { return nil }
        let result = value*a.1/b.1; return result.isFinite ? result : nil
    }
    private struct Parser {
        enum Invalid: Error { case input }
        var chars: [Character]; var position = 0; var depth = 0; var operations = 0
        init(_ input: String) { chars = Array(input.filter { !$0.isWhitespace }) }
        mutating func expression() throws -> Double {
            depth += 1; defer { depth -= 1 }; guard depth <= 32 else { throw Invalid.input }
            var value = try term()
            while position < chars.count, chars[position] == "+" || chars[position] == "-" {
                let op = chars[position]; position += 1; let rhs = try term(); value = op == "+" ? value+rhs : value-rhs
                try count()
            }; return value
        }
        mutating func term() throws -> Double {
            var value = try atom()
            while position < chars.count, ["*","/","%"].contains(chars[position]) {
                let op = chars[position]; position += 1; let rhs = try atom()
                guard op == "*" || rhs != 0 else { throw Invalid.input }
                value = op == "*" ? value*rhs : op == "/" ? value/rhs : value.truncatingRemainder(dividingBy: rhs); try count()
            }; return value
        }
        mutating func atom() throws -> Double {
            guard position < chars.count else { throw Invalid.input }
            if chars[position] == "+" || chars[position] == "-" {
                let minus = chars[position] == "-"; position += 1; depth += 1; defer { depth -= 1 }
                guard depth <= 32 else { throw Invalid.input }; let value = try atom(); return minus ? -value : value
            }
            if chars[position] == "(" { position += 1; let value = try expression(); guard position < chars.count, chars[position] == ")" else { throw Invalid.input }; position += 1; return value }
            let start = position
            while position < chars.count, chars[position].isASCII && (chars[position].isNumber || chars[position] == ".") { position += 1 }
            guard start < position, let value = Double(String(chars[start..<position])), value.isFinite else { throw Invalid.input }; return value
        }
        mutating func count() throws { operations += 1; guard operations <= 256 else { throw Invalid.input } }
    }
}

struct StopwatchLap: Identifiable { let id = UUID(); let total: TimeInterval; let split: TimeInterval }
enum FocusPhase: String { case work = "Focus", rest = "Break", finished = "Finished" }
struct FocusCycle: Equatable {
    var workMinutes = 25; var breakMinutes = 5; var rounds = 4
    var isValid: Bool { (1...180).contains(workMinutes) && (1...60).contains(breakMinutes) && (1...12).contains(rounds) }
}
