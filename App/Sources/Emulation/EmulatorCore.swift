import Foundation
import UIKit

/// What the app needs from an emulator engine. Only the emulation thread calls these
/// (plus setup/teardown while the loop is stopped).
protocol EmulatorCore: AnyObject {
    var system: GameSystem { get }
    var fps: Double { get }
    var sampleRate: Double { get }
    var title: String { get }
    var videoSize: (width: Int, height: Int) { get }

    /// RetroPad bits for player 1 (see `RetroPad`).
    func setButtons(_ mask: UInt32)
    /// Full input: all players, sticks, touch screen, mouse.
    func setInput(_ input: InputFrame)
    func sendKey(_ event: KeyEvent)
    /// Draws with OpenGL ES (N64, PSP).
    var usesGPU: Bool { get }
    func runFrame()
    func reset()
    /// Calls `body` with the current frame: RGBX pixels, width, height, row stride in pixels.
    func withPixels(_ body: (UnsafePointer<UInt32>, Int, Int, Int) -> Void)
    func readAudio(into buffer: UnsafeMutablePointer<Int16>, maxFrames: Int) -> Int

    func saveState(withSaveData: Bool) -> Data?
    @discardableResult func loadState(_ data: Data) -> Bool
    func saveState(to url: URL) -> Bool
    func loadState(from url: URL) -> Bool

    @discardableResult func addCheat(name: String, code: String) -> Bool
    func clearCheats()
    /// Writes battery saves / memory cards to disk.
    func flushSave()
}

extension EmulatorCore {
    func saveState() -> Data? { saveState(withSaveData: false) }
    func setInput(_ input: InputFrame) { setButtons(input.ports[0] & 0xFFFF) }
    func sendKey(_ event: KeyEvent) {}
    var usesGPU: Bool { false }
}

enum EmulatorCores {
    /// Picks the right engine for a game.
    static func make(system: GameSystem, romURL: URL, saveURL: URL) -> EmulatorCore? {
        if system.usesLibretro {
            return LibretroCore(system: system, contentURL: romURL, saveURL: saveURL)
        }
        return MGBACore(romURL: romURL, saveURL: saveURL)
    }

    /// Why a game couldn't start, shown to the player.
    static func problem(for system: GameSystem) -> String? {
        if let fw = system.coreFramework, CoreRegistry.path(for: fw) == nil {
            return "The \(system.name) emulator isn't in this build of Emu4ios."
        }
        let missing = system.requiredBIOS.filter {
            !FileManager.default.fileExists(atPath: biosFolder.appendingPathComponent($0).path)
        }
        if !missing.isEmpty {
            return "\(system.name) needs the BIOS file \(missing.joined(separator: ", ")). Put it in Files → Emu4ios → BIOS."
        }
        return nil
    }

