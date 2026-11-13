import Foundation

/// Cheap validation only. Key derivation stays on the network queue.
enum ScreenBridgeConnectionPolicy {
    static func validHost(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 253
            && !value.contains(where: { $0.isWhitespace || $0.isNewline || $0.isASCII && $0.asciiValue! < 33 })
            && !value.contains(where: { "/@?#".contains($0) })
    }
    static func validCode(_ value: String) -> Bool {
        let normalized = value.uppercased().filter { $0 != "-" && $0 != " " }.map {
            $0 == "O" ? Character("0") : ($0 == "I" || $0 == "L" ? Character("1") : $0)
        }
        return normalized.count == 10 && normalized.allSatisfy { "0123456789ABCDEFGHJKMNPQRSTVWXYZ".contains($0) }
    }
}
