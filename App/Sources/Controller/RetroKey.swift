import GameController

/// libretro keyboard codes (RETROK_*) for the computer systems (DOS, Commodore 64, Amiga).
enum RetroKey {
    static let backspace: UInt32 = 8
    static let tab: UInt32 = 9
    static let enter: UInt32 = 13
    static let escape: UInt32 = 27
    static let space: UInt32 = 32
    static let delete: UInt32 = 127
    static let up: UInt32 = 273
    static let down: UInt32 = 274
    static let right: UInt32 = 275
    static let left: UInt32 = 276
    static let insert: UInt32 = 277
    static let home: UInt32 = 278
    static let end: UInt32 = 279
    static let pageUp: UInt32 = 280
    static let pageDown: UInt32 = 281
    static let f1: UInt32 = 282 // F1…F12 = 282…293
    static let capsLock: UInt32 = 301
    static let rightShift: UInt32 = 303
    static let leftShift: UInt32 = 304
    static let rightCtrl: UInt32 = 305
    static let leftCtrl: UInt32 = 306
    static let rightAlt: UInt32 = 307
    static let leftAlt: UInt32 = 308

    /// Characters typed on a US keyboard that need Shift, and the key they live on.
    private static let shifted: [Character: Character] = [
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
        "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`",
    ]

    /// Key code for a typed character, and whether Shift must be held.
    static func code(for character: Character) -> (UInt32, Bool)? {
        if character == "\n" || character == "\r" { return (enter, false) }
        if character == "\t" { return (tab, false) }
        if character == " " { return (space, false) }
        if let base = shifted[character], let ascii = base.asciiValue { return (UInt32(ascii), true) }
        guard let ascii = character.asciiValue, ascii >= 32, ascii < 127 else { return nil }
        if character.isUppercase, let lower = character.lowercased().first?.asciiValue { return (UInt32(lower), true) }
        return (UInt32(ascii), false)
    }

    /// Hardware keyboard key (USB HID usage) → libretro key code.
    static func code(for key: GCKeyCode) -> UInt32? {
        let usage = Int(key.rawValue)
        switch usage {
        case 4...29: return UInt32(97 + usage - 4)          // a…z
        case 30...38: return UInt32(49 + usage - 30)        // 1…9
        case 39: return 48                                  // 0
        case 40: return enter
        case 41: return escape
        case 42: return backspace
        case 43: return tab
        case 44: return space
        case 45: return 45   // -
        case 46: return 61   // =
        case 47: return 91   // [
        case 48: return 93   // ]
        case 49: return 92   // backslash
        case 51: return 59   // ;
        case 52: return 39   // '
        case 53: return 96   // `
        case 54: return 44   // ,
        case 55: return 46   // .
        case 56: return 47   // /
        case 57: return capsLock
        case 58...69: return f1 + UInt32(usage - 58)
        case 73: return insert
        case 74: return home
        case 75: return pageUp
        case 76: return delete
        case 77: return end
        case 78: return pageDown
        case 79: return right
        case 80: return left
        case 81: return down
        case 82: return up
        case 224: return leftCtrl
        case 225: return leftShift
        case 226: return leftAlt
        case 228: return rightCtrl
        case 229: return rightShift
        case 230: return rightAlt
        default: return nil
        }
    }
}
