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
}
