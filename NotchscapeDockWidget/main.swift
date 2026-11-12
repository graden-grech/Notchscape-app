import AppKit
import Darwin

// Direct Process launch only: never create NSApplication or register a Dock
// tile for the independent, event-driven preference recovery guardian.
if CommandLine.arguments.dropFirst().first == DockVisibilityPolicy.guardianFlag {
    DockVisibilityGuardian.run(arguments: Array(CommandLine.arguments.dropFirst()))
}

// No command shell, URL handler, login item or self-registration. The signed
// main app explicitly launches this embedded companion with a bounded config.
guard let configuration = DockWidgetLaunchConfiguration.parse(Array(CommandLine.arguments.dropFirst())),
      DockWidgetController.validOwner(configuration.ownerPID) else {
    fputs("Notchscape Dock Widget requires its running signed owner and a valid configuration.\n", stderr)
    exit(EXIT_FAILURE)
}
let application = NSApplication.shared
let controller = DockWidgetController(configuration: configuration)
application.delegate = controller
application.setActivationPolicy(.regular)
application.run()
