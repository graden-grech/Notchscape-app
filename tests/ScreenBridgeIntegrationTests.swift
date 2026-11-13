import AppKit

final class FakeBridgeTransport: ScreenBridgeTransport {
    var onReady: (() -> Void)?
    var onMessage: (([String: Any]) -> Void)?
    var onClose: ((String) -> Void)?
    var connections = 0, disconnects = 0
    func connect(host: String, code: String) { connections += 1 }
    func disconnect() { disconnects += 1 }
    func send(_ message: [String: Any]) {}
}
final class FakeBridgeInput: ScreenBridgeInputRouting {
    var direction = ScreenBridgeControlDirection.both
    var side = SBSide.right
    var displayID: String?
    var displays: [SBDisplayInfo] = []
    var send: (([String: Any]) -> Void)?
    var status: ((String) -> Void)?
    var starts = 0, stops = 0, returns = 0
    var succeeds = true
    func refreshDisplays() {}
    func start() -> Bool { starts += 1; return succeeds }
    func stop() { stops += 1 }
    func returnLocal(notify: Bool, position: Double?) { returns += 1 }
    func receive(_ message: [String: Any]) {}
}

@main struct ScreenBridgeIntegrationTests {
    @MainActor static func main() {
        for address in ["192.0.2.1", "example.local", "100.64.0.2", "::1"] {
            precondition(ScreenBridgeConnectionPolicy.validHost(address))
        }
        for address in ["", "https://example.com", "a/b", "a@b", "a b", "a\n", String(repeating: "a", count: 254)] {
            precondition(!ScreenBridgeConnectionPolicy.validHost(address))
        }
        for code in ["ABCDE-FGHJK", "abcde fghjk", "OIL23-45678"] { precondition(ScreenBridgeConnectionPolicy.validCode(code)) }
        for code in ["", "123456", "ABCDE-FGHIU", "ABCDE-FGHJKX"] { precondition(!ScreenBridgeConnectionPolicy.validCode(code)) }
        precondition(ScreenBridgeControlDirection.both.allowsMacToWindows && ScreenBridgeControlDirection.both.allowsWindowsToMac)
        precondition(ScreenBridgeControlDirection.macToWindows.allowsMacToWindows && !ScreenBridgeControlDirection.macToWindows.allowsWindowsToMac)
        precondition(!ScreenBridgeControlDirection.windowsToMac.allowsMacToWindows && ScreenBridgeControlDirection.windowsToMac.allowsWindowsToMac)
        var before: UInt32 = 0
        CGGetEventTapList(0, nil, &before)
        let bridge = ScreenBridgeManager()
        precondition(!bridge.connected && !bridge.connecting && bridge.code.isEmpty)
        bridge.host = ""; bridge.code = "ABCDE-FGHJK"; bridge.connect()
        precondition(!bridge.connected && !bridge.connecting)
        bridge.disconnect()
        precondition(!bridge.connected && !bridge.connecting && bridge.code.isEmpty && bridge.windowsDisplays.isEmpty)
        var after: UInt32 = 0
        CGGetEventTapList(0, nil, &after)
        precondition(after == before, "Opening or cancelling must never install an event tap")
        let domain = "Notchscape.ScreenBridge.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let transport = FakeBridgeTransport(), routing = FakeBridgeInput()
        var locked = false
        let simulated = ScreenBridgeManager(link: transport, input: routing, defaults: defaults,
            isLocked: { locked }, canCapture: { true }, otherClientRunning: { false })
        func connect() { simulated.host = "192.0.2.1"; simulated.code = "ABCDE-FGHJK"; simulated.connect() }
        connect(); precondition(simulated.connecting && transport.connections == 1 && routing.starts == 0)
        locked = true; transport.onReady?()
        precondition(!simulated.connecting && !simulated.connected && routing.starts == 0 && transport.disconnects == 1)
        locked = false; connect(); simulated.disconnect(); transport.onReady?()
        precondition(!simulated.connected && routing.starts == 0)
        connect(); transport.onReady?()
        precondition(simulated.connected && !simulated.connecting && routing.starts == 1 && simulated.code.isEmpty)
        let returnsBeforeDirectionChange = routing.returns
        simulated.setDirection(.windowsToMac)
        precondition(simulated.connected && routing.direction == .windowsToMac && routing.returns == returnsBeforeDirectionChange + 1)
        precondition(defaults.string(forKey: "screenBridgeDirection") == "windowsToMac")
        let restored = ScreenBridgeManager(link: FakeBridgeTransport(), input: FakeBridgeInput(), defaults: defaults,
            isLocked: { false }, canCapture: { true }, otherClientRunning: { false })
        precondition(restored.direction == .windowsToMac && !restored.connected && !restored.connecting)
        locked = true; transport.onMessage?(["type": "move", "dx": 1, "dy": 1])
        precondition(!simulated.connected && routing.stops > 0)
        locked = false; routing.succeeds = false; connect(); transport.onReady?()
        precondition(!simulated.connected && !simulated.connecting)
        precondition(defaults.string(forKey: "code") == nil && defaults.string(forKey: "screenBridgeCode") == nil)
        print("PASS: validation, dormant setup, cancel, ready-after-lock, ready-after-cancel, reconnect, permission failure and locked-message cleanup; fake routing only")
    }
}
