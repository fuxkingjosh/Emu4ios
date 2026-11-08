import AVFoundation

/// Lock-protected ring buffer of interleaved stereo Int16 samples.
final class AudioRingBuffer: @unchecked Sendable {
    private var storage: [Int16]
    private var readIndex = 0
    private var writeIndex = 0
    private var count = 0
    private let lock = NSLock()

    init(frames: Int) { storage = [Int16](repeating: 0, count: frames * 2) }

    var capacityFrames: Int { storage.count / 2 }

    func write(_ samples: UnsafePointer<Int16>, frames: Int) {
        lock.lock(); defer { lock.unlock() }
        let n = frames * 2
        for i in 0..<n {
            storage[writeIndex] = samples[i]
            writeIndex = (writeIndex + 1) % storage.count
            if count == storage.count {
                readIndex = (readIndex + 1) % storage.count // drop oldest when full
            } else {
                count += 1
            }
        }
    }

    /// Fills `left`/`right` with up to `frames` frames, padding with silence. Returns frames read.
    func read(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int, volume: Float) -> Int {
        lock.lock(); defer { lock.unlock() }
        let available = min(frames, count / 2)
        let scale = volume / 32768
        for i in 0..<available {
            left[i] = Float(storage[readIndex]) * scale
            right[i] = Float(storage[(readIndex + 1) % storage.count]) * scale
            readIndex = (readIndex + 2) % storage.count
        }
        count -= available * 2
        for i in available..<frames { left[i] = 0; right[i] = 0 }
        return available
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        readIndex = 0; writeIndex = 0; count = 0
    }

    var bufferedFrames: Int {
        lock.lock(); defer { lock.unlock() }
        return count / 2
    }
}

/// Converts a core's sample rate (anything from 31 kHz to 224 kHz) to the 48 kHz the app plays at.
final class AudioResampler {
    let inputRate: Double
    let outputRate: Double
    private let step: Double
    private var position: Double = -1 // index into the current chunk; −1 = the last frame of the previous chunk
    private var lastL: Int16 = 0, lastR: Int16 = 0
    private var output: [Int16] = []

    init(inputRate: Double, outputRate: Double = 48_000) {
        self.inputRate = inputRate
        self.outputRate = outputRate
        step = inputRate / outputRate
    }

    /// True when the core already runs at a rate the hardware is happy with.
    var isPassthrough: Bool { abs(inputRate - outputRate) < 1 }

    /// Returns resampled interleaved stereo frames (valid until the next call).
    func process(_ input: UnsafePointer<Int16>, frames n: Int, _ body: (UnsafePointer<Int16>, Int) -> Void) {
        guard n > 0 else { return }
        if isPassthrough { body(input, n); return }
        let needed = Int(Double(n) / step) + 4
        if output.count < needed * 2 { output = [Int16](repeating: 0, count: needed * 2) }
        var produced = 0
        output.withUnsafeMutableBufferPointer { out in
            while position < Double(n - 1) && produced < needed {
                let i = Int(position.rounded(.down))
                let frac = position - Double(i)
                let l0 = i < 0 ? Double(lastL) : Double(input[i * 2])
                let r0 = i < 0 ? Double(lastR) : Double(input[i * 2 + 1])
                let l1 = Double(input[(i + 1) * 2]), r1 = Double(input[(i + 1) * 2 + 1])
                out[produced * 2] = Int16(clamping: Int(l0 + (l1 - l0) * frac))
                out[produced * 2 + 1] = Int16(clamping: Int(r0 + (r1 - r0) * frac))
                produced += 1
                position += step
            }
        }
        position -= Double(n)
        lastL = input[(n - 1) * 2]
        lastR = input[(n - 1) * 2 + 1]
        output.withUnsafeBufferPointer { body($0.baseAddress!, produced) }
    }
}

final class AudioOutput {
    /// Everything is played at this rate; cores at other rates are resampled first.
    static let outputRate: Double = 48_000

    let ring: AudioRingBuffer
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    var volume: Float = 1
    var muted = false

    init(sampleRate: Double = AudioOutput.outputRate) {
        ring = AudioRingBuffer(frames: Int(sampleRate * 0.25))
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let ring = self.ring
        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let l = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let vol: Float = (self?.muted ?? true) ? 0 : (self?.volume ?? 1)
            _ = ring.read(left: l, right: r, frames: Int(frameCount), volume: vol)
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    func start() {
        let session = AVAudioSession.sharedInstance()
        // .ambient respects the silent switch and mixes with music; users can change it in Settings.
        let respectSilent = UserDefaults.standard.object(forKey: "respectSilentSwitch") as? Bool ?? true
        try? session.setCategory(respectSilent ? .ambient : .playback, options: [.mixWithOthers])
        try? session.setPreferredIOBufferDuration(0.01)
        try? session.setActive(true)
        try? engine.start()
    }

    func stop() {
        engine.stop()
        ring.clear()
    }
}
