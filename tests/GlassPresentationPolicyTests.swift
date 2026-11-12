import Foundation

@main
struct GlassPresentationPolicyTests {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        for mask in 0..<32 {
            let policy = GlassPresentationPolicy(supportsNativeGlass: mask & 1 != 0,
                reduceTransparency: mask & 2 != 0, increasedContrast: mask & 4 != 0,
                lowImpact: mask & 8 != 0, reduceMotion: mask & 16 != 0)
            if policy.reduceTransparency || policy.increasedContrast || policy.lowImpact {
                check(policy.usesOpaqueSurfaces && !policy.usesNativeGlass, "Access/performance overrides never leave a translucent glass surface")
            }
            if !policy.supportsNativeGlass { check(!policy.usesNativeGlass, "Older macOS never enters the native glass branch") }
            if policy.reduceMotion || policy.lowImpact || policy.reduceTransparency {
                check(!policy.allowsDecorativeMotion, "Explicit access/performance choices remove decorative motion")
            }
            check(!(policy.usesNativeGlass && policy.usesOpaqueSurfaces), "Glass and opaque choices cannot conflict")
        }
        let standard = GlassPresentationPolicy(supportsNativeGlass: true, reduceTransparency: false,
            increasedContrast: false, lowImpact: false, reduceMotion: false)
        check(standard.usesNativeGlass && standard.allowsDecorativeMotion, "Normal supported desktop gets native responsive glass")
        var reducedMotion = standard; reducedMotion.reduceMotion = true
        check(reducedMotion.usesNativeGlass && !reducedMotion.allowsDecorativeMotion, "Reduce Motion keeps readable glass without bounce")
        for request in [-Double.infinity, Double.infinity, Double.nan] {
            check(GlassPresentationPolicy.groupingSpacing(request) == 4, "Invalid spacing has a stable bounded default")
            check(GlassPresentationPolicy.controlDiameter(request) == 30, "Invalid control size has the original compact default")
        }
        for request in stride(from: -100.0, through: 100, by: 0.5) {
            check((0...4).contains(GlassPresentationPolicy.groupingSpacing(request)), "Containers cannot merge unrelated controls through large spacing")
            check((24...44).contains(GlassPresentationPolicy.controlDiameter(request)), "Controls stay within compact native bounds")
        }
        check(GlassPresentationPolicy.controlDiameter(30) == 30 && GlassPresentationPolicy.controlDiameter(40) == 40,
              "Header and large music button measurements stay unchanged")
        print("PASS \(checks) glass rendering, accessibility, motion and control-bound checks")
    }
}
