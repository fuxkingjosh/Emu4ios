import Foundation

/// The one button layout every engine speaks (libretro's "RetroPad").
/// Game Boy/GBA buttons are translated to their GBA bits inside the mGBA wrapper.
enum RetroPad {
    static let b: UInt32 = 1 << 0        // PlayStation ✕
    static let y: UInt32 = 1 << 1        // PlayStation □
    static let select: UInt32 = 1 << 2
    static let start: UInt32 = 1 << 3
    static let up: UInt32 = 1 << 4
    static let down: UInt32 = 1 << 5
    static let left: UInt32 = 1 << 6
    static let right: UInt32 = 1 << 7
    static let a: UInt32 = 1 << 8        // PlayStation ○
    static let x: UInt32 = 1 << 9        // PlayStation △
    static let l: UInt32 = 1 << 10       // L1
    static let r: UInt32 = 1 << 11       // R1
    static let l2: UInt32 = 1 << 12
    static let r2: UInt32 = 1 << 13
    static let l3: UInt32 = 1 << 14
    static let r3: UInt32 = 1 << 15

    static let directions = up | down | left | right

    // Emu4ios-only bits (above the 16 libretro buttons): N64 C buttons, sent to the core as the right stick.
    static let cUp: UInt32 = 1 << 16
    static let cDown: UInt32 = 1 << 17
    static let cLeft: UInt32 = 1 << 18
    static let cRight: UInt32 = 1 << 19
    static let cButtons = cUp | cDown | cLeft | cRight
}

/// Everything the player is doing on one frame, for every controller port.
struct InputFrame: Equatable {
    /// RetroPad bits for players 1–4.
    var ports: [UInt32] = [0, 0, 0, 0]
    /// [port][stick] — x, y in −32767…32767 (y down is positive, like libretro).
    var sticks: [[SIMD2<Int16>]] = Array(repeating: [.zero, .zero], count: 4)
    /// Touch screen (DS): −32767…32767 across the whole picture.
    var pointer = SIMD2<Int16>.zero
    var pointerDown = false
    /// Computer mouse: movement since last frame plus buttons.
    var mouseDelta = SIMD2<Int16>.zero
    var mouseLeft = false
    var mouseRight = false
}

/// A computer-keyboard key for DOS / C64 / Amiga (libretro key code + typed character).
struct KeyEvent {
    var code: UInt32
    var down: Bool
    var character: UInt32 = 0
    var modifiers: UInt16 = 0
}
