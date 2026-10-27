import Foundation

@main struct AccountSettingsPolicyTests {
    static func main() throws {
        var checks = 0
        func require(_ result: Bool) { precondition(result); checks += 1 }
        func rejects(_ text: String) {
            do { _ = try AccountSettingsDocument.decode(Data(text.utf8)); preconditionFailure("Accepted unsafe settings") }
            catch { checks += 1 }
            do { _ = try JSONDecoder().decode(AccountSettingsDocument.self, from: Data(text.utf8)); preconditionFailure("Accepted unsafe API document") }
            catch { checks += 1 }
        }
        require(!AccountFeaturePolicy.isEnabled(nil))
        require(!AccountFeaturePolicy.isEnabled(false))
        require(AccountFeaturePolicy.isEnabled(true))
        for invalid: Any in [1, 0, "true", "false", NSNull(), ["enabled": true], [true]] {
            require(!AccountFeaturePolicy.isEnabled(invalid))
        }
        for key in AccountSettingsPolicy.booleans {
            let document = AccountSettingsDocument(values: [key: .bool(true)])
            require(try AccountSettingsDocument.decode(document.encoded()) == document)
        }
        for (key, options) in AccountSettingsPolicy.choices {
            for option in options {
                let document = AccountSettingsDocument(values: [key: .string(option)])
                require(try AccountSettingsDocument.decode(document.encoded()) == document)
            }
        }
        for payload in [
            "{\"schemaVersion\":1,\"values\":{\"role\":\"admin\"}}",
            "{\"schemaVersion\":1,\"values\":{\"hudReplacement\":true}}",
            "{\"schemaVersion\":1,\"values\":{\"showOnExternalDisplays\":false}}",
            "{\"schemaVersion\":1,\"values\":{\"appTheme\":\"DROP TABLE users;\"}}",
            "{\"schemaVersion\":1,\"values\":{\"appTheme\":{\"admin\":true}}}",
            "{\"schemaVersion\":1,\"values\":{\"showBatteryIndicator\":1}}",
            "{\"schemaVersion\":1,\"values\":{\"showBatteryIndicator\":\"true\"}}",
            "{\"schemaVersion\":2,\"values\":{}}",
            "{\"schemaVersion\":1,\"values\":{},\"admin\":true}",
            "{\"schemaVersion\":1,\"values\":{\"homeWidgetOrder\":[\"music\",\"music\"]}}",
            "{\"schemaVersion\":1,\"values\":{\"homeWidgetOrder\":[\"admin\"]}}",
            "{\"schemaVersion\":1,\"values\":{\"__proto__\":\"admin\"}}",
            "{\"schemaVersion\":1,\"values\":{\"quickActions\":[\"rm -rf /\"]}}",
            String(repeating: " ", count: 8_193)
        ] { rejects(payload) }
        let layout = AccountSettingsDocument(values: ["homeWidgetOrder": .strings(["music", "calendar"])])
        require(try AccountSettingsDocument.decode(layout.encoded()) == layout)
        print("Passed \(checks) account settings policy checks")
    }
}
