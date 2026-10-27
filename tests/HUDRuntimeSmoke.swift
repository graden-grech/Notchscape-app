import Foundation
import CoreGraphics

// Run while HUD replacement is enabled. Reads event-tap metadata only;
// it never sends key events, captures input, or changes permissions.
guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]) else {
    fputs("Usage: swift tests/HUDRuntimeSmoke.swift running-app-pid\n", stderr)
    exit(2)
}
var count: UInt32 = 0
guard CGGetEventTapList(0, nil, &count) == .success else {
    fputs("FAIL: cannot query event-tap metadata\n", stderr)
    exit(1)
}
var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
let result = taps.withUnsafeMutableBufferPointer { CGGetEventTapList(count, $0.baseAddress, &count) }
guard result == .success else { exit(1) }
let mediaTaps = taps.prefix(Int(count)).filter {
    $0.tappingProcess == pid && ($0.eventsOfInterest & (1 << 14)) != 0
}
guard mediaTaps.count == 1, mediaTaps[0].enabled else {
    fputs("FAIL: expected exactly one enabled media-key interceptor for this app\n", stderr)
    exit(1)
}
print("PASS: exactly one enabled media-key interceptor for PID \(pid)")
