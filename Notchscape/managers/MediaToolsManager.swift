import AppKit
import AVFoundation
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers
import SwiftUI
import Combine

enum MediaExportKind: String, CaseIterable, Identifiable {
    case video = "MP4 Video", audio = "M4A Audio", gif = "Animated GIF"
    var id: Self { self }
    var fileExtension: String { switch self { case .video: "mp4"; case .audio: "m4a"; case .gif: "gif" } }
}

/// Explicit, bounded recording/conversion. No camera, microphone, hidden source
/// selection or background recording. All destinations are newly chosen files.
@MainActor
final class MediaToolsManager: NSObject, ObservableObject, SCContentSharingPickerObserver, SCStreamDelegate {
    static let shared = MediaToolsManager()
    @Published private(set) var recording = false
    @Published private(set) var choosingSource = false
    @Published private(set) var finalizing = false
    @Published private(set) var converting = false
    @Published private(set) var message: String?
    @Published private(set) var inputName: String?
    @Published private(set) var duration = 0.0
    @Published private(set) var lastOutput: URL?
    private var input: URL?
    private var destination: URL?
    private var recordingFile: URL?
    private var requestGeneration = 0
    private var stream: SCStream?
    private var output: AnyObject?
    private var stopping = false
    private var recordMonitor: Task<Void, Never>?
    private var conversionTask: Task<Void, Never>?
    private var exporter: AVAssetExportSession?
    private var generation = 0
    var isBusy: Bool { recording || choosingSource || finalizing || converting }
    private override init() { super.init() }
    func chooseRecording() {
        guard WorkspaceAccess.privateToolsAllowed, !isBusy else { return }
        requestGeneration += 1; let request = requestGeneration
        guard #available(macOS 15.0, *) else { message = "Integrated recording requires macOS 15. Use Apple’s Screenshot app on this Mac."; return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.mpeg4Movie]; panel.nameFieldStringValue = "Notchscape Recording.mp4"
        panel.message = "Silent screen recording. After choosing a new file, use Apple’s picker to select one window or display. Stops after 30 minutes or 2 GB, on lock, Presentation Mode, or closing Capture Studio."
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self, WorkspaceAccess.privateToolsAllowed, self.requestGeneration == request, CaptureStudioController.shared.window?.isVisible == true else { return }
                guard !self.isBusy, !FileManager.default.fileExists(atPath: url.path) else { self.message = "Choose a new filename; existing files are never overwritten."; return }
                self.destination = url; self.choosingSource = true; self.message = nil
                let picker = SCContentSharingPicker.shared
                var config = SCContentSharingPickerConfiguration()
                config.allowedPickerModes = [.singleWindow, .singleDisplay]; config.allowsChangingSelectedContent = false
                config.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "theboringteam.boringnotch"]
                picker.defaultConfiguration = config; picker.add(self); picker.isActive = true; picker.present()
            }
        }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) { Task { @MainActor in self.cancelPicker() } }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) { Task { @MainActor in self.cancelPicker(); self.message = "Apple’s source picker couldn’t start. Check Screen Recording access in System Settings." } }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        guard #available(macOS 15.0, *) else { return }
        Task { @MainActor in
            guard self.choosingSource, WorkspaceAccess.privateToolsAllowed, CaptureStudioController.shared.window?.isVisible == true, self.destination != nil else { self.cancelPicker(); return }
            self.choosingSource = false
            do {
                let config = SCStreamConfiguration()
                let rect = filter.contentRect, scale = Double(filter.pointPixelScale)
                let factor = min(1, 3840/max(1, rect.width*scale), 2160/max(1, rect.height*scale))
                config.width = max(2, Int(rect.width*scale*factor)/2*2); config.height = max(2, Int(rect.height*scale*factor)/2*2)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30); config.queueDepth = 3
                config.capturesAudio = false; config.showsCursor = true
                if #available(macOS 15.0, *) { config.captureMicrophone = false }
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Notchscape-Recording-\(UUID().uuidString).mp4")
                self.recordingFile = temporary
                let recordingConfig = SCRecordingOutputConfiguration(); recordingConfig.outputURL = temporary; recordingConfig.videoCodecType = .h264; recordingConfig.outputFileType = .mp4
                let output = SCRecordingOutput(configuration: recordingConfig, delegate: self)
                let capture = SCStream(filter: filter, configuration: config, delegate: self)
                self.stream = capture; self.output = output; self.finalizing = true; self.stopping = false
                try capture.addRecordingOutput(output); try await capture.startCapture()
                guard WorkspaceAccess.privateToolsAllowed, !self.stopping else { self.stopRecording(); return }
                self.recording = true; self.finalizing = false; self.message = "Recording silently. Use Stop to finish the MP4."
                self.monitorRecording()
            } catch { self.finishRecording(success: false) }
        }
    }
    private func cancelPicker() {
        choosingSource = false
        SCContentSharingPicker.shared.remove(self)
        if stream == nil { SCContentSharingPicker.shared.isActive = false }
    }
    private func monitorRecording() {
        recordMonitor?.cancel()
        recordMonitor = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard #available(macOS 15.0, *), let self, recording, let output = output as? SCRecordingOutput else { return }
                if !WorkspaceAccess.privateToolsAllowed || output.recordedDuration.seconds >= 1800 || output.recordedFileSize >= 2_000_000_000 { stopRecording(); return }
            }
        }
    }
    func stopRecording() {
        cancelPicker(); recordMonitor?.cancel(); recordMonitor = nil
        guard let capture = stream, !stopping else { return }
        stopping = true; recording = false; finalizing = true
        Task { [weak self] in
            do { try await capture.stopCapture() }
            catch { self?.finishRecording(success: false) }
        }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) { Task { @MainActor in guard self.stream === stream else { return }; self.finishRecording(success: false) } }
    private func receivedRecordingCallback(_ object: AnyObject, success: Bool) {
        guard output === object else { return }
        finishRecording(success: success)
    }
    private func finishRecording(success: Bool) {
        recordMonitor?.cancel(); recordMonitor = nil; recording = false; finalizing = false; stopping = false; stream = nil; output = nil
        cancelPicker()
        if success, let destination, let recordingFile {
            do { try FileManager.default.moveItem(at: recordingFile, to: destination); lastOutput = destination; message = "Recording saved. You can select it below to trim or convert." }
            catch { lastOutput = recordingFile; message = "The destination could not be used. Your recording was kept in a temporary file—Reveal Last Export to save it elsewhere." }
        } else {
            if let recordingFile, FileManager.default.fileExists(atPath: recordingFile.path) { lastOutput = recordingFile }
            message = "Recording ended with an error. A partial temporary file may be available through Reveal Last Export."
        }
        destination = nil; recordingFile = nil
    }
    func chooseMedia() {
        guard WorkspaceAccess.privateToolsAllowed, !isBusy else { return }
        requestGeneration += 1; let request = requestGeneration
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.movie, .audio]; panel.allowsMultipleSelection = false
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self, WorkspaceAccess.privateToolsAllowed, self.requestGeneration == request else { return }
                let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard url.isFileURL, let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, bytes <= 2_000_000_000 else { self.message = "Choose a local audio or video file under 2 GB."; return }
                let asset = AVURLAsset(url: url)
                guard let time = try? await asset.load(.duration), time.seconds.isFinite, time.seconds > 0, WorkspaceAccess.privateToolsAllowed else { self.message = "This media format can’t be read by macOS."; return }
                self.input = url; self.inputName = url.lastPathComponent; self.duration = time.seconds; self.message = nil
            }
        }
    }
    func export(kind: MediaExportKind, start: Double, end: Double) {
        guard WorkspaceAccess.privateToolsAllowed, !isBusy, let input, start.isFinite, end.isFinite, start >= 0, end > start, end <= duration+0.05 else { message = "Choose valid start and end times within the selected media."; return }
        guard kind != .gif || end-start <= 15 else { message = "GIF export is limited to 15 seconds at 10 fps / 640 pixels."; return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: kind.fileExtension)!]
        panel.nameFieldStringValue = "\(input.deletingPathExtension().lastPathComponent)-export.\(kind.fileExtension)"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.beginExport(input: input, output: url, kind: kind, start: start, end: end) }
        }
    }
    private func beginExport(input: URL, output url: URL, kind: MediaExportKind, start: Double, end: Double) {
        guard WorkspaceAccess.privateToolsAllowed, !isBusy, !FileManager.default.fileExists(atPath: url.path), input.standardizedFileURL != url.standardizedFileURL else { message = "Choose a new filename. The original and existing exports are kept."; return }
        generation += 1; let token = generation; converting = true; message = "Exporting locally…"
        let scoped = input.startAccessingSecurityScopedResource()
        conversionTask = Task { [weak self] in
            defer { if scoped { input.stopAccessingSecurityScopedResource() }; if self?.generation == token { self?.converting = false; self?.exporter = nil } }
            guard let self else { return }
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Notchscape-Export-\(UUID().uuidString).\(kind.fileExtension)")
            defer { try? FileManager.default.removeItem(at: temporary) }
            do {
                if kind == .gif {
                    let task = Task.detached(priority: .utility) { try Self.makeGIF(input: input, output: temporary, start: start, end: end) }
                    try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                } else {
                    let asset = AVURLAsset(url: input)
                    guard let session = AVAssetExportSession(asset: asset, presetName: kind == .audio ? AVAssetExportPresetAppleM4A : AVAssetExportPreset1920x1080) else { throw CocoaError(.fileReadCorruptFile) }
                    exporter = session; session.outputURL = temporary; session.outputFileType = kind == .audio ? .m4a : .mp4
                    session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: end-start, preferredTimescale: 600))
                    session.metadata = []
                    await withTaskCancellationHandler { await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in session.exportAsynchronously { continuation.resume() } } } onCancel: { session.cancelExport() }
                    guard session.status == .completed else { throw session.error ?? CocoaError(.userCancelled) }
                }
                guard !Task.isCancelled, generation == token else { return }
                // moveItem fails if another process created the chosen filename
                // meanwhile. Never overwrite or delete a pre-existing output.
                try FileManager.default.moveItem(at: temporary, to: url)
                lastOutput = url; message = "Export saved. Original media was not changed."
            } catch {
                if generation == token { message = Task.isCancelled ? "Export cancelled. Original kept." : "Export couldn’t complete. Check the selected range and macOS codec support." }
            }
        }
    }
    nonisolated static func makeGIF(input: URL, output: URL, start: Double, end: Double) throws {
        guard input.isFileURL, output.isFileURL, !FileManager.default.fileExists(atPath: output.path), start.isFinite, end.isFinite, start >= 0, end > start, end-start <= 15 else { throw CocoaError(.fileWriteInvalidFileName) }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: input))
        generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        let count = min(150, max(1, Int(ceil((end-start)*10))))
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, count, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<count {
            try Task.checkCancellation()
            let image = try generator.copyCGImage(at: CMTime(seconds: start+Double(frame)/10, preferredTimescale: 600), actualTime: nil)
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
    func cancelConversion() { conversionTask?.cancel(); exporter?.cancelExport() }
    #if MEDIA_TOOLS_SMOKE
    // Test the actual export/cancellation/no-overwrite path without a picker,
    // permissions, an app window, or any screen/microphone capture.
    func exportFixture(input: URL, output: URL, kind: MediaExportKind, start: Double, end: Double) async throws {
        lastOutput = nil
        beginExport(input: input, output: output, kind: kind, start: start, end: end)
        let deadline = Date().addingTimeInterval(30)
        while converting && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        if converting { cancelConversion(); throw CocoaError(.userCancelled) }
        guard lastOutput == output, FileManager.default.fileExists(atPath: output.path) else { throw CocoaError(.fileWriteUnknown) }
    }
    #endif
    func privacyStop() { requestGeneration += 1; stopRecording(); cancelConversion(); input = nil; inputName = nil; duration = 0 }
}

