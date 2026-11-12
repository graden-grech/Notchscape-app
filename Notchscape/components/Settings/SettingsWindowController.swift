//
//  SettingsWindowController.swift
//  Notchscape
//
//  Created by Alexander on 2025-06-14.
//

import AppKit
import SwiftUI
import Defaults
import Sparkle

/// Retains navigation requests before the first hosting view has mounted.
/// Sending only a notification can lose the first request at cold launch.
@MainActor
final class NotchSettingsNavigation: ObservableObject {
    static let shared = NotchSettingsNavigation()
    @Published private(set) var selection = "General"
    private init() {}
    func select(_ section: String) {
        guard NotchSettingsDestination.all.contains(where: { $0.id == section }),
              section != "Account" || AccountFeaturePolicy.enabled else { return }
        selection = section
    }
}

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private var updaterController: SPUStandardUpdaterController?
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        setupWindow()

        // AppKit restores the last usable frame and owns subsequent autosaving.
        // Configure this once; rebuilding the hosting view must not move a window.
        let frameName = NSWindow.FrameAutosaveName("NotchscapeSettingsWindow")
        if !window.setFrameUsingName(frameName) { window.center() }
        window.setFrameAutosaveName(frameName)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setUpdaterController(_ controller: SPUStandardUpdaterController) {
        self.updaterController = controller
        // Recreate the content view with the proper updater controller
        setupWindow()
    }
    
    private func setupWindow() {
        guard let window = window else { return }
        
        window.title = "Notchscape Settings"
        window.titlebarAppearsTransparent = true
        // Keep the native title visible so the active Settings destination can
        // participate in the unified titlebar instead of leaving the detail
        // pane without a heading.
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        // A real system toolbar gives traffic lights their native inset and
        // height. Do not draw content over the title bar or move button frames.
        let toolbar = NSToolbar(identifier: "NotchSettingsToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.minSize = NSSize(width: 760, height: 560)
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.animationBehavior = .documentWindow
        window.isMovableByWindowBackground = false
        
        // Make it behave like a regular app window with proper Spaces support
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        
        // Ensure proper window behavior
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false
        
        // Configure window to be a standard document-style window
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("NotchscapeSettingsWindow")
        
        // Create the SwiftUI content
        let settingsView = SettingsView(updaterController: updaterController)
        let hostingView = NSHostingView(rootView: settingsView)
        window.contentView = hostingView
        
        // Handle window closing
        window.delegate = self
    }
    
    func showWindow(section: String? = nil) {
        if let section { NotchSettingsNavigation.shared.select(section) }
        // If window is already visible, bring it to front properly
        if window?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            window?.orderFrontRegardless()
            window?.makeKeyAndOrderFront(nil)
            return
        }
        
        // Show the window with proper ordering
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        
        // Activate the app and ensure window gets focus
        NSApp.activate(ignoringOtherApps: true)
        
        // Force window to front after activation
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }
    
    override func close() {
        super.close()
        relinquishFocus()
    }
    
    private func relinquishFocus() {
        window?.orderOut(nil)
        
        // Dock visibility is owned by AppPresentationManager, not window focus.
    }
}

extension Notification.Name {
    static let notchSettingsSectionRequested = Notification.Name("NotchSettingsSectionRequested")
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        relinquishFocus()
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }
    
    func windowDidResignKey(_ notification: Notification) {
    }
    
}
