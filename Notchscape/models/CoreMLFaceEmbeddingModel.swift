import Foundation
import CoreML
import CoreVideo
import CryptoKit

/// Called serially by FaceCameraPipeline. Models must return real, versioned
/// embeddings, and must not retain input pixels or perform network requests.
protocol FaceEmbeddingModel: AnyObject, Sendable {
    var schema: FaceEmbeddingSchema { get }
    func embedding(from alignedFace: CVPixelBuffer) throws -> FaceNormalizedEmbedding
}

enum FaceEmbeddingModelError: Error {
    case unavailable, invalidPackage, incompatibleModel, invalidPixels, invalidOutput
}

/// An explicit loader for the independently converted OpenCV Zoo SFace probe.
/// No model is bundled or downloaded by this class. Synthetic conversion parity
/// is established; recognition accuracy and unlock thresholds are uncalibrated.
final class CoreMLFaceEmbeddingModel: FaceEmbeddingModel, @unchecked Sendable {
    static let sourceSHA256 = "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79"
    static let packageSHA256 = "22b0a515abbae2708c1e24981066c94c14441e9d34326f7859cce112d0277c9e"
    static let prototypeSchema = FaceEmbeddingSchema(
        modelVersion: "sface-\(sourceSHA256)-coreml-\(packageSHA256)-vision76-5pt112-rgb-v1", dimension: 128)!
    let schema = prototypeSchema
    private var model: MLModel?
    private let compiledURL: URL
    private let lock = NSLock()

    init(verifiedSFacePackageAt url: URL) throws {
        guard url.isFileURL, url.pathExtension == "mlpackage" else { throw FaceEmbeddingModelError.unavailable }
        let expected = [
            "Data/com.apple.CoreML/model.mlmodel": "03c1f5d8f75dfdfd1223b8068fe0bf43491e1c5f95bc46a91f12144aaf0f2192",
            "Data/com.apple.CoreML/weights/weight.bin": "0d0f19ba62e35fcdc5fe4a6156971ec15b481373150b88295e641a4dd027d37c",
            "Manifest.json": "ccc5a9750d319f93d522eef4e45fb6aafd0b8f18eb6067f70cf06370ebf4e5f8"
        ]
        for (name, digest) in expected {
            let file = url.appendingPathComponent(name)
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, (1...50_000_000).contains(size) else { throw FaceEmbeddingModelError.invalidPackage }
            let actual = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
            guard actual == digest else { throw FaceEmbeddingModelError.invalidPackage }
        }
        let compiled = try MLModel.compileModel(at: url)
        compiledURL = compiled
        let configuration = MLModelConfiguration(); configuration.computeUnits = .cpuOnly
        do {
            let loaded = try MLModel(contentsOf: compiled, configuration: configuration)
            guard Self.matchesContract(loaded) else {
                throw FaceEmbeddingModelError.incompatibleModel
            }
            model = loaded
        } catch {
            try? FileManager.default.removeItem(at: compiled)
            throw error
        }
    }

    private static func matchesContract(_ model: MLModel) -> Bool {
        let description = model.modelDescription
        let input = description.inputDescriptionsByName["face"]?.multiArrayConstraint
        let output = description.outputDescriptionsByName["embedding"]?.multiArrayConstraint
        let metadata = description.metadata[.creatorDefinedKey] as? [String: String]
        return description.inputDescriptionsByName.count == 1 && description.outputDescriptionsByName.count == 1 &&
            input?.shape.map(\.intValue) == [1, 3, 112, 112] && input?.dataType == .float32 &&
            output?.shape.map(\.intValue) == [1, 128] && output?.dataType == .float32 &&
            metadata?["source_sha256"] == sourceSHA256 &&
            metadata?["preprocessing"] == "Aligned112, raw RGB float32 NCHW 0..255, normalization already in graph"
    }

    func embedding(from alignedFace: CVPixelBuffer) throws -> FaceNormalizedEmbedding {
        lock.lock(); defer { lock.unlock() }
        guard let model else { throw FaceEmbeddingModelError.unavailable }
        let input = try Self.rawRGBTensor(from: alignedFace)
        let provider = try MLDictionaryFeatureProvider(dictionary: ["face": MLFeatureValue(multiArray: input)])
        guard let output = try model.prediction(from: provider).featureValue(for: "embedding")?.multiArrayValue,
              output.count == schema.dimension else { throw FaceEmbeddingModelError.invalidOutput }
        let values = (0..<output.count).map { output[$0].floatValue }
        guard let embedding = FaceNormalizedEmbedding(schema: schema, values: values) else { throw FaceEmbeddingModelError.invalidOutput }
        return embedding
    }

    /// BGRA storage → raw RGB NCHW. ONNX already contains (x−127.5)/128.
    static func rawRGBTensor(from pixels: CVPixelBuffer) throws -> MLMultiArray {
        guard CVPixelBufferGetWidth(pixels) == 112, CVPixelBufferGetHeight(pixels) == 112,
              CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(pixels, .readOnly) == kCVReturnSuccess else { throw FaceEmbeddingModelError.invalidPixels }
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { throw FaceEmbeddingModelError.invalidPixels }
        let result = try MLMultiArray(shape: [1, 3, 112, 112], dataType: .float32)
        let destination = result.dataPointer.bindMemory(to: Float.self, capacity: result.count)
        let strides = result.strides.map(\.intValue), rowBytes = CVPixelBufferGetBytesPerRow(pixels)
        for y in 0..<112 {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<112 {
                let offset = y * strides[2] + x * strides[3]
                destination[offset] = Float(row[x*4 + 2])
                destination[offset + strides[1]] = Float(row[x*4 + 1])
                destination[offset + 2*strides[1]] = Float(row[x*4])
            }
        }
        return result
    }

    deinit {
        model = nil
        try? FileManager.default.removeItem(at: compiledURL)
    }
}
