import SwiftUI

struct ScreenBridgeSettingsView: View {
    @ObservedObject private var bridge = ScreenBridgeManager.shared
    var body: some View {
        Form {
            Section {
                LabeledContent("Connection", value: bridge.connected ? "Connected" : bridge.connecting ? "Connecting…" : "Off")
                Text(bridge.status).foregroundStyle(.secondary).accessibilityLabel("Connection status: \(bridge.status)")
            } header: { Text("ScreenBridge") } footer: {
                Text("Use one mouse and keyboard across your Mac and a Windows PC. Connect only to a computer you trust. Nothing connects automatically.")
            }
            Section {
                TextField("Windows address", text: $bridge.host, prompt: Text("IP address or computer name"))
                    .textContentType(.none)
                    .disabled(bridge.connected || bridge.connecting)
                SecureField("Pairing code", text: $bridge.code, prompt: Text("10 characters from Windows"))
                    .disabled(bridge.connected || bridge.connecting)
                    .onSubmit { bridge.connect() }
                HStack {
                    if bridge.connected || bridge.connecting {
                        Button(bridge.connecting ? "Cancel Connection" : "Disconnect") { bridge.disconnect() }
                    } else {
                        Button("Connect to Windows") { bridge.connect() }.buttonStyle(.borderedProminent)
                    }
                    if bridge.connected { Button("Return Control to Mac") { bridge.returnControl() } }
                }
            } header: { Text("Pair Your Computers") } footer: {
                Text("Open the Windows ScreenBridge companion and use its current address and code. The code is used for this encrypted session and is never saved. Clipboard and files are not shared.")
            }
            Section {
                Picker("Control direction", selection: Binding(get: { bridge.direction }, set: bridge.setDirection)) {
                    Text("Both computers").tag(ScreenBridgeControlDirection.both)
                    Text("Mac controls Windows").tag(ScreenBridgeControlDirection.macToWindows)
                    Text("Windows controls Mac").tag(ScreenBridgeControlDirection.windowsToMac)
                }
            } header: { Text("Mouse & Keyboard") } footer: {
                Text("Both computers lets either mouse and keyboard cross to the other screen. Choose Windows controls Mac to use the PC’s mouse and keyboard on your Mac. This does not change the display arrangement. Windows must be connected and unlocked; the Mac must be unlocked too.")
            }
            Section {
                Picker("Windows is", selection: Binding(get: { bridge.side }, set: bridge.setSide)) {
                    Text("Right of Mac").tag(SBSide.right)
                    Text("Left of Mac").tag(SBSide.left)
                    Text("Above Mac").tag(SBSide.above)
                    Text("Below Mac").tag(SBSide.below)
                }
                Picker("Mac bridge display", selection: Binding(get: { bridge.macDisplay }, set: bridge.selectMac)) {
                    ForEach(bridge.macDisplays, id: \.id) { display in Text(display.name).tag(display.id) }
                }
                Picker("Windows bridge display", selection: Binding(get: { bridge.windowsDisplay }, set: bridge.selectWindows)) {
                    if bridge.windowsDisplays.isEmpty { Text("Connect to detect displays").tag("") }
                    ForEach(bridge.windowsDisplays, id: \.id) { display in Text(display.name).tag(display.id) }
                }.disabled(!bridge.connected || bridge.windowsDisplays.isEmpty)
            } header: { Text("Display Arrangement") } footer: {
                Text("Move through the selected display edge to switch computers. Control–Option–Escape returns control. Locking, sleeping, disconnecting or quitting stops sharing.")
            }
            Section {
                Button("Open Accessibility Settings…") { bridge.openPermissions("Privacy_Accessibility") }
                Button("Open Input Monitoring Settings…") { bridge.openPermissions("Privacy_ListenEvent") }
            } header: { Text("Mac Permissions") } footer: {
                Text("Notchscape needs Accessibility and Input Monitoring to share input. You control access in macOS Settings. Restart Notchscape after changing Input Monitoring. This feature does not unlock either computer.")
            }
            Section {
                Text("Windows companion testing is still in progress. A reported issue with control stopping when its window is minimized has not yet been verified as fixed.")
                    .foregroundStyle(.secondary)
            } header: { Text("Preview") }
        }
        .formStyle(.grouped)
    }
}