    /// Copies bundled core data (PPSSPP fonts, shaders…) into the system folder once per app version.
    static func installCoreAssets() {
        guard let assets = Bundle.main.url(forResource: "CoreAssets", withExtension: nil) else { return }
        let version = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
        let key = "coreAssetsVersion"
        guard UserDefaults.standard.string(forKey: key) != version else { return }
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil)) ?? []
        for item in items where item.hasDirectoryPath {
            let dest = biosFolder.appendingPathComponent(item.lastPathComponent, isDirectory: true)
            try? fm.removeItem(at: dest)
            try? fm.copyItem(at: item, to: dest)
        }
        UserDefaults.standard.set(version, forKey: key)
    }

    /// Folder for optional BIOS files (Files app → Emu4ios → BIOS).
    static var biosFolder: URL {
        let url = AppPaths.documents.appendingPathComponent("BIOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

// MARK: - mGBA (Game Boy, Game Boy Color, Game Boy Advance)

final class MGBACore: EmulatorCore {
    private let handle: OpaquePointer
    let system: GameSystem
    let fps: Double
    let sampleRate: Double
    let title: String

    init?(romURL: URL, saveURL: URL) {
        guard let h = e4_create(romURL.path, saveURL.path) else { return nil }
        handle = h
        system = GameSystem(e4_system(h)) ?? .gba
        let rawFPS = e4_fps(h)
        fps = rawFPS.isFinite && rawFPS > 1 ? rawFPS : 59.73
        sampleRate = Double(e4_sample_rate(h))
        var buffer = [CChar](repeating: 0, count: 32)
        e4_title(h, &buffer, buffer.count)
        title = String(cString: buffer)
    }

    deinit { e4_destroy(handle) }

    var videoSize: (width: Int, height: Int) {
        var w: UInt32 = 0, h: UInt32 = 0
        e4_video_size(handle, &w, &h)
        return (Int(w), Int(h))
    }

    func setButtons(_ mask: UInt32) {
        // RetroPad → GBA key bits.
        var keys: UInt32 = 0
        if mask & RetroPad.a != 0 { keys |= UInt32(E4ButtonA.rawValue) }
        if mask & RetroPad.b != 0 { keys |= UInt32(E4ButtonB.rawValue) }
        if mask & RetroPad.select != 0 { keys |= UInt32(E4ButtonSelect.rawValue) }
        if mask & RetroPad.start != 0 { keys |= UInt32(E4ButtonStart.rawValue) }
        if mask & RetroPad.right != 0 { keys |= UInt32(E4ButtonRight.rawValue) }
        if mask & RetroPad.left != 0 { keys |= UInt32(E4ButtonLeft.rawValue) }
        if mask & RetroPad.up != 0 { keys |= UInt32(E4ButtonUp.rawValue) }
        if mask & RetroPad.down != 0 { keys |= UInt32(E4ButtonDown.rawValue) }
        if mask & RetroPad.r != 0 { keys |= UInt32(E4ButtonR.rawValue) }
        if mask & RetroPad.l != 0 { keys |= UInt32(E4ButtonL.rawValue) }
        e4_set_buttons(handle, keys)
    }

    func runFrame() { e4_run_frame(handle) }
    func reset() { e4_reset(handle) }

    func withPixels(_ body: (UnsafePointer<UInt32>, Int, Int, Int) -> Void) {
        var stride = 0
        guard let src = e4_pixels(handle, &stride) else { return }
        let size = videoSize
        body(src, size.width, size.height, stride)
    }

    func readAudio(into buffer: UnsafeMutablePointer<Int16>, maxFrames: Int) -> Int {
        e4_read_audio(handle, buffer, maxFrames)
    }

    func saveState(withSaveData: Bool) -> Data? {
        let capacity = e4_state_size(handle) + 4096
        var data = Data(count: capacity)
        var written = 0
        let ok = data.withUnsafeMutableBytes { e4_save_state(handle, $0.baseAddress, capacity, &written, withSaveData) }
        guard ok else { return nil }
        data.count = written
        return data
    }

    @discardableResult
    func loadState(_ data: Data) -> Bool {
        data.withUnsafeBytes { e4_load_state(handle, $0.baseAddress, data.count) }
    }

    func saveState(to url: URL) -> Bool { e4_save_state_file(handle, url.path) }
    func loadState(from url: URL) -> Bool { e4_load_state_file(handle, url.path) }

    @discardableResult
    func addCheat(name: String, code: String) -> Bool { e4_add_cheat(handle, name, code) }
    func clearCheats() { e4_clear_cheats(handle) }
    func flushSave() {} // mGBA writes battery saves straight to the file
}

// MARK: - libretro cores (every other system)

final class LibretroCore: EmulatorCore {
    private let handle: OpaquePointer
    let system: GameSystem
    let fps: Double
    let sampleRate: Double
    let title: String

    let usesGPU: Bool

    init?(system: GameSystem, contentURL: URL, saveURL: URL) {
        guard let framework = system.coreFramework, let corePath = CoreRegistry.path(for: framework) else { return nil }
        EmulatorCores.installCoreAssets()
        e4lr_clear_options()
        for (key, value) in system.coreOptions { e4lr_set_option(key, value) }
        for (key, value) in CoreOptionOverrides.values(for: system) { e4lr_set_option(key, value) }
        guard let h = e4lr_create(corePath, contentURL.path, saveURL.path, EmulatorCores.biosFolder.path) else { return nil }
        handle = h
        self.system = system
        fps = e4lr_fps(h)
        sampleRate = e4lr_sample_rate(h)
        usesGPU = e4lr_uses_gpu(h)
        title = contentURL.deletingPathExtension().lastPathComponent
    }

    deinit { e4lr_destroy(handle) }

    var videoSize: (width: Int, height: Int) {
        var w: UInt32 = 0, h: UInt32 = 0
        e4lr_video_size(handle, &w, &h)
        return (Int(w), Int(h))
    }

    func setButtons(_ mask: UInt32) { e4lr_set_buttons(handle, mask & 0xFFFF) }

    func setInput(_ input: InputFrame) {
        for port in 0..<4 {
            let bits = input.ports[port]
            e4lr_set_port_buttons(handle, UInt32(port), bits & 0xFFFF)
            var right = input.sticks[port][1]
            // N64 C buttons are the right stick pushed all the way.
            if bits & RetroPad.cButtons != 0 {
                right = .zero
                if bits & RetroPad.cUp != 0 { right.y = -32767 }
                if bits & RetroPad.cDown != 0 { right.y = 32767 }
                if bits & RetroPad.cLeft != 0 { right.x = -32767 }
                if bits & RetroPad.cRight != 0 { right.x = 32767 }
            }
            let left = input.sticks[port][0]
            e4lr_set_analog(handle, UInt32(port), 0, left.x, left.y)
            e4lr_set_analog(handle, UInt32(port), 1, right.x, right.y)
        }
        e4lr_set_pointer(handle, input.pointer.x, input.pointer.y, input.pointerDown)
        e4lr_mouse(handle, input.mouseDelta.x, input.mouseDelta.y, input.mouseLeft, input.mouseRight)
    }

    func sendKey(_ event: KeyEvent) {
        e4lr_key(handle, event.code, event.down, event.character, event.modifiers)
    }
    func runFrame() { e4lr_run_frame(handle) }
    func reset() { e4lr_reset(handle) }

    func withPixels(_ body: (UnsafePointer<UInt32>, Int, Int, Int) -> Void) {
        var w: UInt32 = 0, h: UInt32 = 0
        guard let src = e4lr_pixels(handle, &w, &h), w > 0, h > 0 else { return }
        body(src, Int(w), Int(h), Int(w))
    }

    func readAudio(into buffer: UnsafeMutablePointer<Int16>, maxFrames: Int) -> Int {
        e4lr_read_audio(handle, buffer, maxFrames)
    }

    func saveState(withSaveData: Bool) -> Data? {
        let size = e4lr_state_size(handle)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let ok = data.withUnsafeMutableBytes { e4lr_save_state(handle, $0.baseAddress, size) }
        return ok ? data : nil
    }

    @discardableResult
    func loadState(_ data: Data) -> Bool {
        data.withUnsafeBytes { e4lr_load_state(handle, $0.baseAddress, data.count) }
    }

    func saveState(to url: URL) -> Bool { e4lr_save_state_file(handle, url.path) }
    func loadState(from url: URL) -> Bool { e4lr_load_state_file(handle, url.path) }

    @discardableResult
    func addCheat(name: String, code: String) -> Bool { e4lr_add_cheat(handle, code) }
    func clearCheats() { e4lr_clear_cheats(handle) }
    func flushSave() { e4lr_flush_save(handle) }
}
