import AppKit
import CoreAudio
import Combine
import Defaults
import SwiftUI

struct AudioRoute: Identifiable { let id: AudioDeviceID; let uid: String; let name: String }

@MainActor
final class AudioRoutingManager: ObservableObject {
    static let shared = AudioRoutingManager()
    @Published private(set) var inputs: [AudioRoute] = []
    @Published private(set) var outputs: [AudioRoute] = []
    @Published private(set) var selectedInput: AudioDeviceID = 0
    @Published private(set) var inputMuted = false
    @Published private(set) var canMuteInput = false
    @Published private(set) var preferred: [String] = []
    @Published private(set) var message: String?
    private var observations = Set<AnyCancellable>()
    private var listener: AudioObjectPropertyListenerBlock?
    private var addresses: [AudioObjectPropertyAddress] = []
    private var muteListener: AudioObjectPropertyListenerBlock?
    private var muteDevice: AudioDeviceID = 0
    private init() {
        preferred = Array((UserDefaults.standard.stringArray(forKey: "audio.preferredOutputs") ?? []).filter { $0.count <= 2048 }.prefix(32))
        Defaults.publisher(.preferredAudioRouting).receive(on: RunLoop.main).sink { [weak self] _ in self?.configure() }.store(in: &observations)
        Defaults.publisher(.deviceControlsEnabled).receive(on: RunLoop.main).sink { [weak self] _ in self?.configure() }.store(in: &observations)
        WorkspaceModeManager.shared.$session.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.configure() }.store(in: &observations)
    }
    func stop() {
        removeMuteListener()
        if let listener { for var address in addresses { AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener) } }
        listener = nil; addresses = []
    }
    func configure() {
        stop(); guard Defaults[.deviceControlsEnabled], WorkspaceAccess.privateToolsAllowed else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] count, pointers in
            let hardwareChanged = (0..<Int(count)).contains { pointers[$0].mSelector == kAudioHardwarePropertyDevices }
            Task { @MainActor in self?.refresh(applyPreference: hardwareChanged) }
        }
        listener = block
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr { addresses.append(address) }
        }
        refresh(applyPreference: Defaults[.preferredAudioRouting])
    }
    func refresh(applyPreference: Bool = false) {
        guard Defaults[.deviceControlsEnabled], WorkspaceAccess.privateToolsAllowed else { return }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0, size <= 4096 else { inputs = []; outputs = []; return }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size)/MemoryLayout<AudioDeviceID>.size)
        guard ids.withUnsafeMutableBytes({ AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!) }) == noErr else { return }
        func routes(_ scope: AudioObjectPropertyScope) -> [AudioRoute] {
            ids.compactMap { id in
                var property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
                var bytes: UInt32 = 0
                guard AudioObjectGetPropertyDataSize(id, &property, 0, nil, &bytes) == noErr, bytes > 0 else { return nil }
                func string(_ selector: AudioObjectPropertySelector) -> String? {
                    // CoreAudio's UID/name properties return a retained CFObject.
                    // Read the raw reference first, then transfer ownership to ARC.
                    var value: Unmanaged<CFString>?; var count = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                    var property = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                    guard AudioObjectGetPropertyData(id, &property, 0, nil, &count, &value) == noErr else { return nil }
                    return value?.takeRetainedValue() as String?
                }
                guard let uid = string(kAudioDevicePropertyDeviceUID) else { return nil }
                return .init(id: id, uid: uid, name: string(kAudioObjectPropertyName) ?? "Audio device")
            }
        }
        inputs = routes(kAudioDevicePropertyScopeInput); outputs = routes(kAudioDevicePropertyScopeOutput)
        address.mSelector = kAudioHardwarePropertyDefaultInputDevice; size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var input: AudioDeviceID = 0
        if AudioObjectGetPropertyData(system, &address, 0, nil, &size, &input) == noErr { selectedInput = input }
        var mute = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        canMuteInput = input != 0 && AudioObjectHasProperty(input, &mute) && AudioObjectIsPropertySettable(input, &mute, &settable) == noErr && settable.boolValue
        var value: UInt32 = 0; size = UInt32(MemoryLayout<UInt32>.size)
        inputMuted = canMuteInput && AudioObjectGetPropertyData(input, &mute, 0, nil, &size, &value) == noErr && value != 0
        if muteDevice != input {
            removeMuteListener()
            if canMuteInput {
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in Task { @MainActor in self?.refresh() } }
                if AudioObjectAddPropertyListenerBlock(input, &mute, .main, block) == noErr { muteDevice = input; muteListener = block }
            }
        }
        if applyPreference, Defaults[.preferredAudioRouting], let route = preferred.compactMap({ uid in outputs.first { $0.uid == uid } }).first {
            setDefault(route.id, selector: kAudioHardwarePropertyDefaultOutputDevice)
        }
    }
    func selectInput(_ id: AudioDeviceID) { guard inputs.contains(where: { $0.id == id }) else { return }; setDefault(id, selector: kAudioHardwarePropertyDefaultInputDevice); refresh() }
    private func setDefault(_ id: AudioDeviceID, selector: AudioObjectPropertySelector) {
        guard WorkspaceAccess.privateToolsAllowed, Defaults[.deviceControlsEnabled] else { return }
        var value = id
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value) != noErr { message = "macOS couldn’t change the audio device." }
        else { message = nil }
    }
    func muteInput(_ value: Bool) {
        guard canMuteInput, WorkspaceAccess.privateToolsAllowed, Defaults[.deviceControlsEnabled] else { return }
        var mute: UInt32 = value ? 1 : 0
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectSetPropertyData(selectedInput, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &mute) != noErr { message = "This device couldn’t change hardware mute." }
        refresh()
    }
    func togglePreferred(_ route: AudioRoute) {
        guard WorkspaceAccess.privateToolsAllowed else { return }
        if preferred.contains(route.uid) { preferred.removeAll { $0 == route.uid } }
        else if preferred.count < 32 { preferred.append(route.uid) }
        UserDefaults.standard.set(preferred, forKey: "audio.preferredOutputs")
    }
    func removePreferred(_ uid: String) {
        guard WorkspaceAccess.privateToolsAllowed else { return }
        preferred.removeAll { $0 == uid }; UserDefaults.standard.set(preferred, forKey: "audio.preferredOutputs")
    }
    private func removeMuteListener() {
        if let muteListener {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(muteDevice, &address, .main, muteListener)
        }
        muteDevice = 0; muteListener = nil
    }
    func move(_ uid: String, by delta: Int) {
        guard WorkspaceAccess.privateToolsAllowed, let index = preferred.firstIndex(of: uid), preferred.indices.contains(index+delta) else { return }
        preferred.swapAt(index, index+delta); UserDefaults.standard.set(preferred, forKey: "audio.preferredOutputs")
    }
}

