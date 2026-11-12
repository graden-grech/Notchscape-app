import AppKit
import AVFoundation
import Combine
import CoreGraphics
import Darwin
import Defaults
import LocalAuthentication
import OpenDirectory

struct FaceIdentitySummary: Identifiable {
    let id: UUID
    let label: String
    let isEnabled: Bool
}

enum FaceUnlockPresentation: String, CaseIterable { case minimal, expanded }

/// Only non-sensitive presentation state is exposed to the locked Home tree.
@MainActor
final class FaceUnlockActivityCenter: ObservableObject {
    enum Phase: Equatable { case hidden, scanning, recognized, unavailable }
    static let shared = FaceUnlockActivityCenter()
    @Published private(set) var phase: Phase = .hidden
    @Published private(set) var message = ""
    @Published private(set) var symbol = "person.crop.square"
    @Published private(set) var expandedGuidance = false
    @Published private(set) var canRetry = false
    var retry: (() -> Void)?
    private var dismissalTask: Task<Void, Never>?
    var isVisible: Bool { phase != .hidden }

    func update(_ phase: Phase, message: String = "", symbol: String = "person.crop.square", expandedGuidance: Bool = false, canRetry: Bool = false) {
        dismissalTask?.cancel(); dismissalTask = nil
        if self.phase != phase { self.phase = phase }
        if self.message != message { self.message = message }
        if self.symbol != symbol { self.symbol = symbol }
        if self.expandedGuidance != expandedGuidance { self.expandedGuidance = expandedGuidance }
        if self.canRetry != canRetry { self.canRetry = canRetry }
        if phase == .unavailable || phase == .recognized {
            dismissalTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                guard !Task.isCancelled else { return }
                self?.phase = .hidden
                self?.message = ""
            }
        }
    }
}

/// No camera, model load, authentication prompt or Keychain operation at init.
/// The only persistent preferences are local non-secret identifiers/appearance.
@MainActor
final class FaceUnlockManager: ObservableObject {
    static let shared = FaceUnlockManager()
    static var featureEnabled: Bool {
        FaceUnlockFeaturePolicy.permits(
            configurationValue: Bundle.main.object(forInfoDictionaryKey: "NotchFaceUnlockEnabled"),
            hasProtectedHelper: FileManager.default.fileExists(atPath: Bundle.main.bundleURL
                .appendingPathComponent("Contents/XPCServices/NotchscapeFaceVault.xpc").path))
    }
    @Published private(set) var hasVault = false
    @Published private(set) var isVaultAuthorized = false
    @Published private(set) var isBusy = false
    @Published private(set) var isCapturing = false
    @Published private(set) var identities: [FaceIdentitySummary] = []
    @Published private(set) var hasSavedCredential = false
    @Published private(set) var statusMessage = "Off. Set up Face Unlock to begin."
    @Published private(set) var statusSymbol = "lock"
    @Published private(set) var errorMessage: String?
    @Published private(set) var captureGuidance = "Look at the camera."
    @Published private(set) var captureSymbol = "person.crop.square"
    @Published private(set) var captureProgress = 0.0
    @Published private(set) var cameraPreview: FaceCameraPreviewSource?
    @Published private(set) var authorizedUntil: Date?
    @Published private(set) var automaticUnlockEnabled = false
    @Published private(set) var companionAuthenticationAvailable = false
    @Published private(set) var canRecoverUnfinishedSetup = false
    @Published private var lastRecognitionTestAt: Double?
    @Published var hapticFeedback: Bool {
        didSet { UserDefaults.standard.set(hapticFeedback, forKey: "faceUnlockHaptics") }
    }
    @Published var presentation: FaceUnlockPresentation {
        didSet { UserDefaults.standard.set(presentation.rawValue, forKey: "faceUnlockPresentation") }
    }

    private enum CapturePurpose { case enrollment(String), recognitionTest, screenUnlock }
    private let directory: URL
    private var vaultID: UUID
    private var vault: FaceUnlockVault?
    private var model: CoreMLFaceEmbeddingModel?
    private var pipeline: FaceCameraPipeline?
    private var captureID: UUID?
    private var capturePurpose: CapturePurpose?
    private var captureManifest = FaceIdentityManifest.empty
    private var enrollmentSamples: [FaceNormalizedEmbedding] = []
    private var enrollmentReference: FaceNormalizedEmbedding?
    private var recognition: FaceRecognitionSessionPolicy?
    private var recognitionReference: FaceNormalizedEmbedding?
    private var recognitionAliases: Set<UUID> = []
    private var convenienceAuthorization: FaceUnlockAuthorizationSession?
    private var expiryTask: Task<Void, Never>?
    private var pendingRecognitionTask: Task<Void, Never>?
    private var automaticResumeTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var operationGeneration: UInt64 = 0
    private var lockGeneration: UInt64 = 0
    private var attemptedLockGeneration: UInt64?
    private var isSystemLocked = false
    private var isSystemSleeping = false
    private let unlockAction = ScreenUnlockAction(now: { FaceUnlockVault.monotonicNow() })

