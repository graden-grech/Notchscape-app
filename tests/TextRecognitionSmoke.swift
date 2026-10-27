import AppKit
import Vision

// A generated test image, not a screenshot of the user's screen.
@main
struct TextRecognitionSmoke {
    static func main() throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 240,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1000, height: 240).fill()
        ("Boring Notch Text Capture\nPrivate on-device recognition" as NSString).draw(
            in: NSRect(x: 30, y: 30, width: 940, height: 175),
            withAttributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])!
        let fixture = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/private/tmp/notch-ocr-fixture.png")
        try data.write(to: fixture)
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true; request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(url: fixture).perform([request])
        let result = request.results!.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        precondition(result.contains("Boring Notch Text Capture"))
        precondition(result.contains("Private on-device recognition"))
        print("PASS: Apple Vision recognizes the generated fixture without screen permission or network access")
    }
}
