import AppKit
import Combine
import Darwin
import IOKit.ps
import Security

/// This companion owns only its own application tile in the real macOS Dock.
/// The main app's activation policy, saved Dock items and permissions are never
/// changed. Its scoped IPC has three bounded presentation values, no commands
/// that access documents, credentials, cameras, other apps or the network.
@MainActor
final class DockWidgetController: NSObject, NSApplicationDelegate {
    private let configuration: DockWidgetLaunchConfiguration
    private var widget: DockWidgetKind
    private var privacy = DockWidgetPrivacy()
    private let tileView = DockWidgetTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    private var subscriptions = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private var ownerSource: DispatchSourceProcess?
    private var powerSource: CFRunLoopSource?
    private var battery: DockWidgetBattery?
    private var tileMenu: NSMenu?
    private var widgetItems: [(DockWidgetKind, NSMenuItem)] = []
    private var openItems: [NSMenuItem] = []
    private var stopped = false
    private var removalPending = false

    init(configuration: DockWidgetLaunchConfiguration) {
        self.configuration = configuration
        widget = configuration.widget
        super.init()
    }

    static func validOwner(_ pid: Int32) -> Bool {
        guard pid > 1, pid != getpid(), getuid() == geteuid() else { return false }
        var before = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &before, size) == size,
              before.pbi_pid == UInt32(pid), before.pbi_uid == getuid(), before.pbi_ruid == getuid(),
              before.pbi_start_tvsec > 0,
              NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == DockWidgetPolicy.mainBundleID else { return false }
        var requirement: SecRequirement?
        var guest: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        guard SecRequirementCreateWithString(DockWidgetPolicy.ownerRequirement as CFString, [], &requirement) == errSecSuccess,
              let requirement, SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess,
              let guest, SecCodeCheckValidity(guest, [], requirement) == errSecSuccess else { return false }
        var after = proc_bsdinfo()
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &after, size) == size &&
            before.pbi_start_tvsec == after.pbi_start_tvsec && before.pbi_start_tvusec == after.pbi_start_tvusec &&
            after.pbi_pid == UInt32(pid) && after.pbi_uid == getuid() && after.pbi_ruid == getuid()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Self.validOwner(configuration.ownerPID) else { shutdown(); return }
        privacy.sessionEligible = sessionEligible
        privacy.locked = !privacy.sessionEligible
        privacy.awake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
        // Presenting remains true until the owner's first configuration arrives.
        // A ready event lets it re-send if launch completion raced our observers.
        buildMenus()
        tileView.autoresizingMask = [.width, .height]
        NSApp.dockTile.contentView = tileView
        NSApp.dockTile.showsApplicationBadge = false
        displayTile(force: true)
        observeLifecycle()
        let source = DispatchSource.makeProcessSource(identifier: configuration.ownerPID, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }; privacy.ownerAlive = false; shutdown()
            }
        }
        ownerSource = source; source.resume()
        // Close the creation race between owner validation and exit monitoring.
        guard Self.validOwner(configuration.ownerPID) else { shutdown(); return }
        reconcile()
        send(event: "ready")
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? { updateMenus(); return tileMenu }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openWorkspace(nil)
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !stopped else { return .terminateNow }
        requestRemoval()
        // The owner persists disabled before acknowledging with quit. This
        // avoids racing a removed notification against didTerminateApplication.
        return .terminateCancel
    }

    private var sessionEligible: Bool {
        DockWidgetPolicy.eligibleSession(CGSessionCopyCurrentDictionary() as? [String: Any], uid: getuid(), euid: geteuid())
    }

    private func observeLifecycle() {
        let distributed = DistributedNotificationCenter.default()
        distributed.publisher(for: .init(DockWidgetPolicy.controlName), object: configuration.controlToken as NSString)
            .receive(on: RunLoop.main).sink { [weak self] notification in
                guard let self, !stopped, let command = DockWidgetControl.parse(notification.userInfo) else { return }
                switch command {
                case .quit: shutdown()
                case let .configure(next, presenting):
                    guard !removalPending else { return }
                    widget = next; privacy.presenting = presenting; reconcile()
                }
            }.store(in: &subscriptions)
        distributed.publisher(for: .init("com.apple.screenIsLocked"))
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.privacy.locked = true; self?.reconcile() }.store(in: &subscriptions)
        distributed.publisher(for: .init("com.apple.screenIsUnlocked"))
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self, sessionEligible else { return }; privacy.locked = false; reconcile()
            }.store(in: &subscriptions)
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.privacy.awake = false; $0.reconcile() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.privacy.awake = false; $0.reconcile() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.refreshWake() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.refreshWake() }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.privacy.sessionActive = false; $0.reconcile() }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.privacy.sessionActive = true; $0.reconcile() }
        observe(NotificationCenter.default, .NSSystemClockDidChange) { $0.reconcile() }
        observe(NotificationCenter.default, .NSSystemTimeZoneDidChange) { $0.reconcile() }
        observe(NotificationCenter.default, NSLocale.currentLocaleDidChangeNotification) { $0.reconcile() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { $0.displayTile(force: true) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping @MainActor (DockWidgetController) -> Void) {
        center.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self, !stopped else { return }; action(self)
        }.store(in: &subscriptions)
    }

    private func refreshWake() {
        privacy.awake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
        reconcile()
    }

    private func reconcile() {
        guard !stopped else { return }
        refreshTask?.cancel(); refreshTask = nil
        privacy.sessionEligible = sessionEligible
        if !privacy.permitsContent {
            stopPowerObservation(); battery = nil; displayTile(); updateMenus(); return
        }
        if widget == .battery {
            startPowerObservation(); readBattery()
        } else { stopPowerObservation(); battery = nil }
        displayTile(); updateMenus()
        guard let delay = DockWidgetPolicy.nextRefresh(widget: widget, now: Date()) else { return }
        refreshTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !Task.isCancelled, !stopped else { return }; reconcile()
        }
    }

    private func startPowerObservation() {
        guard powerSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let controller = Unmanaged<DockWidgetController>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak controller] in
                guard let controller, !controller.stopped, controller.widget == .battery else { return }
                guard controller.privacy.permitsContent, controller.sessionEligible else { controller.reconcile(); return }
                controller.readBattery(); controller.displayTile()
            }
        }, context)?.takeRetainedValue() else { return }
        powerSource = source; CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func stopPowerObservation() {
        if let source = powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes); CFRunLoopSourceInvalidate(source)
        }
        powerSource = nil
    }

    private func readBattery() {
        battery = nil
        guard privacy.permitsContent, widget == .battery,
              let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in sources.prefix(16) {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? NSNumber,
                  let maximum = description[kIOPSMaxCapacityKey] as? NSNumber else { continue }
            battery = DockWidgetBattery.reading(current: current.doubleValue, maximum: maximum.doubleValue,
                charging: description[kIOPSIsChargingKey] as? Bool == true,
                onACPower: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
            return
        }
    }

    private func displayTile(force: Bool = false) {
        let next = DockWidgetSnapshot.make(widget: widget, privacy: privacy, now: Date(), battery: battery)
        guard force || tileView.snapshot != next else { return }
        tileView.snapshot = next
        NSApp.dockTile.display()
    }

    private func buildMenus() {
        let menu = NSMenu(title: "Notchscape Dock Widget")
        menu.autoenablesItems = false
        appendControls(to: menu, keyboard: false); tileMenu = menu
        let bar = NSMenu()
        let application = NSMenuItem()
        let appMenu = NSMenu(title: "Notchscape Dock Widget")
        appMenu.autoenablesItems = false
        appendControls(to: appMenu, keyboard: true); application.submenu = appMenu
        bar.addItem(application); NSApp.mainMenu = bar
        updateMenus()
    }

    private func appendControls(to menu: NSMenu, keyboard: Bool) {
        let open = NSMenuItem(title: "Open Workspace", action: #selector(openWorkspace(_:)), keyEquivalent: "")
        open.target = self; menu.addItem(open); openItems.append(open)
        menu.addItem(.separator())
        for kind in DockWidgetKind.allCases {
            let item = NSMenuItem(title: kind.title, action: #selector(selectWidget(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = kind.rawValue
            menu.addItem(item); widgetItems.append((kind, item))
        }
        menu.addItem(.separator())
        let remove = NSMenuItem(title: "Remove Dock Widget", action: #selector(removeWidget(_:)), keyEquivalent: keyboard ? "q" : "")
        remove.target = self; menu.addItem(remove)
    }

    private func updateMenus() {
        for (kind, item) in widgetItems { item.state = widget == kind ? .on : .off }
        for item in openItems { item.isEnabled = privacy.permitsContent }
    }

    @objc private func openWorkspace(_ sender: Any?) {
        guard !stopped, !removalPending, privacy.permitsContent, sessionEligible else { return }; send(event: "openWorkspace")
    }
    @objc private func selectWidget(_ sender: NSMenuItem) {
        guard !stopped, !removalPending, let raw = sender.representedObject as? String, let kind = DockWidgetKind(rawValue: raw) else { return }
        widget = kind; reconcile(); send(event: "selectedWidget", widget: kind)
    }
    @objc private func removeWidget(_ sender: Any?) { requestRemoval() }

    private func requestRemoval() {
        guard !stopped, !removalPending else { return }
        removalPending = true; privacy.presenting = true; reconcile()
        send(event: "removed")
        // No deadline races the owner's acknowledgement. Its process-exit
        // source still terminates us if the main app quits or crashes.
    }

    private func send(event: String, widget: DockWidgetKind? = nil) {
        var info: [String: String] = ["event": event]
        if let widget { info["widget"] = widget.rawValue }
        DistributedNotificationCenter.default().postNotificationName(.init(DockWidgetPolicy.eventName),
            object: configuration.controlToken, userInfo: info, deliverImmediately: true)
    }

    private func shutdown() {
        guard !stopped else { return }; stopped = true
        privacy.ownerAlive = false
        refreshTask?.cancel(); refreshTask = nil
        stopPowerObservation(); battery = nil
        subscriptions.removeAll(); ownerSource?.cancel(); ownerSource = nil
        displayTile(); NSApp.dockTile.contentView = nil
        NSApp.terminate(nil)
    }
}