@available(macOS 15.0, *)
extension MediaToolsManager: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) { }
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { Task { @MainActor in self.receivedRecordingCallback(recordingOutput, success: true) } }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) { Task { @MainActor in self.receivedRecordingCallback(recordingOutput, success: false) } }
}

#if !MEDIA_TOOLS_SMOKE
struct MediaToolsView: View {
    @ObservedObject private var media = MediaToolsManager.shared
    @State private var kind: MediaExportKind = .video
    @State private var start = 0.0
    @State private var end = 0.0
    var body: some View {
        Form {
            Section("Screen Recording") {
                HStack { Label(media.recording ? "Recording" : media.finalizing ? "Finishing recording…" : "Ready", systemImage: media.recording ? "record.circle.fill" : "record.circle").foregroundStyle(media.recording ? .red : .primary); Spacer(); Button("Choose Source & Record…") { media.chooseRecording() }.disabled(media.isBusy); Button("Stop Recording") { media.stopRecording() }.disabled(!media.recording && !media.choosingSource) }
                Text("Silent, explicit window/display capture using Apple’s picker. No microphone or system audio. Maximum 30 minutes / 2 GB; stops on lock, Presentation, or closing this window. macOS 15 or later.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Trim & Convert") {
                HStack { Text(media.inputName ?? "No media selected").lineLimit(1); Spacer(); Button("Choose Audio or Video…") { media.chooseMedia() }.disabled(media.isBusy) }
                Picker("Export format", selection: $kind) { ForEach(MediaExportKind.allCases) { Text($0.rawValue).tag($0) } }
                HStack { TextField("Start (seconds)", value: $start, format: .number); TextField("End (seconds)", value: $end, format: .number) }
                HStack { Button("Export New File…") { media.export(kind: kind, start: start, end: end) }.disabled(media.isBusy || media.inputName == nil); Button("Cancel Export") { media.cancelConversion() }.disabled(!media.converting) }
                Text("New output only. Video is limited to 1080p H.264; audio uses M4A. GIFs are capped at 15 seconds, 10 fps and 640 pixels. Conversion depends on codecs supported by macOS.").font(.caption).foregroundStyle(.secondary)
            }
            if let message = media.message { Text(message).foregroundStyle(.secondary) }
            if let output = media.lastOutput { Button("Reveal Last Export") { NSWorkspace.shared.activateFileViewerSelecting([output]) } }
        }.formStyle(.grouped).onChange(of: media.inputName) { _, _ in start = 0; end = media.duration }
    }
}

struct RecordingMenuControl: View {
    @ObservedObject private var media = MediaToolsManager.shared
    var body: some View {
        if media.recording || media.choosingSource { Button("Stop Screen Recording") { media.stopRecording() } }
        else if media.finalizing { Text("Finishing screen recording…") }
    }
}
#endif
