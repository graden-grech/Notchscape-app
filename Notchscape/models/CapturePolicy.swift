import AppKit
import ImageIO
import UniformTypeIdentifiers

enum CaptureMarkupTool: String, CaseIterable, Identifiable {
    case arrow = "Arrow", text = "Text", redact = "Redact", crop = "Crop"
    var id: Self { self }
}
struct CaptureMark: Equatable {
    var tool: CaptureMarkupTool
    var start: CGPoint
    var end: CGPoint
    var text = ""
    var normalizedRect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x-end.x), height: abs(start.y-end.y)).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}
enum CaptureImagePolicy {
    static let maxBytes = 30_000_000
    static func preview(_ image: CGImage) -> CGImage? {
        let scale = min(1, 1600/Double(max(image.width, image.height)))
        let w = max(1, Int(Double(image.width)*scale)), h = max(1, Int(Double(image.height)*scale))
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high; context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h)); return context.makeImage()
    }
    static func load(_ url: URL, thumbnail: Int? = nil) -> CGImage? {
        guard url.isFileURL, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxBytes,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_384, height <= 16_384, Double(width)*Double(height) <= 40_000_000 else { return nil }
        // Apply EXIF orientation once. Exports contain pixels only, not source metadata.
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: thumbnail ?? max(width, height)] as CFDictionary)
    }
    static func render(_ image: CGImage, marks: [CaptureMark]) -> CGImage? {
        guard marks.count <= 200, image.width <= 16_384, image.height <= 16_384,
              Double(image.width)*Double(image.height) <= 40_000_000,
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let w = Double(image.width), h = Double(image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: min(1, max(0, p.x))*w, y: (1-min(1, max(0, p.y)))*h) }
        for mark in marks where mark.tool != .crop {
            guard [mark.start.x, mark.start.y, mark.end.x, mark.end.y].allSatisfy(\.isFinite) else { return nil }
            let a = point(mark.start), b = point(mark.end)
            switch mark.tool {
            case .redact:
                let r = mark.normalizedRect
                // Opaque destructive replacement, not a blur or a reversible layer.
                context.setFillColor(CGColor(gray: 0, alpha: 1))
                context.fill(CGRect(x: floor(r.minX*w), y: floor((1-r.maxY)*h), width: ceil(r.width*w)+1, height: ceil(r.height*h)+1))
            case .arrow:
                context.setStrokeColor(NSColor.systemRed.cgColor); context.setLineWidth(max(3, w/400)); context.setLineCap(.round)
                context.move(to: a); context.addLine(to: b); context.strokePath()
                let angle = atan2(b.y-a.y, b.x-a.x), length = max(12, w/80)
                context.move(to: CGPoint(x: b.x-length*cos(angle-0.5), y: b.y-length*sin(angle-0.5))); context.addLine(to: b)
                context.addLine(to: CGPoint(x: b.x-length*cos(angle+0.5), y: b.y-length*sin(angle+0.5))); context.strokePath()
            case .text:
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                String(mark.text.prefix(1000)).draw(at: a, withAttributes: [.font: NSFont.systemFont(ofSize: max(16, w/50), weight: .semibold), .foregroundColor: NSColor.white, .backgroundColor: NSColor.black])
                NSGraphicsContext.restoreGraphicsState()
            case .crop: break
            }
        }
        guard var rendered = context.makeImage() else { return nil }
        if let crop = marks.last(where: { $0.tool == .crop }) {
            let r = crop.normalizedRect
            guard r.width*w >= 2, r.height*h >= 2 else { return nil }
            guard let cropped = rendered.cropping(to: CGRect(x: r.minX*w, y: r.minY*h, width: r.width*w, height: r.height*h).integral) else { return nil }; rendered = cropped
        }
        return rendered
    }
    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), data.length <= 160_000_000 else { return nil }; return data as Data
    }
    static func isManagedFile(_ name: String) -> Bool {
        let prefix = "Notchscape-Capture-"
        guard name.hasPrefix(prefix), name.hasSuffix(".png") else { return false }
        return UUID(uuidString: String(name.dropFirst(prefix.count).dropLast(4))) != nil
    }
}
