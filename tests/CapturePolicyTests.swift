import AppKit
import ImageIO
import CoreImage
import Vision

@main struct CapturePolicyTests {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) { precondition(value(), name); checks += 1 }
        let context = CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
        let original = context.makeImage()!
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--write-fixture" {
            try CaptureImagePolicy.png(original)!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .withoutOverwriting)
        }
        let redact = CaptureMark(tool: .redact, start: .init(x: 0.2,y: 0.2), end: .init(x: 0.8,y: 0.8))
        let flattened = CaptureImagePolicy.render(original, marks: [redact])!
        let bitmap = NSBitmapImageRep(cgImage: flattened)
        let hidden = bitmap.colorAt(x: 50, y: 40)!.usingColorSpace(.deviceRGB)!
        check(hidden.redComponent < 0.01 && hidden.greenComponent < 0.01 && hidden.blueComponent < 0.01 && hidden.alphaComponent > 0.99, "redaction replaces pixels opaquely")
        check(bitmap.colorAt(x: 5,y: 5)!.usingColorSpace(.deviceRGB)!.redComponent > 0.9, "outside kept")
        check(NSBitmapImageRep(cgImage: original).colorAt(x: 50,y: 40)!.usingColorSpace(.deviceRGB)!.redComponent > 0.9, "original unchanged")
        let crop = CaptureMark(tool: .crop, start: .init(x: 0.1,y: 0.1), end: .init(x: 0.6,y: 0.6))
        let cropped = CaptureImagePolicy.render(original, marks: [redact,crop])!
        check(cropped.width == 50 && cropped.height == 40, "pixel crop dimensions")
        check(CaptureImagePolicy.render(original, marks: [.init(tool: .crop, start: .zero, end: .zero)]) == nil, "empty crop rejected")
        check(CaptureImagePolicy.render(original, marks: [.init(tool: .arrow, start: .init(x: CGFloat.nan,y: 0), end: .zero)]) == nil, "nonfinite marks rejected")
        check(CaptureImagePolicy.render(original, marks: Array(repeating: redact, count: 201)) == nil, "mark limit")
        let png = CaptureImagePolicy.png(flattened)!
        let source = CGImageSourceCreateWithData(png as CFData, nil)!
        let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
        let exif = metadata[kCGImagePropertyExifDictionary] as? [CFString: Any]
        check(metadata[kCGImagePropertyGPSDictionary] == nil && exif?[kCGImagePropertyExifDateTimeOriginal] == nil && exif?[kCGImagePropertyExifUserComment] == nil, "private EXIF and GPS absent; encoder may add pixel dimensions")
        check(CaptureImagePolicy.isManagedFile("Notchscape-Capture-\(UUID().uuidString).png"), "managed filename")
        check(!CaptureImagePolicy.isManagedFile("../personal.png"), "unmanaged file rejected")
        check(!CaptureImagePolicy.isManagedFile("Notchscape-Capture-not-a-uuid.png"), "invalid ID rejected")
        let filter = CIFilter(name: "CIQRCodeGenerator")!; filter.setValue(Data("Notchscape harmless QR fixture".utf8), forKey: "inputMessage")
        let image = CIContext().createCGImage(filter.outputImage!.transformed(by: .init(scaleX: 12,y: 12)), from: filter.outputImage!.extent.applying(.init(scaleX: 12,y: 12)))!
        let request = VNDetectBarcodesRequest(); try VNImageRequestHandler(cgImage: image).perform([request])
        check(request.results?.contains { $0.payloadStringValue == "Notchscape harmless QR fixture" } == true, "local Vision QR fixture")
        print("PASS \(checks) capture and QR checks")
    }
}
