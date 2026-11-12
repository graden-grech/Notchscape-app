// Native preview hosting adapted from Glance and FaceUnlock (MIT).
// Copyright (c) 2026 Jonathan Zhou; Copyright (c) 2026 HasBrain.
// Full notices: Resources/FacePreviewNotices.txt.
import AppKit
@preconcurrency import AVFoundation
import SwiftUI

/// The capture queue configures the connection before publishing this handle.
/// Only the main actor hosts/layouts the layer; this handle never starts capture.
final class FaceCameraPreviewSource: @unchecked Sendable {
    let layer: AVCaptureVideoPreviewLayer
    private let lock = NSLock()
    private var revoked = false

    init(layer: AVCaptureVideoPreviewLayer) { self.layer = layer }
    var isValid: Bool { lock.lock(); defer { lock.unlock() }; return !revoked }
    func revoke() { lock.lock(); revoked = true; lock.unlock() }
}

struct FaceCameraPreviewView: NSViewRepresentable {
    let source: FaceCameraPreviewSource

    func makeNSView(context: Context) -> FaceCameraPreviewHost {
        let view = FaceCameraPreviewHost(frame: .zero)
        view.display(source)
        return view
    }
    func updateNSView(_ view: FaceCameraPreviewHost, context: Context) { view.display(source) }
    static func dismantleNSView(_ view: FaceCameraPreviewHost, coordinator: ()) { view.display(nil) }
}

final class FaceCameraPreviewHost: NSView {
    private var source: FaceCameraPreviewSource?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }

    func display(_ newSource: FaceCameraPreviewSource?) {
        let next = newSource?.isValid == true ? newSource : nil
        guard source !== next else { return }
        source?.layer.removeFromSuperlayer()
        source = next
        if let next {
            next.layer.videoGravity = .resizeAspectFill
            layer?.addSublayer(next.layer)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let source, source.isValid else { display(nil); return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // A mirrored layer's frame is undefined: position/bounds stay stable.
        source.layer.bounds = CGRect(origin: .zero, size: bounds.size)
        source.layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        source.layer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        CATransaction.commit()
    }
}
