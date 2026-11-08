import AVFoundation
import Photos
import UIKit

/// Records gameplay continuously into short rolling video segments (game screen + game audio),
/// so the last N seconds can be saved as a clip at any moment. Doesn't use ReplayKit, so it
/// works alongside the system screen recorder and never asks for permission until you save.
final class ClipRecorder: @unchecked Sendable {
    static let shared = ClipRecorder()

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "clipsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "clipsEnabled") }
    }

    var clipLength: Double {
        get { UserDefaults.standard.object(forKey: "clipLength") as? Double ?? 30 }
        set { UserDefaults.standard.set(newValue, forKey: "clipLength") }
    }

    private let queue = DispatchQueue(label: "emu4ios.clips", qos: .utility)
    private let segmentSeconds = 10.0
    private let scale = 4
    private let recordEveryNthFrame = 2 // 30 fps clips

    private struct Segment {
        let url: URL
        let writer: AVAssetWriter
        let video: AVAssetWriterInput
        let audio: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        var videoFrames: Int64 = 0
        var audioFrames: Int64 = 0
    }

    private var current: Segment?
    private var finished: [URL] = []
    private var width = 0, height = 0
    private var fps: Double = 60
    private var sampleRate: Double = 32_768
    private var frameCounter = 0
    private var active = false
    private let folder: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ClipSegments", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    // MARK: Session lifecycle (called by the play session)

    func begin(width: Int, height: Int, fps: Double, sampleRate: Double) {
        queue.async {
            self.discardAll()
            self.width = width
            self.height = height
            self.fps = fps
            self.sampleRate = sampleRate
            self.frameCounter = 0
            self.active = self.isEnabled
        }
    }

    func end() {
        queue.async {
            self.active = false
            self.discardAll()
        }
    }

    // MARK: Feeding (called from the emulation thread)

    /// `pixels` are RGBX, `width*height`, tightly packed. Copied before returning.
    func appendVideo(pixels: UnsafePointer<UInt32>, width w: Int, height h: Int) {
        frameCounter += 1
        guard isEnabled, frameCounter % recordEveryNthFrame == 0 else { return }
        let copy = Array(UnsafeBufferPointer(start: pixels, count: w * h))
        queue.async { self.writeVideo(copy, w, h) }
    }

    /// Interleaved stereo Int16.
    func appendAudio(samples: UnsafePointer<Int16>, frames: Int) {
        guard isEnabled, frames > 0 else { return }
        let copy = Array(UnsafeBufferPointer(start: samples, count: frames * 2))
        queue.async { self.writeAudio(copy, frames) }
    }

    // MARK: Export

    func exportLastClip(_ done: @escaping @Sendable (String) -> Void) {
        guard isEnabled else {
            done("Clips are off — turn them on in Settings")
            return
        }
        queue.async {
            // Close the segment being written so it's included.
            let semaphore = DispatchSemaphore(value: 0)
            if let segment = self.current {
                self.current = nil
                self.finish(segment) { semaphore.signal() }
                semaphore.wait()
            }
            let segments = self.finished
            guard !segments.isEmpty else {
                done("Play a little first — nothing recorded yet")
                return
            }
            self.compose(segments, seconds: self.clipLength) { url in
                guard let url else {
                    done("Couldn't save the clip")
                    return
                }
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    guard status == .authorized || status == .limited else {
                        done("Allow Photos access in Settings to save clips")
                        return
                    }
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                    }, completionHandler: { ok, _ in
                        try? FileManager.default.removeItem(at: url)
                        done(ok ? "Clip saved to Photos 🎬" : "Couldn't save the clip")
                    })
                }
            }
        }
    }

    // MARK: - Writing (on `queue`)

    private func makeSegment() -> Segment? {
        guard width > 0, height > 0 else { return nil }
        let url = folder.appendingPathComponent("seg-\(UUID().uuidString).mov")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return nil }
        let outW = width * scale, outH = height * scale
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outW,
            AVVideoHeightKey: outH,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
        ])
        video.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outW,
            kCVPixelBufferHeightKey as String: outH,
        ])
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size),
        ])
        audio.expectsMediaDataInRealTime = true
        guard writer.canAdd(video), writer.canAdd(audio) else { return nil }
        writer.add(video)
        writer.add(audio)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)
        return Segment(url: url, writer: writer, video: video, audio: audio, adaptor: adaptor)
    }

    private func rotateIfNeeded() {
        guard active else { return }
        let clipFPS = fps / Double(recordEveryNthFrame)
        if let seg = current, Double(seg.videoFrames) / clipFPS >= segmentSeconds {
            current = nil
            finish(seg) {}
        }
        if current == nil { current = makeSegment() }
    }

    private func writeVideo(_ pixels: [UInt32], _ w: Int, _ h: Int) {
        guard active, w == width, h == height else { return }
        rotateIfNeeded()
        guard var seg = current, seg.video.isReadyForMoreMediaData,
              let pool = seg.adaptor.pixelBufferPool else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
            let s = scale
            pixels.withUnsafeBufferPointer { src in
                for y in 0..<h {
                    for dy in 0..<s {
                        let row = (base + (y * s + dy) * rowBytes).assumingMemoryBound(to: UInt32.self)
                        for x in 0..<w {
                            let p = src[y * w + x]
                            // RGBX (little endian) → BGRA
                            let r = p & 0xFF, g = (p >> 8) & 0xFF, b = (p >> 16) & 0xFF
                            let bgra = b | (g << 8) | (r << 16) | 0xFF00_0000
                            for dx in 0..<s { row[x * s + dx] = bgra }
                        }
                    }
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let clipFPS = Int32((fps / Double(recordEveryNthFrame)).rounded())
        let time = CMTime(value: seg.videoFrames, timescale: max(clipFPS, 1))
        if seg.adaptor.append(buffer, withPresentationTime: time) {
            seg.videoFrames += 1
            current = seg
        }
    }

    private func writeAudio(_ samples: [Int16], _ frames: Int) {
        guard active, var seg = current, seg.audio.isReadyForMoreMediaData else { return }
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2,
            mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        guard let format else { return }
        let byteCount = frames * 4
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: byteCount, blockAllocator: nil,
                                           customBlockSource: nil, offsetToData: 0, dataLength: byteCount,
                                           flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard let block else { return }
        samples.withUnsafeBytes { raw in
            _ = CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
        }
        var sample: CMSampleBuffer?
        let pts = CMTime(value: seg.audioFrames, timescale: CMTimeScale(sampleRate))
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: format,
                                                            sampleCount: frames, presentationTimeStamp: pts,
                                                            packetDescriptions: nil, sampleBufferOut: &sample)
        guard let sample, seg.audio.append(sample) else { return }
        seg.audioFrames += Int64(frames)
        current = seg
    }

    private func finish(_ seg: Segment, then: @escaping () -> Void) {
        seg.video.markAsFinished()
        seg.audio.markAsFinished()
        let url = seg.url
        seg.writer.finishWriting { [weak self] in
            guard let self else { return then() }
            self.queue.async {
                if seg.writer.status == .completed, seg.videoFrames > 0 {
                    self.finished.append(url)
                    // Keep just enough segments to cover the longest clip.
                    let keep = Int((60 / self.segmentSeconds).rounded(.up)) + 1
                    while self.finished.count > keep {
                        try? FileManager.default.removeItem(at: self.finished.removeFirst())
                    }
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
                then()
            }
        }
    }

    private func discardAll() {
        if let seg = current {
            seg.writer.cancelWriting()
            try? FileManager.default.removeItem(at: seg.url)
        }
        current = nil
        finished.forEach { try? FileManager.default.removeItem(at: $0) }
        finished.removeAll()
    }

    /// Joins the segments and keeps only the last `seconds`, exported as an MP4.
    private func compose(_ urls: [URL], seconds: Double, completion: @escaping @Sendable (URL?) -> Void) {
        Task {
            let composition = AVMutableComposition()
            guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                return completion(nil)
            }
            var cursor = CMTime.zero
            for url in urls {
                let asset = AVURLAsset(url: url)
                guard let duration = try? await asset.load(.duration), duration > .zero,
                      let v = try? await asset.loadTracks(withMediaType: .video).first else { continue }
                let range = CMTimeRange(start: .zero, duration: duration)
                try? videoTrack.insertTimeRange(range, of: v, at: cursor)
                if let a = try? await asset.loadTracks(withMediaType: .audio).first {
                    let audioDuration = (try? await a.load(.timeRange).duration) ?? duration
                    try? audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: min(audioDuration, duration)), of: a, at: cursor)
                }
                cursor = cursor + duration
            }
            guard cursor > .zero else { return completion(nil) }
            let length = CMTime(seconds: seconds, preferredTimescale: 600)
            let start = cursor > length ? cursor - length : .zero
            guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                return completion(nil)
            }
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("Emu4ios Clip \(UUID().uuidString.prefix(6)).mp4")
            export.outputURL = out
            export.outputFileType = .mp4
            export.timeRange = CMTimeRange(start: start, end: cursor)
            await export.export()
            completion(export.status == .completed ? out : nil)
        }
    }
}
