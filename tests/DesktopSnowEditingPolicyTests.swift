import Foundation
import CoreGraphics

@main struct DesktopSnowEditingPolicyTests {
    static func main() {
        var session = DesktopSnowEditingSession()
        precondition(!session.isActive)
        precondition(!session.begin(eligible: false, now: 1))
        precondition(!session.begin(eligible: true, now: .nan))
        precondition(session.begin(eligible: true, now: 1))
        precondition(session.validate(eligible: true, now: 60))
        session.interact(now: 60)
        precondition(session.validate(eligible: true, now: 179))
        precondition(!session.validate(eligible: true, now: 181))
        precondition(session.begin(eligible: true, now: 200))
        precondition(!session.validate(eligible: false, now: 201))
        precondition(session.begin(eligible: true, now: 300))
        precondition(!session.validate(eligible: true, now: 299))
        precondition(session.begin(eligible: true, now: 400))
        session.end(); precondition(!session.isActive)
        let points = DesktopSnowEditingSession.samples(from: .zero, to: CGPoint(x: 100, y: 30), radius: 20)
        precondition(points.count <= 32 && points.last == CGPoint(x: 100, y: 30))
        precondition(points.allSatisfy { $0.x >= 0 && $0.x <= 100 && $0.y >= 0 && $0.y <= 30 })
        precondition(DesktopSnowEditingSession.samples(from: .zero, to: CGPoint(x: 50_000, y: 50_000), radius: 12).count == 32)
        precondition(DesktopSnowEditingSession.samples(from: CGPoint(x: CGFloat.nan, y: 0), to: .zero, radius: 20).isEmpty)
        precondition(DesktopSnowEditingSession.samples(from: .zero, to: .zero, radius: .infinity).isEmpty)
        print("PASS: snow editing eligibility, idle expiry, cancellation, monotonic clock and bounded stroke sampling")
    }
}
