import Foundation
import UIKit

/// Thin Swift wrapper over the C bridge. Not thread-safe: only the emulation thread touches it
/// (plus setup/teardown, which happen while the loop is stopped).
final class EmulatorCore {
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

    func setButtons(_ mask: UInt32) { e4_set_buttons(handle, mask) }
    func runFrame() { e4_run_frame(handle) }
    func reset() { e4_reset(handle) }

    /// Copies the current frame (RGBX bytes) into `dest`, tightly packed width*height.
    func copyPixels(into dest: UnsafeMutablePointer<UInt32>, width: Int, height: Int) {
        var stride = 0
        guard let src = e4_pixels(handle, &stride) else { return }
        for y in 0..<height {
            (dest + y * width).update(from: src + y * stride, count: width)
        }
    }

    func readAudio(into buffer: UnsafeMutablePointer<Int16>, maxFrames: Int) -> Int {
        e4_read_audio(handle, buffer, maxFrames)
    }

    // MARK: States

    func saveState(withSaveData: Bool = false) -> Data? {
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

    // MARK: Cheats

    @discardableResult
    func addCheat(name: String, code: String) -> Bool { e4_add_cheat(handle, name, code) }
    func clearCheats() { e4_clear_cheats(handle) }

    func peek(_ address: UInt32) -> UInt8 { e4_peek(handle, address) }
}
