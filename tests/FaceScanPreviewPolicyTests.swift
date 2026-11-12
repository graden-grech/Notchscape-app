import Foundation

@main struct FaceScanPreviewPolicyTests {
    static func main() {
        var checks = 0
        func check(_ value: Bool, _ name: String) { precondition(value, name); checks += 1 }
        let id = UUID()
        for (width, height) in [(640.0, 480.0), (1280, 720), (1920, 1080), (480, 640), (1, 1)] {
            let scale = FaceScanPreviewPolicy.previewScale(width: width, height: height)!
            check(width * scale <= 640 && height * scale <= 640 && scale <= 1, "Preview fits without dropping larger camera frames")
        }
        for value in [0.0, -1, .nan, .infinity, 20_000] {
            check(FaceScanPreviewPolicy.previewScale(width: value, height: 480) == nil, "Invalid preview dimensions refused")
        }
        for capture in [false, true] {
            for authorization in [false, true] {
                for unlocked in [false, true] {
                    for automatic in [false, true] {
                        let result = FaceScanPreviewPolicy.permits(session: id, currentSession: id,
                            capturing: capture, authorized: authorization, desktopUnlocked: unlocked,
                            automaticAttempt: automatic, timestamp: 100, now: 100.1)
                        check(result == (capture && authorization && unlocked && !automatic), "Preview cannot bypass a lifecycle gate")
                    }
                }
            }
        }
        for session in [nil, UUID()] as [UUID?] {
            check(!FaceScanPreviewPolicy.permits(session: id, currentSession: session,
                capturing: true, authorized: true, desktopUnlocked: true,
                automaticAttempt: false, timestamp: 100, now: 100), "Cancelled/replaced capture rejects queued frames")
        }
        for time in [-1.0, .nan, .infinity, 102.0] {
            check(!FaceScanPreviewPolicy.permits(session: id, currentSession: id,
                capturing: true, authorized: true, desktopUnlocked: true,
                automaticAttempt: false, timestamp: time, now: 100), "Invalid/future preview refused")
        }
        check(!FaceScanPreviewPolicy.permits(session: id, currentSession: id, capturing: true,
            authorized: true, desktopUnlocked: true, automaticAttempt: false,
            timestamp: 98, now: 100), "Stale frame refused")
        for (value, expected) in [(Double.nan, 0.0), (.infinity, 0.0), (-1, 0), (0.5, 0.5), (2, 1)] {
            check(FaceScanPreviewPolicy.progress(value) == expected, "Displayed progress stays finite and bounded")
        }
        print("PASS \(checks) camera preview lifecycle checks; no camera or person images")
    }
}
