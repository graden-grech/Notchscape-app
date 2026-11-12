@preconcurrency import AVFoundation
@preconcurrency import Vision
import CoreImage
import ImageIO
import Foundation

enum FaceCameraRejection: Sendable {
    case noFace, multipleFaces, faceTooSmall, unsupportedPose, missingLandmarks, poorLightingOrBlur
}
enum FaceCameraFailure: Error, Sendable {
    case permissionRequired, modelUnavailable, cameraUnavailable, configurationFailed
    case processingFailed, modelFailed, captureInterrupted, sessionTimedOut
}
struct FaceCameraQuality: Sendable {
    let facePixelSize: CGSize
    let detectionConfidence: Float
    let meanLuma: Double
    let lumaStandardDeviation: Double
    let edgeEnergy: Double
    // Conservative image-processing heuristics, not biometric confidence.
    var isUsable: Bool { detectionConfidence >= 0.8 && (20...235).contains(meanLuma) && lumaStandardDeviation >= 10 && edgeEnergy >= 3 }
}
struct FaceCameraObservation: Sendable {
    let sessionID: UUID
    /// Monotonic time from the injected clock; never persisted image metadata.
    let timestamp: TimeInterval
    /// Vision coordinates: normalized lower-left origin in the upright image.
    let normalizedBounds: CGRect
    let pose: FaceCameraPose
    let quality: FaceCameraQuality
    let challengeID: UUID
    let headMovement: FaceHeadChallengeProgress
    let embedding: FaceNormalizedEmbedding
}
enum FaceCameraEvent: Sendable {
    case started(UUID)
    case preview(FaceCameraPreview)
    case observation(FaceCameraObservation)
    case rejected(sessionID: UUID, reason: FaceCameraRejection)
    case failed(sessionID: UUID, reason: FaceCameraFailure)
    case stopped(UUID)
}

/// A bounded readiness heartbeat, not a copied camera image.
struct FaceCameraPreview: Sendable {
    let sessionID: UUID
    let timestamp: TimeInterval
    let source: FaceCameraPreviewSource
}

