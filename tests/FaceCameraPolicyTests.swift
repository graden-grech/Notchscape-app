import Foundation
import CoreGraphics
import CoreVideo
import CoreImage
import ImageIO

@main struct FaceCameraPolicyTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a-b) < 0.00001 }
        let configuration = FaceCameraConfiguration()!
        let previewPipeline = FaceCameraPipeline(model: nil, onEvent: { _ in })
        for (width, height, expectedWidth, expectedHeight) in [(640, 480, 640, 480), (1280, 720, 640, 360), (1920, 1080, 640, 360), (480, 640, 480, 640)] {
            let synthetic = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.7))
                .cropped(to: CGRect(x: 10, y: 20, width: width, height: height))
            let analysis = previewPipeline.analysisImage(from: synthetic)
            check(analysis?.extent.width == CGFloat(expectedWidth) && analysis?.extent.height == CGFloat(expectedHeight),
                  "HD camera input stays bounded for recognition independently of native preview")
        }
        check(FaceCameraConfiguration(minimumFrameInterval: .nan) == nil, "nonfinite frame interval")
        check(FaceCameraConfiguration(minimumFrameInterval: 0.1) == nil, "high-frequency capture forbidden")
        check(FaceCameraConfiguration(minimumFacePixels: 100) == nil, "face must cover model input")
        check(FaceCameraConfiguration(maximumSessionDuration: 100) == nil, "capture duration bounded")
        check(configuration.acceptsFace(.init(x: 0.1, y: 0.1, width: 0.2, height: 0.25), imageSize: .init(width: 640, height: 480)), "adequately sized face")
        check(!configuration.acceptsFace(.init(x: 0.1, y: 0.1, width: 0.1, height: 0.1), imageSize: .init(width: 640, height: 480)), "tiny face rejected")
        check(!configuration.acceptsFace(.init(x: -0.1, y: 0, width: 0.5, height: 0.5), imageSize: .init(width: 640, height: 480)), "offscreen face rejected")
        check(!configuration.acceptsFace(.infinite, imageSize: .init(width: 640, height: 480)), "infinite bounds rejected")
        check(!configuration.acceptsFace(.init(x: CGFloat.nan, y: 0, width: 0.5, height: 0.5), imageSize: .init(width: 640, height: 480)), "NaN bounds rejected")
        check(!configuration.acceptsFace(.init(x: 0, y: 0, width: 0.5, height: 0.5), imageSize: .init(width: CGFloat.infinity, height: 480)), "invalid dimensions rejected")
        let center = FaceCameraPose(yaw: 0, pitch: 0, roll: 0)!
        let left = FaceCameraPose(yaw: -0.4, pitch: 0, roll: 0)!
        let right = FaceCameraPose(yaw: 0.4, pitch: 0, roll: 0)!
        check(FaceCameraPose(yaw: .nan, pitch: 0, roll: 0) == nil, "nonfinite pose rejected")
        check(FaceCameraPose(yaw: 2, pitch: 0, roll: 0) == nil, "out of range pose rejected")
        check(!FaceCameraPose(yaw: 0, pitch: 0.5, roll: 0)!.permitsAlignment, "excessive pitch gated")
        var challenge = FaceHeadMovementChallenge(direction: .left, issuedAt: 10)!
        check(challenge.observe(pose: left, at: 10) == .waitingForCenter, "cannot begin already turned")
        check(challenge.observe(pose: center, at: 10.35) == .waitingForCenter, "one center frame insufficient")
        check(challenge.observe(pose: center, at: 10.7) == .turn(.left), "center dwell prompts chosen turn")
        check(challenge.observe(pose: right, at: 11.05) == .turn(.left), "opposite turn does not pass")
        check(challenge.observe(pose: left, at: 11.4) == .turn(.left), "one turn frame insufficient")
        check(challenge.observe(pose: left, at: 11.75) == .returnToCenter, "turn dwell completed")
        check(challenge.observe(pose: center, at: 12.1) == .returnToCenter, "one return frame insufficient")
        check(challenge.observe(pose: center, at: 12.45) == .completed, "center-turn-center sequence completed")
        check(challenge.observe(pose: nil, at: 12.8) == .waitingForCenter, "face loss invalidates completion")
        check(challenge.observe(pose: center, at: 22) == .expired, "challenge deadline enforced")
        var stale = FaceHeadMovementChallenge(direction: .right, issuedAt: 0)!
        _ = stale.observe(pose: center, at: 0); _ = stale.observe(pose: center, at: 0.35)
        check(stale.observe(pose: right, at: 2) == .waitingForCenter, "long frame gap resets continuity")
        _ = stale.observe(pose: center, at: 2.35); _ = stale.observe(pose: center, at: 2.7)
        check(stale.observe(pose: right, at: 2.7) == .waitingForCenter, "duplicate timestamps cannot advance")
        check(FaceHeadMovementChallenge(direction: .left, issuedAt: .infinity) == nil, "invalid issue time")
        check(FaceHeadMovementChallenge(direction: .left, issuedAt: 0, duration: 30) == nil, "unbounded challenge rejected")
        let canonical = FaceAlignmentPolicy.referencePoints
        let identity = FaceAlignmentPolicy.similarityTransform(source: canonical)!
        for point in canonical {
            let transformed = point.applying(identity)
            check(near(point.x, transformed.x) && near(point.y, transformed.y), "identity alignment")
        }
        let inputTransform = CGAffineTransform(scaleX: 2.5, y: 2.5).rotated(by: 0.15).translatedBy(x: 80, y: 40)
        let source = canonical.map { $0.applying(inputTransform) }
        let correction = FaceAlignmentPolicy.similarityTransform(source: source)!
        for (point, expected) in zip(source, canonical) {
            let transformed = point.applying(correction)
            check(near(transformed.x, expected.x) && near(transformed.y, expected.y), "known scale/rotation/translation recovered")
        }
        check(FaceAlignmentPolicy.similarityTransform(source: Array(repeating: .zero, count: 5)) == nil, "degenerate landmarks rejected")
        check(FaceAlignmentPolicy.similarityTransform(source: canonical.reversed()) == nil, "reversed landmark identity rejected")
        check(FaceAlignmentPolicy.similarityTransform(source: [.init(x: CGFloat.nan, y: 0)] + Array(canonical.dropFirst())) == nil, "NaN landmarks rejected")
        check(FaceAlignmentPolicy.similarityTransform(source: canonical.map { .init(x: 112-$0.x, y: $0.y) }) == nil, "mirroring cannot silently change identity")
        let pixels = try makePixels { x, y in (UInt8(x*2), UInt8(y*2), 64) }
        let tensor = try CoreMLFaceEmbeddingModel.rawRGBTensor(from: pixels)
        check(tensor.shape.map(\.intValue) == [1,3,112,112], "model input shape")
        check(tensor[[0,0,30,50]].floatValue == 100, "red plane raw byte value")
        check(tensor[[0,1,30,50]].floatValue == 60, "green plane raw byte value")
        check(tensor[[0,2,30,50]].floatValue == 64, "blue plane raw byte value")
        check(tensor[[0,0,111,111]].floatValue == 222, "padded pixel rows and final pixel")
        let context = CIContext(options: [.cacheIntermediates: false])
        func rendered(_ image: CIImage) throws -> CVPixelBuffer {
            var result: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault, Int(image.extent.width), Int(image.extent.height),
                kCVPixelFormatType_32BGRA, nil, &result) == kCVReturnSuccess, let result else { throw FaceEmbeddingModelError.invalidPixels }
            context.render(image, to: result, bounds: image.extent, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return result
        }
        // The exact pipeline orientation path round-trips all eight EXIF
        // orientations. Fixtures are generated pixels, never camera images.
        let orientations: [CGImagePropertyOrientation] = [.up,.down,.left,.right,.upMirrored,.downMirrored,.leftMirrored,.rightMirrored]
        let inverse: [CGImagePropertyOrientation] = [.up,.down,.right,.left,.upMirrored,.downMirrored,.leftMirrored,.rightMirrored]
        let upright = FaceCameraPipeline.uprightImage(from: pixels, orientation: .up)
        let baseline = try CoreMLFaceEmbeddingModel.rawRGBTensor(from: rendered(upright))
        for (orientation, undo) in zip(orientations, inverse) {
            let oriented = FaceCameraPipeline.uprightImage(from: pixels, orientation: orientation)
            check(oriented.extent.origin == .zero && oriented.extent.size == .init(width:112,height:112), "orientation has finite normalized extent")
            let roundTrip = oriented.oriented(undo)
            let normalized = roundTrip.transformed(by: .init(translationX:-roundTrip.extent.minX,y:-roundTrip.extent.minY))
            let restored = try CoreMLFaceEmbeddingModel.rawRGBTensor(from: rendered(normalized))
            check((0..<baseline.count).allSatisfy { abs(baseline[$0].floatValue-restored[$0].floatValue) <= 1 }, "orientation/mirror round trip preserves channels")
        }
        let flat = try makePixels { _, _ in (128,128,128) }
        check(!FaceCameraPipeline.quality(of: flat, facePixelSize: .init(width: 112,height: 112), confidence: 1).isUsable, "flat fixture fails texture quality")
        let black = try makePixels { _, _ in (0,0,0) }
        check(!FaceCameraPipeline.quality(of: black, facePixelSize: .init(width: 112,height: 112), confidence: 1).isUsable, "black fixture fails exposure quality")
        let pattern = try makePixels { x, y in let v: UInt8 = (x+y)%2 == 0 ? 64 : 192; return (v,v,v) }
        check(FaceCameraPipeline.quality(of: pattern, facePixelSize: .init(width: 112,height: 112), confidence: 1).isUsable, "synthetic texture passes image heuristics")
        check(!FaceCameraPipeline.quality(of: pattern, facePixelSize: .init(width: 112,height: 112), confidence: 0.2).isUsable, "low detection confidence fails")
        check(CoreMLFaceEmbeddingModel.prototypeSchema.dimension == 128, "verified dimension")
        if let package = ProcessInfo.processInfo.environment["FACE_CAMERA_MODEL_PACKAGE"],
           let referenceFile = ProcessInfo.processInfo.environment["FACE_CAMERA_SYNTHETIC_REFERENCE"] {
            let model = try CoreMLFaceEmbeddingModel(verifiedSFacePackageAt: URL(fileURLWithPath: package))
            let embedding = try model.embedding(from: pixels)
            let reference = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: referenceFile))) as! [String: Any]
            let values = reference["normalizedEmbedding"] as! [Double]
            check(embedding.values.count == 128 && embedding.schema == model.schema, "native model typed schema")
            let error = zip(embedding.values, values).map { pow(Double($0)-$1,2) }.reduce(0,+).squareRoot()
            check(error < 0.0001, "native BGRA-RGB/CoreML parity with ONNX synthetic reference")
            let squared = embedding.values.reduce(0.0) { $0 + Double($1)*Double($1) }
            check(abs(squared-1) < 0.00001, "native embedding normalized")
            print("Native synthetic parity L2 error: \(error)")
        }
        // Explicitly exercise unavailable-model failure. The start guard returns
        // before camera authorization/discovery/setup, so this never opens input.
        let events = LockedEvents()
        let eventQueue = DispatchQueue(label: "FaceCameraTests.events")
        let pipeline = FaceCameraPipeline(model: nil, eventQueue: eventQueue) { events.append($0) }
        let session = pipeline.start()
        check(events.done.wait(timeout: .now()+3) == .success, "model-unavailable event delivered")
        check(events.failedID == session, "unavailable model fails closed before camera access")
        pipeline.stop()
        print("PASS \(checks) face camera/alignment/adapter checks; no camera or permission request")
    }

    static func makePixels(_ color: (Int, Int) -> (UInt8, UInt8, UInt8)) throws -> CVPixelBuffer {
        var pixels: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault,112,112,kCVPixelFormatType_32BGRA,nil,&pixels) == kCVReturnSuccess,
              let pixels, CVPixelBufferLockBaseAddress(pixels, []) == kCVReturnSuccess else { throw FaceEmbeddingModelError.invalidPixels }
        defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
        let base = CVPixelBufferGetBaseAddress(pixels)!, stride = CVPixelBufferGetBytesPerRow(pixels)
        for y in 0..<112 {
            let row = base.advanced(by: y*stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<112 { let (r,g,b)=color(x,y); row[x*4]=b;row[x*4+1]=g;row[x*4+2]=r;row[x*4+3]=255 }
        }
        return pixels
    }
}

private final class LockedEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var id: UUID?
    let done = DispatchSemaphore(value: 0)
    var failedID: UUID? { lock.lock(); defer { lock.unlock() }; return id }
    func append(_ event: FaceCameraEvent) {
        if case let .failed(id, .modelUnavailable) = event {
            lock.lock(); self.id=id; lock.unlock(); done.signal()
        }
    }
}