struct AudioRoutingControlsView: View {
    @ObservedObject private var routing = AudioRoutingManager.shared
    @Default(.preferredAudioRouting) private var automatic
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Audio input", selection: Binding(get: { routing.selectedInput }, set: { routing.selectInput($0) })) { ForEach(routing.inputs) { Text($0.name).tag($0.id) } }.disabled(routing.inputs.isEmpty)
                Toggle("Hardware input mute", isOn: Binding(get: { routing.inputMuted }, set: { routing.muteInput($0) })).disabled(!routing.canMuteInput)
            }
            if !routing.canMuteInput { Text("Selected input does not expose a writable hardware mute. No fake software mute is applied.").font(.caption2).foregroundStyle(.secondary) }
            DisclosureGroup("Preferred Audio Outputs") {
                Toggle("Choose preferred output when devices change", isOn: $automatic)
                ForEach(routing.preferred, id: \.self) { uid in
                    HStack {
                        Text(routing.outputs.first { $0.uid == uid }?.name ?? "Disconnected preferred output")
                        Spacer(); Button { routing.move(uid, by: -1) } label: { Image(systemName: "arrow.up") }.help("Move up")
                        Button { routing.move(uid, by: 1) } label: { Image(systemName: "arrow.down") }.help("Move down")
                        Button("Remove") { routing.removePreferred(uid) }
                    }.font(.caption)
                }
                ForEach(routing.outputs.filter { !routing.preferred.contains($0.uid) }) { route in Button("Add \(route.name)") { routing.togglePreferred(route) } }
                Text("Off by default. Uses stable device IDs and hot-plug events; never changes an unavailable device or records audio.").font(.caption2).foregroundStyle(.secondary)
            }
            if let message = routing.message { Text(message).font(.caption).foregroundStyle(.orange) }
        }.toggleStyle(CompactSwitchToggleStyle()).onAppear { routing.configure() }
    }
}
