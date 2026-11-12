import AppKit
import AVFoundation
import QuartzCore

@main struct FaceNativePreviewTests {
    @MainActor static func main() {
        var checks = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        // Empty layers only: no capture session, devices, permissions or person images.
        let first = FaceCameraPreviewSource(layer: AVCaptureVideoPreviewLayer())
        let second = FaceCameraPreviewSource(layer: AVCaptureVideoPreviewLayer())
        let view = FaceCameraPreviewHost(frame: CGRect(x: 0, y: 0, width: 416, height: 300))
        view.display(first)
        view.layout()
        check(first.layer.superlayer === view.layer, "Native preview is attached")
        check(first.layer.videoGravity == .resizeAspectFill, "Preview fills its viewport without distortion")
        for size in [CGSize(width: 416, height: 300), CGSize(width: 320, height: 240), CGSize(width: 452, height: 300)] {
            view.setFrameSize(size); view.layout()
            check(first.layer.bounds.size == size, "Mirrored preview resizes without frame/transform jumps")
            check(first.layer.position == CGPoint(x: size.width / 2, y: size.height / 2), "Preview stays centered")
            check(first.layer.affineTransform().a == -1 && first.layer.affineTransform().d == 1, "Exactly one selfie mirror")
        }
        view.display(second)
        check(first.layer.superlayer == nil && second.layer.superlayer === view.layer, "Session replacement detaches old preview")
        second.revoke()
        view.display(second)
        check(second.layer.superlayer == nil, "Revoked source cannot remain displayed")
        view.display(first)
        view.display(nil)
        check(first.layer.superlayer == nil, "Cancel/dismantle detaches native layer")
        first.revoke()
        view.display(first)
        check(first.layer.superlayer == nil, "Revocation is permanent")
        print("PASS \(checks) native preview checks; no camera/session/person images")
    }
}