/// Constructing this object never requests permission, discovers cameras or
/// starts capture. Callers explicitly request permission, then explicitly start.
/// Recognition is serial and limited to at most four frames/s.
/// Interactive preview is rendered directly by AVFoundation, independently.
/// No image/embedding is written, logged or sent over a network by this class.
final class FaceCameraPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    static var authorizationStatus: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }
    static func requestCameraPermission() async -> Bool {
        switch authorizationStatus {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private let model: (any FaceEmbeddingModel)?
    private let configuration: FaceCameraConfiguration
    private let now: @Sendable () -> TimeInterval
    private let eventQueue: DispatchQueue
    private let onEvent: @Sendable (FaceCameraEvent) -> Void
    private let previewEnabled: Bool
    private let queue = DispatchQueue(label: "Notchscape.FaceCamera", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var session: AVCaptureSession?
    private var output: AVCaptureVideoDataOutput?
    private var sessionID: UUID?
    private var orientation: CGImagePropertyOrientation = .up
    private var challenge: FaceHeadMovementChallenge?
    private var previousBounds: CGRect?
    private var lastFrameAt: TimeInterval = -.infinity
    private var previewDeliveryPending = false
    private var previewSource: FaceCameraPreviewSource?
    private var deadline: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []

    init(model: (any FaceEmbeddingModel)?, configuration: FaceCameraConfiguration = FaceCameraConfiguration()!,
         now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         eventQueue: DispatchQueue = .main, previewEnabled: Bool = false,
         onEvent: @escaping @Sendable (FaceCameraEvent) -> Void) {
        self.model = model; self.configuration = configuration
        self.now = now
        self.eventQueue = eventQueue; self.onEvent = onEvent
        self.previewEnabled = previewEnabled
        super.init()
    }

    /// Orientation describes the unmirrored camera buffer, not a selfie preview.
    /// Mirroring is disabled on the connection and orientation is applied once
    /// in Core Image before Vision/alignment, including externally rotated input.
    @discardableResult
    func start(deviceID: String? = nil, orientation: CGImagePropertyOrientation = .up,
               direction: FaceHeadTurnDirection? = nil) -> UUID {
        let id = UUID()
        queue.async { [self] in
            teardown()
            sessionID = id
            guard model != nil else { fail(.modelUnavailable); return }
            guard Self.authorizationStatus == .authorized else { fail(.permissionRequired); return }
            self.orientation = orientation
            let now = self.now()
            guard let challenge = FaceHeadMovementChallenge(direction: direction ?? (Bool.random() ? .left : .right), issuedAt: now) else {
                fail(.configurationFailed); return
            }
            self.challenge = challenge
            do {
                let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external],
                    mediaType: .video, position: .unspecified).devices
                let device = deviceID.flatMap { id in devices.first { $0.uniqueID == id } } ??
                    (deviceID == nil ? (devices.first { $0.deviceType == .builtInWideAngleCamera } ?? devices.first) : nil)
                guard let device else { fail(.cameraUnavailable); return }
                let input = try AVCaptureDeviceInput(device: device)
                let capture = AVCaptureSession(), dataOutput = AVCaptureVideoDataOutput()
                capture.beginConfiguration()
                let preset: AVCaptureSession.Preset = previewEnabled && device.supportsSessionPreset(.hd1280x720) && capture.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .vga640x480
                guard capture.canSetSessionPreset(preset), capture.canAddInput(input), capture.canAddOutput(dataOutput) else {
                    capture.commitConfiguration(); fail(.configurationFailed); return
                }
                capture.sessionPreset = preset
                capture.addInput(input); capture.addOutput(dataOutput)
                dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                dataOutput.alwaysDiscardsLateVideoFrames = true
                dataOutput.setSampleBufferDelegate(self, queue: queue)
                if let connection = dataOutput.connection(with: .video) {
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                    if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
                }
                if previewEnabled {
                    // Configure this connection on the capture queue, before startRunning.
                    // The UI receives only its display layer, never ownership of capture.
                    let layer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: capture)
                    guard let port = input.ports.first(where: { $0.mediaType == .video }) else {
                        capture.commitConfiguration(); fail(.configurationFailed); return
                    }
                    let connection = AVCaptureConnection(inputPort: port, videoPreviewLayer: layer)
                    guard capture.canAddConnection(connection) else {
                        capture.commitConfiguration(); fail(.configurationFailed); return
                    }
                    capture.addConnection(connection)
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                    if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
                    previewSource = FaceCameraPreviewSource(layer: layer)
                }
                capture.commitConfiguration()
                session = capture; output = dataOutput
                observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                    object: capture, queue: nil) { [weak self] _ in self?.stopAfterFailure(.captureInterrupted) })
                observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
                    object: capture, queue: nil) { [weak self] _ in self?.stopAfterFailure(.captureInterrupted) })
                observers.append(NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification,
                    object: device, queue: nil) { [weak self] _ in self?.stopAfterFailure(.captureInterrupted) })
                capture.startRunning()
                guard capture.isRunning else { fail(.configurationFailed); return }
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now() + configuration.maximumSessionDuration)
                timer.setEventHandler { [weak self] in self?.fail(.sessionTimedOut) }
                deadline = timer; timer.resume()
                emit(.started(id))
            } catch { fail(.configurationFailed) }
        }
        return id
    }

    func stop() { queue.async { [self] in teardown() } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard output === self.output, let id = sessionID, let model,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = self.now()
        guard now.isFinite, now >= 0, now > lastFrameAt else { fail(.processingFailed); return }
        guard now - lastFrameAt >= configuration.minimumFrameInterval else { return }
        lastFrameAt = now
        autoreleasepool {
            do {
                guard let upright = analysisImage(from: Self.uprightImage(from: pixels, orientation: orientation)) else {
                    rejectProcessingFailure(at: now); return
                }
                if previewEnabled, !previewDeliveryPending, let source = previewSource, source.isValid {
                    previewDeliveryPending = true
                    let frame = FaceCameraPreview(sessionID: id, timestamp: now, source: source)
                    // Coalesce readiness delivery; native video never waits for this
                    // recognition heartbeat or copies camera images into SwiftUI.
                    eventQueue.async { [weak self] in
                        guard let self else { return }
                        onEvent(.preview(frame))
                        queue.async { [weak self] in self?.previewDeliveryPending = false }
                    }
                }
                let request = VNDetectFaceLandmarksRequest(); request.constellation = .constellation76Points
                try VNImageRequestHandler(ciImage: upright, orientation: .up).perform([request])
                let faces = request.results ?? []
                guard faces.count == 1 else { reject(faces.isEmpty ? .noFace : .multipleFaces, at: now); return }
                let face = faces[0], size = upright.extent.size
                guard configuration.acceptsFace(face.boundingBox, imageSize: size) else { reject(.faceTooSmall, at: now); return }
                guard let yaw = face.yaw?.doubleValue, let pitch = face.pitch?.doubleValue,
                      let roll = face.roll?.doubleValue, let pose = FaceCameraPose(yaw: yaw, pitch: pitch, roll: roll),
                      pose.permitsAlignment else { reject(.unsupportedPose, at: now); return }
                guard let aligned = alignedFace(face, in: upright) else { reject(.missingLandmarks, at: now); return }
                let quality = Self.quality(of: aligned, facePixelSize: .init(width: face.boundingBox.width * size.width,
                    height: face.boundingBox.height * size.height), confidence: face.confidence)
                guard quality.isUsable else { reject(.poorLightingOrBlur, at: now); return }
                // A discontinuous face location restarts the weak movement check.
                // Caller must additionally require the same matched identity
                // throughout a challenge; geometric continuity is not identity.
                if let previousBounds {
                    let intersection = previousBounds.intersection(face.boundingBox)
                    let area = max(0, intersection.width) * max(0, intersection.height)
                    let union = previousBounds.width * previousBounds.height + face.boundingBox.width * face.boundingBox.height - area
                    if !area.isFinite || area / max(union, 1e-12) < 0.35 { _ = challenge?.observe(pose: nil, at: now - 0.000001) }
                }
                previousBounds = face.boundingBox
                let embedding: FaceNormalizedEmbedding
                do { embedding = try model.embedding(from: aligned) } catch { fail(.modelFailed); return }
                guard embedding.schema == model.schema, var current = challenge else { fail(.modelFailed); return }
                let progress = current.observe(pose: pose, at: now); challenge = current
                emit(.observation(.init(sessionID: id, timestamp: now, normalizedBounds: face.boundingBox,
                    pose: pose, quality: quality, challengeID: current.id, headMovement: progress, embedding: embedding)))
            } catch { rejectProcessingFailure(at: now) }
        }
    }

    static func uprightImage(from pixels: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> CIImage {
        let oriented = CIImage(cvPixelBuffer: pixels).oriented(orientation)
        return oriented.transformed(by: .init(translationX: -oriented.extent.minX, y: -oriented.extent.minY))
    }

    func analysisImage(from image: CIImage) -> CIImage? {
        guard let scale = FaceScanPreviewPolicy.previewScale(width: image.extent.width, height: image.extent.height) else { return nil }
        let origin = image.transformed(by: .init(translationX: -image.extent.minX, y: -image.extent.minY))
        return origin.transformed(by: .init(scaleX: scale, y: scale))
    }

    private func alignedFace(_ face: VNFaceObservation, in image: CIImage) -> CVPixelBuffer? {
        guard let landmarks = face.landmarks else { return nil }
        func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            guard let region else { return [] }
            return region.normalizedPoints.map { p in
                CGPoint(x: (face.boundingBox.minX + p.x * face.boundingBox.width) * image.extent.width,
                        y: (face.boundingBox.minY + p.y * face.boundingBox.height) * image.extent.height)
            }
        }
        func mean(_ points: [CGPoint]) -> CGPoint? {
            guard !points.isEmpty else { return nil }
            return .init(x: points.map(\.x).reduce(0,+) / CGFloat(points.count), y: points.map(\.y).reduce(0,+) / CGFloat(points.count))
        }
        guard let eyeA = mean(points(landmarks.leftEye)), let eyeB = mean(points(landmarks.rightEye)),
              let nose = points(landmarks.noseCrest).min(by: { $0.y < $1.y }),
              let lipA = points(landmarks.outerLips).min(by: { $0.x < $1.x }),
              let lipB = points(landmarks.outerLips).max(by: { $0.x < $1.x }) else { return nil }
        // Vision76 outline-derived points differ from YuNet's detector points.
        // This adapter is explicitly versioned and needs real recognition
        // calibration; tensor conversion parity alone does not validate it.
        let eyes = [eyeA, eyeB].sorted { $0.x < $1.x }
        let source = [eyes[0], eyes[1], nose, lipA, lipB]
        let destination = FaceAlignmentPolicy.referencePoints.map { CGPoint(x: $0.x, y: 112 - $0.y) }
        guard let transform = FaceAlignmentPolicy.similarityTransform(source: source, destination: destination) else { return nil }
        var result: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 112, 112, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
            &result) == kCVReturnSuccess, let result else { return nil }
        context.render(image.transformed(by: transform).cropped(to: .init(x: 0, y: 0, width: 112, height: 112)),
            to: result, bounds: .init(x: 0, y: 0, width: 112, height: 112), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return result
    }

    static func quality(of pixels: CVPixelBuffer, facePixelSize: CGSize, confidence: Float) -> FaceCameraQuality {
        guard CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_32BGRA,
              CVPixelBufferGetWidth(pixels) == 112, CVPixelBufferGetHeight(pixels) == 112,
              CVPixelBufferLockBaseAddress(pixels, .readOnly) == kCVReturnSuccess else {
            return .init(facePixelSize: facePixelSize, detectionConfidence: confidence, meanLuma: 0, lumaStandardDeviation: 0, edgeEnergy: 0)
        }
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else {
            return .init(facePixelSize: facePixelSize, detectionConfidence: confidence, meanLuma: 0, lumaStandardDeviation: 0, edgeEnergy: 0)
        }
        var total = 0.0, squared = 0.0, edges = 0.0
        let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
        // Ignore the outer eight pixels, where alignment padding can dominate.
        for y in 8..<104 {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            var previous: Double?
            for x in 8..<104 {
                let luma = 0.2126 * Double(row[x*4+2]) + 0.7152 * Double(row[x*4+1]) + 0.0722 * Double(row[x*4])
                total += luma; squared += luma*luma
                if let previous { edges += abs(luma - previous) }; previous = luma
            }
        }
        let mean = total / (96*96), deviation = max(0, squared / (96*96) - mean*mean).squareRoot()
        return .init(facePixelSize: facePixelSize, detectionConfidence: confidence, meanLuma: mean,
            lumaStandardDeviation: deviation, edgeEnergy: edges / (96*95))
    }

    private func reject(_ reason: FaceCameraRejection, at time: TimeInterval) {
        previousBounds = nil; _ = challenge?.observe(pose: nil, at: time)
        if let sessionID { emit(.rejected(sessionID: sessionID, reason: reason)) }
    }
    private func rejectProcessingFailure(at time: TimeInterval) {
        previousBounds = nil; _ = challenge?.observe(pose: nil, at: time)
        if let sessionID { emit(.failed(sessionID: sessionID, reason: .processingFailed)) }
    }
    private func stopAfterFailure(_ reason: FaceCameraFailure) { queue.async { [weak self] in self?.fail(reason) } }
    private func fail(_ reason: FaceCameraFailure) {
        if let sessionID { emit(.failed(sessionID: sessionID, reason: reason)) }; teardown()
    }
    private func emit(_ event: FaceCameraEvent) { eventQueue.async { [onEvent] in onEvent(event) } }
    private func teardown() {
        let oldID = sessionID; sessionID = nil
        previewSource?.revoke(); previewSource = nil
        previewDeliveryPending = false
        deadline?.cancel(); deadline = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        output?.setSampleBufferDelegate(nil, queue: nil)
        if let session {
            if session.isRunning { session.stopRunning() }
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput); session.outputs.forEach(session.removeOutput)
            session.commitConfiguration()
        }
        output = nil; session = nil; challenge = nil; previousBounds = nil; lastFrameAt = -.infinity
        if let oldID { emit(.stopped(oldID)) }
    }
    deinit {
        deadline?.cancel(); observers.forEach(NotificationCenter.default.removeObserver)
        let remainingSession = session, remainingOutput = output
        queue.async {
            remainingOutput?.setSampleBufferDelegate(nil, queue: nil)
            if remainingSession?.isRunning == true { remainingSession?.stopRunning() }
        }
    }
}
