import AppKit
import AVFoundation
import ImageIO

// Standalone fixture stubs: no live app, screen, account or permission access.
enum WorkspaceAccess { @MainActor static var privateToolsAllowed: Bool { true } }
@MainActor final class CaptureStudioController {
    static let shared = CaptureStudioController()
    var window: NSWindow? { nil }
}

@main struct MediaToolsSmoke {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Notchscape-Media-Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("fixture.mov"), gif = directory.appendingPathComponent("fixture.gif")
        let writer = try AVAssetWriter(outputURL: input, fileType: .mov)
        let track = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 90])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: track, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 90])
        writer.add(track); precondition(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        for frame in 0..<10 {
            while !track.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
            var buffer: CVPixelBuffer?
            precondition(CVPixelBufferCreate(kCFAllocatorDefault, 160, 90, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess)
            let pixels = buffer!; CVPixelBufferLockBaseAddress(pixels, [])
            let data = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
            let bytes = CVPixelBufferGetBytesPerRow(pixels)*90
            for i in stride(from: 0, to: bytes, by: 4) { data[i] = 255; data[i+1] = UInt8(frame*20); data[i+2] = 50; data[i+3] = 100 }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            precondition(adapter.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)))
        }
        track.markAsFinished(); await writer.finishWriting(); precondition(writer.status == .completed)
        let source = try Data(contentsOf: input)
        try MediaToolsManager.makeGIF(input: input, output: gif, start: 0, end: 0.8)
        let image = CGImageSourceCreateWithURL(gif as CFURL, nil)!
        precondition(CGImageSourceGetCount(image) == 8, "GIF frame count bounded")
        precondition(CGImageSourceCreateImageAtIndex(image, 0, nil)!.width <= 640, "GIF dimension bound")
        do { try MediaToolsManager.makeGIF(input: input, output: gif, start: 0, end: 0.8); preconditionFailure("overwrite accepted") } catch { }
        do { try MediaToolsManager.makeGIF(input: input, output: directory.appendingPathComponent("bad.gif"), start: 0, end: 16); preconditionFailure("long GIF accepted") } catch { }
        let after = try Data(contentsOf: input)
        precondition(after == source, "original unchanged")
        let mp4 = directory.appendingPathComponent("trimmed.mp4")
        let media = MediaToolsManager.shared
        try await media.exportFixture(input: input, output: mp4, kind: .video, start: 0.1, end: 0.6)
        let trimmed = AVURLAsset(url: mp4)
        let videoDuration = try await trimmed.load(.duration).seconds
        precondition(abs(videoDuration - 0.5) < 0.12, "MP4 trim uses the selected range")
        let videoTracks = try await trimmed.loadTracks(withMediaType: .video)
        precondition(videoTracks.count == 1, "MP4 contains a valid video track")
        let videoSize = try await videoTracks[0].load(.naturalSize)
        precondition(videoSize.width <= 1920 && videoSize.height <= 1080, "Video export dimension bound")
        let preservedExport = try Data(contentsOf: mp4)
        do { try await media.exportFixture(input: input, output: mp4, kind: .video, start: 0, end: 0.8); preconditionFailure("production export overwrote a file") } catch { }
        let unchangedExport = try Data(contentsOf: mp4)
        precondition(unchangedExport == preservedExport, "Existing MP4 never changes")
        let audioInput = directory.appendingPathComponent("silent-fixture.caf")
        let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let audioBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: 44_100)!
        audioBuffer.frameLength = 44_100
        for sample in 0..<44_100 { audioBuffer.floatChannelData![0][sample] = 0 }
        do { let audioFile = try AVAudioFile(forWriting: audioInput, settings: audioFormat.settings); try audioFile.write(from: audioBuffer) }
        let m4a = directory.appendingPathComponent("trimmed.m4a")
        try await media.exportFixture(input: audioInput, output: m4a, kind: .audio, start: 0.2, end: 0.7)
        let audioAsset = AVURLAsset(url: m4a)
        let audioDuration = try await audioAsset.load(.duration).seconds
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        let strayVideo = try await audioAsset.loadTracks(withMediaType: .video)
        precondition(abs(audioDuration - 0.5) < 0.12, "M4A trim uses the selected range")
        precondition(audioTracks.count == 1 && strayVideo.isEmpty, "M4A has audio only")
        let originalAfterExports = try Data(contentsOf: input)
        precondition(originalAfterExports == source, "Source video remains byte-for-byte unchanged")
        print("PASS 12 synthetic GIF/MP4/M4A and trim checks; no screen or microphone capture")
    }
}