    // Deliberately strict preview settings, not calibrated biometric confidence
    // or a Face ID equivalent. Enrollment/test on the actual camera is required.
    private let thresholds = FaceMatchThresholds(minimumCosineSimilarity: 0.80, minimumRunnerUpMargin: 0.10)!

    var hasRecentRecognitionTest: Bool {
        guard let lastRecognitionTestAt else { return false }
        let age = FaceUnlockVault.monotonicNow() - lastRecognitionTestAt
        return age >= 0 && age < 300
    }

    var showsCameraGuide: Bool {
        guard isCapturing, isVaultAuthorized, desktopIsUnlocked else { return false }
        switch capturePurpose {
        case .some(.enrollment), .some(.recognitionTest): return true
        default: return false
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        vaultID = defaults.string(forKey: "faceUnlockVaultID").flatMap(UUID.init(uuidString:)) ?? UUID()
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchscape/FaceUnlock", isDirectory: true)
        hapticFeedback = defaults.object(forKey: "faceUnlockHaptics") as? Bool ?? true
        presentation = defaults.string(forKey: "faceUnlockPresentation").flatMap(FaceUnlockPresentation.init(rawValue:)) ?? .minimal
        guard Self.featureEnabled else {
            statusMessage = "Face Unlock is not available in this release."
            return
        }
        hasVault = FileManager.default.fileExists(atPath: directory.appendingPathComponent(vaultID.uuidString).appendingPathExtension("vault").path)
        automaticUnlockEnabled = defaults.bool(forKey: "faceUnlockAutomaticEnabled")
        FaceUnlockActivityCenter.shared.retry = { [weak self] in
            Task { await self?.startLockScreenRecognition() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.systemWillSleep() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.systemDidWake() }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.endSession() } })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.systemDidWake() } })
    }

    func refreshCompanionAvailability() {
        // Advisory capability only: this is not the Mac's Auto Unlock setting
        // and never triggers a Watch or authentication prompt.
        let context = LAContext()
        companionAuthenticationAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithCompanion, error: nil)
        context.invalidate()
    }

    func openVault() async {
        guard Self.featureEnabled, !isBusy, desktopIsUnlocked else { return }
        if convenienceAuthorization?.mode == .automaticWhileRunning {
            do { try await refreshVaultSummary(); isVaultAuthorized = true }
            catch { report(error) }
            return
        }
        if automaticUnlockEnabled, hasVault {
            do { await authorizeAutomatic(using: try localVault()) }
            catch { report(error) }
            return
        }
        operationGeneration &+= 1
        isBusy = true; errorMessage = nil
        let token = operationGeneration
        convenienceAuthorization = nil; authorizedUntil = nil
        expiryTask?.cancel(); unlockAction.setEnabled(false)
        defer { isBusy = false }
        do {
            let vault = try localVault()
            await vault.updateDesktopState(isActive: true, isUnlocked: true)
            if !hasVault {
                UserDefaults.standard.set(vaultID.uuidString, forKey: "faceUnlockVaultID")
                try await vault.setup(initialManifest: .empty, credentialData: nil,
                    reason: "Create Notchscape's encrypted local Face Unlock vault")
                hasVault = true
                guard token == operationGeneration, desktopIsUnlocked else { return }
                statusMessage = "Vault created. Complete macOS authentication to add a face."
            }
            try await vault.authorizeUnlockedSession(lifetime: 300,
                reason: "Manage your local Notchscape face enrollments")
            guard token == operationGeneration, desktopIsUnlocked else { return }
            convenienceAuthorization = nil; authorizedUntil = nil; unlockAction.setEnabled(false)
            try await refreshVaultSummary()
            isVaultAuthorized = true
            statusMessage = "Face Unlock settings are unlocked."
            statusSymbol = "lock.open"
            scheduleExpiry(after: 300)
        } catch { report(error) }
    }

    func checkStorageAvailability() async {
        guard !isBusy, desktopIsUnlocked else { return }
        isBusy = true; errorMessage = nil
        let operation = operationGeneration
        defer { isBusy = false }
        do {
            let vault = try localVault()
            await vault.updateDesktopState(isActive: ownedConsoleSessionIsActive, isUnlocked: desktopIsUnlocked)
            guard operation == operationGeneration, desktopIsUnlocked else { return }
            try await vault.checkAvailability()
            guard operation == operationGeneration, desktopIsUnlocked else { return }
            statusMessage = "Protected storage is ready."
            statusSymbol = "checkmark.shield"
        } catch { report(error) }
    }

    func recoverUnfinishedSetup() async {
        guard canRecoverUnfinishedSetup, !isBusy, desktopIsUnlocked else { return }
        operationGeneration &+= 1
        let operation = operationGeneration
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do {
            try await localVault().recoverUnfinishedSetup(reason: "Recover the unfinished local Face Unlock setup")
            hasVault = true; canRecoverUnfinishedSetup = false
            guard operation == operationGeneration, desktopIsUnlocked else { return }
            statusMessage = "Setup recovered. Unlock these settings to add your first face."
            statusSymbol = "lock"
        } catch { report(error) }
    }

    @discardableResult
    func beginEnrollment(label: String) async -> Bool {
        guard let label = FaceIdentityTemplate.validatedLabel(label), identities.count < 8,
              !identities.contains(where: { $0.label.caseInsensitiveCompare(label) == .orderedSame }) else {
            errorMessage = "Choose a unique name of 1–64 characters. Up to eight appearances can be enrolled."
            return false
        }
        return await prepareCapture(.enrollment(label))
    }

    func beginRecognitionTest() async { _ = await prepareCapture(.recognitionTest) }

    private func prepareCapture(_ purpose: CapturePurpose) async -> Bool {
        guard Self.featureEnabled, !isBusy, !isCapturing, isVaultAuthorized, desktopIsUnlocked, let vault else { return false }
        isBusy = true; errorMessage = nil
        let token = operationGeneration
        defer { isBusy = false }
        do {
            try await loadModelIfNeeded()
            guard token == operationGeneration, desktopIsUnlocked else { model = nil; return false }
            guard await FaceCameraPipeline.requestCameraPermission() else {
                errorMessage = "Allow Camera access for Notchscape in System Settings to enroll or test a face."
                return false
            }
            guard token == operationGeneration, desktopIsUnlocked else { return false }
            let manifest = try await vault.manifest()
            guard token == operationGeneration, desktopIsUnlocked else { return false }
            captureManifest = manifest
            startCapture(purpose)
            return true
        } catch { report(error); return false }
    }

    private func loadModelIfNeeded() async throws {
        guard model == nil else { return }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("FaceModels/SFace.mlpackage"),
              FileManager.default.fileExists(atPath: url.path) else { throw FaceEmbeddingModelError.unavailable }
        let loaded = try await Task.detached(priority: .userInitiated) {
            try CoreMLFaceEmbeddingModel(verifiedSFacePackageAt: url)
        }.value
        model = loaded
    }

    private func startCapture(_ purpose: CapturePurpose) {
        guard let model else { return }
        enrollmentSamples.removeAll(); enrollmentReference = nil
        recognitionReference = nil; recognitionAliases.removeAll()
        capturePurpose = purpose
        cameraPreview?.revoke(); cameraPreview = nil
        let previewEnabled: Bool
        switch purpose {
        case .enrollment, .recognitionTest: previewEnabled = true
        case .screenUnlock: previewEnabled = false
        }
        captureProgress = 0; captureGuidance = "Look straight at the camera."; captureSymbol = "person.crop.square"
        let pipeline = FaceCameraPipeline(model: model,
            configuration: FaceCameraConfiguration(maximumSessionDuration: 20)!,
            now: { FaceUnlockVault.monotonicNow() }, previewEnabled: previewEnabled) { [weak self] event in
                Task { @MainActor in self?.handleCamera(event) }
            }
        self.pipeline = pipeline
        let id = pipeline.start()
        captureID = id
        recognition = FaceRecognitionSessionPolicy(captureID: id, startedAt: FaceUnlockVault.monotonicNow())
        isCapturing = true
    }

    func cancelCapture() {
        cameraPreview?.revoke(); cameraPreview = nil
        captureID = nil; capturePurpose = nil
        pipeline?.stop(); pipeline = nil
        isCapturing = false
        enrollmentSamples.removeAll(); enrollmentReference = nil
        recognition = nil; captureManifest = .empty
        recognitionReference = nil; recognitionAliases.removeAll()
        if isSystemLocked, convenienceAuthorization?.permitsScreenUnlock == true {
            FaceUnlockActivityCenter.shared.update(.unavailable, message: "Unlock your Mac normally, or try again.", expandedGuidance: presentation == .expanded, canRetry: attemptedLockGeneration != lockGeneration)
        }
    }

    private func handleCamera(_ event: FaceCameraEvent) {
        switch event {
        case .preview(let frame):
            let automatic: Bool
            if case .some(.screenUnlock) = capturePurpose { automatic = true } else { automatic = false }
            guard FaceScanPreviewPolicy.permits(session: frame.sessionID, currentSession: captureID,
                capturing: isCapturing, authorized: isVaultAuthorized, desktopUnlocked: desktopIsUnlocked,
                automaticAttempt: automatic, timestamp: frame.timestamp, now: FaceUnlockVault.monotonicNow()) else { return }
            guard frame.source.isValid else { return }
            if cameraPreview !== frame.source { cameraPreview = frame.source }
        case .started(let id):
            guard id == captureID else { return }
        case .stopped(let id):
            guard id == captureID else { return }
            cancelCapture()
        case .failed(let id, let reason):
            guard id == captureID else { return }
            cancelCapture()
            errorMessage = cameraFailureMessage(reason)
            statusMessage = errorMessage ?? "Camera session stopped."
            if isSystemLocked {
                FaceUnlockActivityCenter.shared.update(.unavailable, message: statusMessage,
                    expandedGuidance: presentation == .expanded, canRetry: attemptedLockGeneration != lockGeneration)
            }
        case .rejected(let id, let reason):
            guard id == captureID else { return }
            recognition?.rejectFrame()
            recognitionReference = nil; recognitionAliases.removeAll()
            enrollmentSamples.removeAll(); enrollmentReference = nil
            switch reason {
            case .noFace: setGuidance("Look at the camera.", symbol: "person.crop.square", progress: 0)
            case .multipleFaces: setGuidance("Keep only one face in view.", symbol: "person.2.slash", progress: 0)
            case .faceTooSmall: setGuidance("Move a little closer to the camera.", symbol: "arrow.down.right.and.arrow.up.left", progress: 0)
            case .unsupportedPose, .missingLandmarks: setGuidance("Face the camera with your head upright.", symbol: "person.crop.square", progress: 0)
            case .poorLightingOrBlur: setGuidance("Use brighter, steady lighting.", symbol: "sun.max", progress: 0)
            }
        case .observation(let observation):
            guard observation.sessionID == captureID, let purpose = capturePurpose,
                  observation.quality.isUsable, observation.embedding.schema == model?.schema else { return }
            let age = FaceUnlockVault.monotonicNow() - observation.timestamp
            guard age >= 0 && age <= 1.2 else { recognition?.rejectFrame(); return }
            updateGuidance(observation.headMovement)
            guard observation.sessionID == captureID else { return }
            switch purpose {
            case .enrollment(let label): processEnrollment(observation, label: label)
            case .recognitionTest, .screenUnlock: processRecognition(observation, purpose: purpose)
            }
        }
    }

    private func processEnrollment(_ observation: FaceCameraObservation, label: String) {
        if let reference = enrollmentReference {
            let similarity = zip(reference.values, observation.embedding.values).reduce(0.0) { $0 + Double($1.0) * Double($1.1) }
            guard similarity >= 0.75 else {
                cancelCapture(); errorMessage = "The face changed during enrollment. Try again with one face in view."
                return
            }
        } else { enrollmentReference = observation.embedding }
        if abs(observation.pose.yaw) <= 0.13, enrollmentSamples.count < FaceIdentityTemplate.maximumSamples {
            enrollmentSamples.append(observation.embedding)
        }
        guard observation.headMovement == .completed, enrollmentSamples.count >= 3,
              let identity = FaceIdentityTemplate(label: label, samples: enrollmentSamples), let vault else { return }
        let manifest = captureManifest
        let token = operationGeneration
        cancelCapture()
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                guard token == operationGeneration, desktopIsUnlocked else { return }
                try await vault.saveManifest(try manifest.enrolling(identity))
                guard token == operationGeneration, desktopIsUnlocked else { return }
                try await refreshVaultSummary()
                statusMessage = "Face enrolled. Test Recognition before enabling unlock."
                statusSymbol = "checkmark.circle"
                lastRecognitionTestAt = nil
                feedback()
            } catch { report(error) }
        }
    }

    private func processRecognition(_ observation: FaceCameraObservation, purpose: CapturePurpose) {
        let match = FaceIdentityMatcher.matchAuthorizedFace(observation.embedding, manifest: captureManifest, thresholds: thresholds)
        guard case .matched = match else {
            cancelCapture()
            statusMessage = "That face did not match an enabled enrollment. Try again with steady lighting."
            return
        }
        if let reference = recognitionReference {
            let similarity = zip(reference.values, observation.embedding.values).reduce(0.0) { $0 + Double($1.0) * Double($1.1) }
            guard similarity >= 0.75 else {
                cancelCapture(); statusMessage = "The face changed during the check. Start again with one face in view."
                return
            }
        } else {
            recognitionReference = observation.embedding
            recognitionAliases = FaceIdentityMatcher.compatibleAppearances(for: observation.embedding,
                manifest: captureManifest, minimumSimilarity: 0.75)
        }
        guard let evidence = recognition?.observe(captureID: observation.sessionID, challengeID: observation.challengeID,
            timestamp: observation.timestamp, pose: observation.pose, progress: observation.headMovement,
            match: match, compatibleIdentityAliases: recognitionAliases) else { return }
        cancelCapture()
        feedback()
        switch purpose {
        case .recognitionTest:
            lastRecognitionTestAt = FaceUnlockVault.monotonicNow()
            statusMessage = "Your enrolled face and movement check matched in this test."
            statusSymbol = "checkmark.circle"
        case .screenUnlock:
            submitRecognizedFace(observation.embedding, evidence: evidence, match: match)
        case .enrollment: break
        }
    }

    private func submitRecognizedFace(_ embedding: FaceNormalizedEmbedding, evidence: FaceRecognitionEvidence, match: FaceMatchOutcome) {
        guard isSystemLocked, let authorization = convenienceAuthorization, let vault else { return }
        attemptedLockGeneration = lockGeneration
        do {
            let attempt = try unlockAction.reserve(authorization: authorization,
                proof: ScreenUnlockRecognitionProof(authorizationToken: authorization.token,
                    lockGeneration: lockGeneration, match: match, challengeID: evidence.challengeID,
                    challengeSatisfied: true, frameTimestamp: evidence.observedAt, consecutiveMatchCount: 6))
            let action = unlockAction
            let thresholds = thresholds
            let operation = operationGeneration
            let generation = lockGeneration
            FaceUnlockActivityCenter.shared.update(.recognized, message: "Face recognized. Checking macOS…", expandedGuidance: presentation == .expanded)
            Task {
                guard operation == operationGeneration, generation == lockGeneration,
                      isSystemLocked, convenienceAuthorization?.token == attempt.authorizationToken else {
                    action.cancel(attempt); return
                }
                do {
                    let result = try await vault.withCredentialForRecognizedFace(embedding, thresholds: thresholds,
                        challengeSatisfied: true, authorizationToken: attempt.authorizationToken) { secret in
                            _ = try action.submit(secret, for: attempt)
                        }
                    guard case .matched = result else { action.cancel(attempt); return }
                    guard operation == operationGeneration, generation == lockGeneration,
                          isSystemLocked else { return }
                    statusMessage = "Submitted to macOS. Waiting for the system to unlock."
                    // A void event-post result does not prove an unlocked Mac.
                } catch {
                    action.cancel(attempt)
                    guard operation == operationGeneration, generation == lockGeneration,
                          isSystemLocked else { return }
                    report(error)
                    FaceUnlockActivityCenter.shared.update(.unavailable, message: "Unlock your Mac normally.", expandedGuidance: presentation == .expanded)
                }
            }
        } catch {
            report(error)
            FaceUnlockActivityCenter.shared.update(.unavailable, message: "Unlock your Mac normally.", expandedGuidance: presentation == .expanded)
        }
    }

    func saveMacPassword(_ password: String) async {
        guard !isBusy, !isCapturing, isVaultAuthorized, desktopIsUnlocked, let vault else { return }
        guard !password.isEmpty, password.utf16.count <= 256, !password.contains("\0") else {
            errorMessage = "Enter a Mac password of up to 256 characters."
            return
        }
        isBusy = true; errorMessage = nil
        let token = operationGeneration
        defer { isBusy = false }
        do {
            let valid = try await Task.detached(priority: .userInitiated) {
                let node = try ODNode(session: ODSession.default(), type: UInt32(kODNodeTypeLocalNodes))
                let record = try node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
                do { try record.verifyPassword(password); return true }
                catch { return false }
            }.value
            guard token == operationGeneration, desktopIsUnlocked else { return }
            guard valid else { errorMessage = "That password did not match your local Mac account."; return }
            var data = Data(password.utf8)
            defer { data.resetBytes(in: 0..<data.count) }
            try await vault.setCredentialData(data)
            hasSavedCredential = true
            statusMessage = "Mac password saved in your encrypted local vault."
        } catch { report(error) }
    }

    func removeMacPassword() async {
        guard !isBusy, isVaultAuthorized, desktopIsUnlocked, let vault else { return }
        do {
            try await vault.setCredentialData(nil)
            hasSavedCredential = false
            automaticUnlockEnabled = false
            UserDefaults.standard.set(false, forKey: "faceUnlockAutomaticEnabled")
            endSession()
        }
        catch { report(error) }
    }

    func setIdentityEnabled(_ enabled: Bool, id: UUID) async {
        await editManifest { try $0.settingEnabled(enabled, identityID: id) }
    }
    func deleteIdentity(_ id: UUID) async { await editManifest { try $0.deleting(id) } }
    func renameIdentity(_ id: UUID, label: String) async { await editManifest { try $0.renaming(id, label: label) } }

    private func editManifest(_ edit: (FaceIdentityManifest) throws -> FaceIdentityManifest) async {
        guard !isBusy, !isCapturing, isVaultAuthorized, desktopIsUnlocked, let vault else { return }
        isBusy = true; errorMessage = nil
        let token = operationGeneration
        defer { isBusy = false }
        do {
            let current = try await vault.manifest()
            guard token == operationGeneration, desktopIsUnlocked else { return }
            try await vault.saveManifest(edit(current))
            guard token == operationGeneration, desktopIsUnlocked else { return }
            try await refreshVaultSummary()
            lastRecognitionTestAt = nil
        } catch { report(error) }
    }

    func setAutomaticUnlockEnabled(_ enabled: Bool) async {
        if !enabled {
            automaticUnlockEnabled = false
            UserDefaults.standard.set(false, forKey: "faceUnlockAutomaticEnabled")
            endSession()
            statusMessage = "Face Unlock is off."
            return
        }
        guard !isBusy, !isCapturing, isVaultAuthorized, hasSavedCredential,
              hasRecentRecognitionTest, desktopIsUnlocked, let vault else { return }
        await authorizeAutomatic(using: vault)
    }

    private func authorizeAutomatic(using vault: FaceUnlockVault) async {
        guard !Task.isCancelled, desktopIsUnlocked else { return }
        operationGeneration &+= 1
        isBusy = true; errorMessage = nil
        let token = operationGeneration
        defer { isBusy = false }
        do {
            await vault.updateDesktopState(isActive: true, isUnlocked: true)
            try await vault.authorizeAutomaticUnlock(reason: "Enable automatic webcam unlock while Notchscape is running")
            guard token == operationGeneration, desktopIsUnlocked,
                  let authorization = await vault.authorizationSession(), authorization.permitsScreenUnlock else { return }
            try await refreshVaultSummary()
            guard hasSavedCredential, identities.contains(where: \.isEnabled) else {
                endSession(); errorMessage = "Add an enabled face and save your Mac password first."; return
            }
            try await loadModelIfNeeded()
            guard token == operationGeneration, desktopIsUnlocked else { return }
            convenienceAuthorization = authorization
            authorizedUntil = nil
            expiryTask?.cancel(); expiryTask = nil
            automaticUnlockEnabled = true
            UserDefaults.standard.set(true, forKey: "faceUnlockAutomaticEnabled")
            isVaultAuthorized = true
            unlockAction.setEnabled(true)
            statusMessage = "Face Unlock is on. It starts automatically when this Mac locks."
            statusSymbol = "lock.open"
        } catch { report(error) }
    }

    private func resumeAutomaticIfEnabled() {
        guard Self.featureEnabled, automaticUnlockEnabled, hasVault, !isBusy, !isCapturing,
              convenienceAuthorization == nil, desktopIsUnlocked else { return }
        automaticResumeTask?.cancel()
        automaticResumeTask = Task {
            do { await authorizeAutomatic(using: try localVault()) }
            catch { report(error) }
        }
    }

    func resumeAutomaticUnlock() { resumeAutomaticIfEnabled() }

    func systemDidLock() {
        guard !isSystemLocked else { return }
        isSystemLocked = true; lockGeneration &+= 1; operationGeneration &+= 1
        pendingRecognitionTask?.cancel(); pendingRecognitionTask = nil
        cancelCapture()
        isVaultAuthorized = false; identities = []
        FaceUnlockWindowController.shared.close()
        if automaticUnlockEnabled, convenienceAuthorization?.permitsScreenUnlock == true {
            unlockAction.setEnabled(true)
        }
        unlockAction.sessionLocked(generation: lockGeneration)
        guard ownedConsoleSessionIsActive else { endSession(); return }
        guard let vault else { return }
        let generation = lockGeneration
        pendingRecognitionTask = Task {
            await vault.updateDesktopState(isActive: true, isUnlocked: false)
            // Native Auto Unlock gets the first opportunity. Actual lock/session
            // checks, not a Watch capability guess, decide whether we continue.
            do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
            guard !Task.isCancelled, generation == lockGeneration, isSystemLocked else { return }
            await startLockScreenRecognition()
        }
    }

    func systemDidUnlock() {
        // Native unlock (including Apple Watch or Touch ID) wins immediately.
        // Revoke credential delivery before canceling camera/UI work or awaits.
        unlockAction.sessionUnlocked()
        operationGeneration &+= 1
        let displayAwake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
        isSystemSleeping = !displayAwake
        pendingRecognitionTask?.cancel(); pendingRecognitionTask = nil
        let wasLocked = isSystemLocked
        isSystemLocked = false
        guard ownedConsoleSessionIsActive else { endSession(); return }
        attemptedLockGeneration = nil
        cancelCapture()
        FaceUnlockActivityCenter.shared.update(.hidden)
        if wasLocked { statusMessage = "Your Mac is unlocked." }
        if let vault {
            let operation = operationGeneration
            Task {
                await vault.handle(displayAwake ? .systemWake : .systemSleep)
                await vault.updateDesktopState(isActive: ownedConsoleSessionIsActive, isUnlocked: desktopIsUnlocked)
                guard operation == operationGeneration, desktopIsUnlocked else { return }
                if convenienceAuthorization?.mode == .automaticWhileRunning {
                    do { try await refreshVaultSummary(); isVaultAuthorized = true }
                    catch { report(error) }
                }
            }
        }
        if displayAwake { resumeAutomaticIfEnabled() }
    }

    private func systemWillSleep() {
        isSystemSleeping = true
        operationGeneration &+= 1
        pendingRecognitionTask?.cancel(); pendingRecognitionTask = nil
        cancelCapture(); unlockAction.invalidate()
        FaceUnlockActivityCenter.shared.update(.hidden)
        if convenienceAuthorization?.mode != .automaticWhileRunning { endSession() }
        else if let vault { Task { await vault.handle(.systemSleep) } }
    }

    private func systemDidWake() {
        guard CGDisplayIsAsleep(CGMainDisplayID()) == 0 else { return }
        isSystemSleeping = false
        operationGeneration &+= 1
        let operation = operationGeneration
        Task {
            if let vault {
                await vault.handle(.systemWake)
                await vault.updateDesktopState(isActive: ownedConsoleSessionIsActive, isUnlocked: desktopIsUnlocked)
                guard operation == operationGeneration else { return }
                if let authorization = await vault.authorizationSession(), authorization.mode == .automaticWhileRunning {
                    convenienceAuthorization = authorization
                }
            }
            guard operation == operationGeneration else { return }
            guard automaticUnlockEnabled else { return }
            continueAfterSystemWake()
        }
    }

    private func continueAfterSystemWake() {
        if desktopIsUnlocked { resumeAutomaticIfEnabled(); return }
        guard isSystemLocked, convenienceAuthorization?.mode == .automaticWhileRunning else { return }
        unlockAction.setEnabled(true)
        unlockAction.sessionLocked(generation: lockGeneration)
        pendingRecognitionTask?.cancel()
        let generation = lockGeneration
        pendingRecognitionTask = Task {
            do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
            guard !Task.isCancelled, generation == lockGeneration, isSystemLocked else { return }
            await startLockScreenRecognition()
        }
    }

    private func startLockScreenRecognition() async {
        guard isSystemLocked, !isSystemSleeping, ownedConsoleSessionIsActive, attemptedLockGeneration != lockGeneration,
              !isCapturing, let vault, let authorization = convenienceAuthorization,
              authorization.permitsRead(now: FaceUnlockVault.monotonicNow(), desktopIsActive: true, desktopIsUnlocked: false),
              FaceCameraPipeline.authorizationStatus == .authorized, model != nil else { return }
        do {
            let operation = operationGeneration
            let manifest = try await vault.manifest()
            guard operation == operationGeneration, isSystemLocked, !isSystemSleeping,
                  convenienceAuthorization?.token == authorization.token else { return }
            captureManifest = manifest
            FaceUnlockActivityCenter.shared.update(.scanning, message: "Look at the camera.", expandedGuidance: presentation == .expanded)
            startCapture(.screenUnlock)
        } catch { report(error) }
    }

    func endSession() {
        operationGeneration &+= 1
        pendingRecognitionTask?.cancel(); pendingRecognitionTask = nil
        automaticResumeTask?.cancel(); automaticResumeTask = nil
        expiryTask?.cancel(); expiryTask = nil
        cancelCapture(); unlockAction.setEnabled(false)
        convenienceAuthorization = nil; authorizedUntil = nil
        model = nil
        isVaultAuthorized = false; identities = []; hasSavedCredential = false; lastRecognitionTestAt = nil
        statusMessage = automaticUnlockEnabled ? "Authenticate with macOS to resume Face Unlock."
            : (hasVault ? "Locked. Unlock Face Unlock settings to continue." : "Off. Set up Face Unlock to begin.")
        statusSymbol = "lock"
        FaceUnlockActivityCenter.shared.update(.hidden)
        if let vault { Task { await vault.stop() } }
    }

    func lockSettings() { endSession() }
    func closeSettings() {
        operationGeneration &+= 1
        if !isSystemLocked { cancelCapture() }
        if convenienceAuthorization == nil { endSession() }
    }

    func deleteAllData() async {
        guard !isBusy, isVaultAuthorized, desktopIsUnlocked, let vault else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await vault.deleteVault()
            automaticUnlockEnabled = false
            UserDefaults.standard.set(false, forKey: "faceUnlockAutomaticEnabled")
            endSession(); self.vault = nil; model = nil
            hasVault = false; vaultID = UUID()
            canRecoverUnfinishedSetup = false
            UserDefaults.standard.removeObject(forKey: "faceUnlockVaultID")
            statusMessage = "Local Face Unlock data deleted."
        } catch { report(error) }
    }

    private func localVault() throws -> FaceUnlockVault {
        guard Self.featureEnabled else { throw FaceVaultError.authenticationUnavailable }
        if let vault { return vault }
        let vault = try FaceUnlockVault(directory: directory, vaultID: vaultID)
        self.vault = vault
        return vault
    }

    private func refreshVaultSummary() async throws {
        guard let vault, desktopIsUnlocked else { throw FaceVaultError.desktopLocked }
        let operation = operationGeneration
        let manifest = try await vault.manifest()
        let credentialPresent = try await vault.hasCredential()
        guard operation == operationGeneration, desktopIsUnlocked else { throw FaceVaultError.invalidated }
        identities = manifest.identities.map { FaceIdentitySummary(id: $0.id, label: $0.label, isEnabled: $0.isEnabled) }
        hasSavedCredential = credentialPresent
    }

    private func scheduleExpiry(after lifetime: Double) {
        expiryTask?.cancel()
        expiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(lifetime)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.endSession()
        }
    }

    private func updateGuidance(_ progress: FaceHeadChallengeProgress) {
        switch progress {
        case .waitingForCenter: setGuidance("Look straight at the camera.", symbol: "person.crop.square", progress: 0.15)
        case .turn(let direction): setGuidance(direction == .left ? "Turn your head gently left." : "Turn your head gently right.", symbol: direction == .left ? "arrow.turn.up.left" : "arrow.turn.up.right", progress: 0.4)
        case .returnToCenter: setGuidance("Face the camera again.", symbol: "person.crop.square", progress: 0.75)
        case .completed: setGuidance("Movement check complete.", symbol: "checkmark", progress: 1)
        case .expired: cancelCapture(); statusMessage = "The movement check timed out. Start again when ready."
        }
    }

    private func setGuidance(_ text: String, symbol: String, progress: Double) {
        if captureGuidance != text { captureGuidance = text }
        if captureSymbol != symbol { captureSymbol = symbol }
        if captureProgress != progress { captureProgress = progress }
        if isSystemLocked { FaceUnlockActivityCenter.shared.update(.scanning, message: text, symbol: symbol, expandedGuidance: presentation == .expanded) }
    }

    private func feedback() {
        if hapticFeedback && Defaults[.enableHaptics] {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private var desktopIsUnlocked: Bool {
        // The WindowServer omits its lock key on an unlocked desktop. Combine
        // that metadata with our lock/sleep fence and exact owned console user;
        // never use absence alone as authority to deliver credentials.
        !isSystemLocked && !isSystemSleeping && ownedConsoleSessionIsActive && WorkspaceAccess.unlocked
    }

    private var ownedConsoleSessionIsActive: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              session[kCGSessionLoginDoneKey as String] as? Bool == true,
              let user = session[kCGSessionUserIDKey as String] as? NSNumber else { return false }
        return user.uint32Value == getuid() && geteuid() == getuid() && getuid() != 0
    }

    private func cameraFailureMessage(_ failure: FaceCameraFailure) -> String {
        switch failure {
        case .permissionRequired: "Camera access is unavailable."
        case .cameraUnavailable, .configurationFailed: "The camera is unavailable. Close other camera sessions and try again."
        case .modelUnavailable, .modelFailed: "The verified recognition model could not be loaded."
        case .processingFailed: "The camera frame could not be processed."
        case .captureInterrupted: "The camera session was interrupted."
        case .sessionTimedOut: "The camera session ended. Start again when ready."
        }
    }

    private func report(_ error: Error) {
        canRecoverUnfinishedSetup = false
        if let failure = error as? ScreenUnlockFailure { errorMessage = failure.errorDescription }
        else if let failure = error as? FaceVaultError {
            switch failure {
            case .unfinishedSetup:
                canRecoverUnfinishedSetup = true
                errorMessage = "A protected key exists from an unfinished setup. Recover Setup creates an empty local vault after system authentication; it does not replace existing faces or keys."
            case .authenticationDenied, .cancelled: errorMessage = "System authentication was canceled or denied."
            case .authenticationUnavailable: errorMessage = "System authentication is unavailable on this Mac."
            case .authorizationRequired, .sessionExpired, .invalidated, .desktopLocked: errorMessage = "Unlock Face Unlock settings again to continue."
            case .credentialMissing: errorMessage = "Save your Mac password before authorizing an unlock session."
            case .systemFailure(let details):
                if details.isMissingEntitlement {
                    errorMessage = "Face Unlock setup is unavailable in this app build. Install the corrected build, then try again. (\(details.diagnosticCode))"
                } else {
                    let operation: String
                    switch details.stage {
                    case .brokerConnection: operation = "connect to the protected vault"
                    case .accessControlCreation, .keychainCreate: operation = "create the protected vault key"
                    case .authenticationAvailability, .authenticationEvaluation: operation = "complete system authentication"
                    case .keychainRead: operation = "open the protected vault key"
                    case .keychainDelete, .encryptedDelete: operation = "remove the local vault"
                    case .encryptedRead: operation = "open the encrypted local vault"
                    case .encryptedWrite: operation = "save the encrypted local vault"
                    }
                    errorMessage = "macOS could not \(operation). No unlock was attempted. (\(details.diagnosticCode))"
                }
            default: errorMessage = "The encrypted local vault could not be updated. No unlock was attempted."
            }
        } else if error is FaceEmbeddingModelError { errorMessage = "The verified local recognition model is unavailable." }
        else if error is FaceUnlockPolicyError { errorMessage = "That appearance could not be saved. Use a unique name and try again." }
        else { errorMessage = "The local operation could not be completed. Your normal Mac password remains available." }
    }
}
