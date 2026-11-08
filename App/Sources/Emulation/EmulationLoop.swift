import Foundation
import QuartzCore

/// Latest video frame, shared between the emulation thread (writer) and the renderer (reader).
final class FrameBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var width: Int
    private(set) var height: Int
    private var pixels: [UInt32]
    private(set) var version: UInt64 = 0

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = [UInt32](repeating: 0, count: 256 * 224)
    }

    func write(_ fill: (UnsafeMutablePointer<UInt32>, Int, Int) -> Void, width: Int, height: Int) {
        lock.lock(); defer { lock.unlock() }
        self.width = width
        self.height = height
        pixels.withUnsafeMutableBufferPointer { fill($0.baseAddress!, width, height) }
        version &+= 1
    }

    func read(_ body: (UnsafePointer<UInt32>, Int, Int, UInt64) -> Void) {
        lock.lock(); defer { lock.unlock() }
        pixels.withUnsafeBufferPointer { body($0.baseAddress!, width, height, version) }
    }

    /// Current frame as an image (for screenshots, save-state previews and the widget).
    func makeImage(scale: Int = 1) -> CGImage? {
        var image: CGImage?
        read { ptr, w, h, _ in
            let data = Data(bytes: ptr, count: w * h * 4)
            guard let provider = CGDataProvider(data: data as CFData) else { return }
            image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
        guard scale > 1, let base = image else { return image }
        let ctx = CGContext(data: nil, width: base.width * scale, height: base.height * scale, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        ctx?.interpolationQuality = .none
        ctx?.draw(base, in: CGRect(x: 0, y: 0, width: base.width * scale, height: base.height * scale))
        return ctx?.makeImage() ?? base
    }
}

/// Runs the emulator on its own thread at the game's native speed (or faster / backwards).
final class EmulationLoop: @unchecked Sendable {
    let core: EmulatorCore
    let frame: FrameBuffer
    let audio: AudioOutput

    private let lock = NSLock()
    private var _buttons: UInt32 = 0
    private var _turboButtons: UInt32 = 0
    private var _paused = true
    private var _speed: Double = 1
    private var _rewinding = false
    private var _rewindEnabled = true
    private var pendingWork: [(EmulatorCore) -> Void] = []

    private var thread: Thread?
    private var running: Bool {
        get { lock.withLock { _running } }
        set { lock.withLock { _running = newValue } }
    }
    private var _running = false
    private let exited = DispatchSemaphore(value: 0)
    private var rewind: RewindBuffer
    private var frameCount: UInt64 = 0
    private(set) var activePlaySeconds: Double = 0

    init(core: EmulatorCore) {
        self.core = core
        let size = core.videoSize
        frame = FrameBuffer(width: size.width, height: size.height)
        audio = AudioOutput(sampleRate: core.sampleRate)
        let stateSize = core.saveState()?.count ?? 400_000
        rewind = RewindBuffer(stateSize: stateSize)
    }

    // MARK: Controls (any thread)

    var buttons: UInt32 {
        get { lock.withLock { _buttons } }
        set { lock.withLock { _buttons = newValue } }
    }
    var turboButtons: UInt32 {
        get { lock.withLock { _turboButtons } }
        set { lock.withLock { _turboButtons = newValue } }
    }
    var paused: Bool {
        get { lock.withLock { _paused } }
        set { lock.withLock { _paused = newValue } }
    }
    var speed: Double {
        get { lock.withLock { _speed } }
        set { lock.withLock { _speed = max(0.25, min(newValue, 8)) } }
    }
    var rewinding: Bool {
        get { lock.withLock { _rewinding } }
        set { lock.withLock { _rewinding = newValue && _rewindEnabled } }
    }
    var rewindEnabled: Bool {
        get { lock.withLock { _rewindEnabled } }
        set { lock.withLock { _rewindEnabled = newValue } }
    }
    var rewindSecondsAvailable: Double { lock.withLock { Double(rewind.states.count * rewind.interval) / 60 } }

    /// Runs `work` on the emulation thread between frames and waits for it to finish.
    func perform<T>(_ work: @escaping (EmulatorCore) -> T) -> T {
        if !running { return work(core) }
        let done = DispatchSemaphore(value: 0)
        var result: T!
        lock.withLock {
            pendingWork.append { core in
                result = work(core)
                done.signal()
            }
        }
        done.wait()
        return result
    }

    // MARK: Lifecycle

    func start() {
        guard !running else { return }
        running = true
        audio.start()
        let t = Thread { [weak self] in self?.run() }
        t.qualityOfService = .userInteractive
        t.name = "Emu4ios.emulation"
        thread = t
        t.start()
    }

    func stop() {
        guard running else { return }
        running = false
        _ = exited.wait(timeout: .now() + 1)
        // Let any caller blocked in perform() finish.
        lock.withLock {
            let work = pendingWork
            pendingWork.removeAll()
            work.forEach { $0(core) }
        }
        audio.stop()
    }

    // MARK: Loop

    private func run() {
        var next = CACurrentMediaTime()
        var audioScratch = [Int16](repeating: 0, count: 8_192)
        var lastTick = CACurrentMediaTime()

        while running {
            let (work, isPaused, speed, isRewinding, rewindOn, held, turbo) = lock.withLock {
                let w = pendingWork; pendingWork.removeAll()
                return (w, _paused, _speed, _rewinding, _rewindEnabled, _buttons, _turboButtons)
            }
            work.forEach { $0(core) }

            let now = CACurrentMediaTime()
            if isPaused {
                lastTick = now
                next = now
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }
            activePlaySeconds += now - lastTick
            lastTick = now

            let frameTime = 1.0 / core.fps
            if isRewinding {
                // Step back through saved states, roughly 3x speed.
                if frameCount % 3 == 0, let state = lock.withLock({ rewind.pop() }) {
                    core.loadState(state)
                }
                core.setButtons(0)
                core.runFrame()
                _ = core.readAudio(into: &audioScratch, maxFrames: 4_096) // discard audio while rewinding
                publishFrame()
                frameCount &+= 1
                next += frameTime
            } else {
                // Fast-forward runs several frames per display frame, only showing the last.
                let framesThisTick = max(1, Int(speed.rounded(.down)))
                for i in 0..<framesThisTick {
                    let turboOn = (frameCount / 4) % 2 == 0
                    core.setButtons(held | (turboOn ? turbo : 0))
                    core.runFrame()
                    frameCount &+= 1
                    let produced = audioScratch.withUnsafeMutableBufferPointer {
                        core.readAudio(into: $0.baseAddress!, maxFrames: 4_096)
                    }
                    if speed <= 1.01, produced > 0 {
                        audioScratch.withUnsafeBufferPointer {
                            audio.ring.write($0.baseAddress!, frames: produced)
                            ClipRecorder.shared.appendAudio(samples: $0.baseAddress!, frames: produced)
                        }
                    }
                    if rewindOn {
                        lock.withLock { rewind.tick { core.saveState() } }
                    }
                    if i == framesThisTick - 1 {
                        publishFrame()
                        if speed <= 1.01 {
                            frame.read { pixels, w, h, _ in ClipRecorder.shared.appendVideo(pixels: pixels, width: w, height: h) }
                        }
                    }
                }
                // Fractional speeds (e.g. 1.5x, 0.5x) adjust the frame time.
                let effective = speed < 1 ? speed : speed / Double(framesThisTick)
                next += frameTime / effective
            }

            // Keep audio from drifting: if the buffer runs low, run slightly faster; if high, slower.
            if speed <= 1.01, !isRewinding {
                let buffered = Double(audio.ring.bufferedFrames) / core.sampleRate
                if buffered < 0.03 { next -= frameTime * 0.05 }
                if buffered > 0.12 { next += frameTime * 0.05 }
            }

            let wait = next - CACurrentMediaTime()
            if wait > 0 {
                Thread.sleep(forTimeInterval: wait)
            } else if wait < -0.25 {
                next = CACurrentMediaTime() // we fell far behind (e.g. app was busy); don't try to catch up
            }
        }
        exited.signal()
    }

    private func publishFrame() {
        let size = core.videoSize
        frame.write({ dest, w, h in core.copyPixels(into: dest, width: w, height: h) },
                    width: size.width, height: size.height)
    }

    func clearRewind() { lock.withLock { rewind.clear() } }
}
