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
        pixels = [UInt32](repeating: 0, count: max(width * height, 256 * 224))
    }

    /// Copies a frame in (rows of `stride` pixels), growing the buffer if the resolution changed.
    func write(from src: UnsafePointer<UInt32>, width w: Int, height h: Int, stride: Int) {
        guard w > 0, h > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        if pixels.count < w * h { pixels = [UInt32](repeating: 0, count: w * h) }
        width = w
        height = h
        pixels.withUnsafeMutableBufferPointer { dst in
            if stride == w {
                dst.baseAddress!.update(from: src, count: w * h)
            } else {
                for y in 0..<h { (dst.baseAddress! + y * w).update(from: src + y * stride, count: w) }
            }
        }
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
    private let resampler: AudioResampler

    private let lock = NSLock()
    private var _input = InputFrame()
    private var _keys: [KeyEvent] = []
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
    private var idleTicks: UInt64 = 0
    private(set) var activePlaySeconds: Double = 0

    init(core: EmulatorCore) {
        self.core = core
        let size = core.videoSize
        frame = FrameBuffer(width: size.width, height: size.height)
        audio = AudioOutput()
        resampler = AudioResampler(inputRate: core.sampleRate, outputRate: AudioOutput.outputRate)
        if core.system.supportsRewind {
            let stateSize = core.saveState()?.count ?? 400_000
            // Big states (PlayStation ≈ 4 MB) are captured less often to keep memory in check.
            rewind = RewindBuffer(stateSize: stateSize, interval: stateSize > 1_000_000 ? 20 : 10)
        } else {
            rewind = RewindBuffer(stateSize: 1, interval: 10)
            _rewindEnabled = false
        }
    }

    // MARK: Controls (any thread)

    /// Player 1's buttons (touch controls + first controller).
    var buttons: UInt32 {
        get { lock.withLock { _input.ports[0] } }
        set { lock.withLock { _input.ports[0] = newValue } }
    }
    /// Players 2–4 (extra controllers).
    func setButtons(_ mask: UInt32, port: Int) {
        guard (1..<4).contains(port) else { return }
        lock.withLock { _input.ports[port] = mask }
    }
    /// stick 0 = left, 1 = right; values −1…1.
    func setStick(_ stick: Int, x: Double, y: Double, port: Int = 0) {
        guard (0..<4).contains(port), (0..<2).contains(stick) else { return }
        let v = SIMD2<Int16>(Int16(clamping: Int((max(-1, min(1, x)) * 32767).rounded())),
                             Int16(clamping: Int((max(-1, min(1, y)) * 32767).rounded())))
        lock.withLock { _input.sticks[port][stick] = v }
    }
    /// Touch screen position in 0…1 of the picture.
    func setPointer(x: Double, y: Double, down: Bool) {
        let px = Int16(clamping: Int(((max(0, min(1, x)) * 2) - 1) * 32767))
        let py = Int16(clamping: Int(((max(0, min(1, y)) * 2) - 1) * 32767))
        lock.withLock { _input.pointer = SIMD2(px, py); _input.pointerDown = down }
    }
    func moveMouse(dx: Double, dy: Double) {
        lock.withLock {
            _input.mouseDelta &+= SIMD2(Int16(clamping: Int(dx.rounded())), Int16(clamping: Int(dy.rounded())))
        }
    }
    func setMouseButtons(left: Bool, right: Bool) {
        lock.withLock { _input.mouseLeft = left; _input.mouseRight = right }
    }
    func sendKey(_ event: KeyEvent) { lock.withLock { _keys.append(event) } }
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
            let (work, isPaused, speed, isRewinding, rewindOn, input, turbo, keys) = lock.withLock {
                let w = pendingWork; pendingWork.removeAll()
                let k = _keys; _keys.removeAll()
                let i = _input
                _input.mouseDelta = .zero
                return (w, _paused, _speed, _rewinding, _rewindEnabled, i, _turboButtons, k)
            }
            work.forEach { $0(core) }
            // A key pressed and released between two frames would never be seen as held by cores that
            // poll the keyboard, so a release of a key pressed this frame waits for the next frame.
            var pressedNow = Set<UInt32>()
            for (i, key) in keys.enumerated() {
                if !key.down && pressedNow.contains(key.code) {
                    let rest = Array(keys[i...])
                    lock.withLock { _keys.insert(contentsOf: rest, at: 0) }
                    break
                }
                if key.down { pressedNow.insert(key.code) }
                core.sendKey(key)
            }

            let now = CACurrentMediaTime()
            if isPaused {
                lastTick = now
                next = now
                idleTicks &+= 1
                if idleTicks % 100 == 0 { e4ra_idle() } // keeps RetroAchievements' connection alive
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
                core.setInput(InputFrame())
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
                    var frameInput = input
                    frameInput.ports[0] |= turboOn ? turbo : 0
                    if i > 0 { frameInput.mouseDelta = .zero } // mouse movement counts once
                    core.setInput(frameInput)
                    core.runFrame()
                    e4ra_do_frame()
                    frameCount &+= 1
                    let produced = audioScratch.withUnsafeMutableBufferPointer {
                        core.readAudio(into: $0.baseAddress!, maxFrames: 4_096)
                    }
                    if speed <= 1.01, produced > 0 {
                        audioScratch.withUnsafeBufferPointer { raw in
                            resampler.process(raw.baseAddress!, frames: produced) { samples, frames in
                                audio.ring.write(samples, frames: frames)
                                ClipRecorder.shared.appendAudio(samples: samples, frames: frames)
                            }
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
                let buffered = Double(audio.ring.bufferedFrames) / AudioOutput.outputRate
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
        core.withPixels { src, w, h, stride in frame.write(from: src, width: w, height: h, stride: stride) }
    }

    func clearRewind() { lock.withLock { rewind.clear() } }
}
