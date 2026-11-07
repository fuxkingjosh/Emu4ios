import SwiftUI

enum ControlInput: String, Codable, CaseIterable, Identifiable {
    case dpad, a, b, l, r, start, select
    // App actions that can be placed on the controller like any button.
    case menu, fastForward, rewind, quickSave, quickLoad, screenshot, clip

    var id: String { rawValue }

    var isAction: Bool {
        [.menu, .fastForward, .rewind, .quickSave, .quickLoad, .screenshot, .clip].contains(self)
    }

    var defaultLabel: String {
        switch self {
        case .dpad: return ""
        case .a: return "A"
        case .b: return "B"
        case .l: return "L"
        case .r: return "R"
        case .start: return "START"
        case .select: return "SELECT"
        case .menu: return "☰"
        case .fastForward: return "»"
        case .rewind: return "«"
        case .quickSave: return "SAVE"
        case .quickLoad: return "LOAD"
        case .screenshot: return "📷"
        case .clip: return "CLIP"
        }
    }

    var displayName: String {
        switch self {
        case .dpad: return "D-Pad"
        case .fastForward: return "Fast Forward"
        case .quickSave: return "Quick Save"
        case .quickLoad: return "Quick Load"
        case .clip: return "Save Clip"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// Emulator button bits for game inputs.
    var buttonMask: UInt32 {
        switch self {
        case .a: return UInt32(E4ButtonA.rawValue)
        case .b: return UInt32(E4ButtonB.rawValue)
        case .l: return UInt32(E4ButtonL.rawValue)
        case .r: return UInt32(E4ButtonR.rawValue)
        case .start: return UInt32(E4ButtonStart.rawValue)
        case .select: return UInt32(E4ButtonSelect.rawValue)
        default: return 0
        }
    }
}

enum ButtonShape: String, Codable, CaseIterable, Identifiable {
    case circle, roundedRect, pill, diamond, hexagon, square
    var id: String { rawValue }
}

enum HapticStrength: String, Codable, CaseIterable, Identifiable {
    case off, soft, light, medium, heavy, rigid
    var id: String { rawValue }
}

enum ButtonSound: String, Codable, CaseIterable, Identifiable {
    case none, click, pop, tick, retro, bubble
    var id: String { rawValue }
}

enum DPadStyle: String, Codable, CaseIterable, Identifiable {
    case cross, circlePad, fourButtons
    var id: String { rawValue }
}

/// A rectangle stored in 0...1 units of the controller area, so layouts fit any screen size.
struct NormRect: Codable, Hashable {
    var x: Double, y: Double, w: Double, h: Double
    func rect(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width, y: y * size.height, width: w * size.width, height: h * size.height)
    }
    init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    init(_ rect: CGRect, in size: CGSize) {
        x = rect.minX / max(size.width, 1); y = rect.minY / max(size.height, 1)
        w = rect.width / max(size.width, 1); h = rect.height / max(size.height, 1)
    }
}

struct ButtonSpec: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var input: ControlInput
    var frame: NormRect
    var shape: ButtonShape = .circle
    var fill = ThemeColor(hex: "#FFFFFF2E")
    var pressedFill = ThemeColor(hex: "#FFFFFF66")
    var border = ThemeColor(hex: "#FFFFFF55")
    var borderWidth: Double = 1.5
    var label: String? = nil
    var labelColor = ThemeColor(hex: "#FFFFFFE6")
    var labelSize: Double = 18
    var opacity: Double = 1
    var hidden: Bool = false
    var haptic: HapticStrength = .light
    var sound: ButtonSound = .none
    /// Rapid-fire while held.
    var turbo: Bool = false
    var dpadStyle: DPadStyle = .cross
    /// Lets diagonal presses register on the D-pad.
    var dpadDiagonals: Bool = true

    var displayLabel: String { label ?? input.defaultLabel }
}

struct ControllerLayout: Codable, Hashable {
    /// Where the game screen sits, in 0...1 units of the whole view.
    var screen: NormRect
    var buttons: [ButtonSpec]
    /// Color of the controller area (behind the buttons). Clear = show the background.
    var deckColor = ThemeColor.clear
}

struct ControllerSkin: Codable, Hashable {
    var portrait: ControllerLayout
    var landscape: ControllerLayout
    var hapticsEnabled = true
    var soundsEnabled = true
    var hideWhenControllerConnected = true

    func layout(landscape isLandscape: Bool) -> ControllerLayout {
        isLandscape ? landscape : portrait
    }

    /// Removes buttons the system doesn't have (e.g. L/R on Game Boy) and adds missing ones.
    func adapted(to system: GameSystem) -> ControllerSkin {
        var copy = self
        let allowed = Set(system.inputs)
        func adapt(_ layout: ControllerLayout, portrait: Bool) -> ControllerLayout {
            var l = layout
            l.buttons = l.buttons.filter { $0.input.isAction || allowed.contains($0.input) }
            let reference = portrait ? ControllerSkin.standard(for: system).portrait : ControllerSkin.standard(for: system).landscape
            for input in system.inputs where !l.buttons.contains(where: { $0.input == input }) {
                if let spec = reference.buttons.first(where: { $0.input == input }) { l.buttons.append(spec) }
            }
            return l
        }
        copy.portrait = adapt(portrait, portrait: true)
        copy.landscape = adapt(landscape, portrait: false)
        return copy
    }

    // MARK: Default layouts

    static func standard(for system: GameSystem) -> ControllerSkin {
        let aspect = system.screenSize.width / system.screenSize.height
        let hasShoulders = system == .gba

        // Portrait: screen on top, controls below.
        let screenH = min(0.42, 1.0 / aspect * 0.55)
        var p: [ButtonSpec] = [
            ButtonSpec(input: .dpad, frame: NormRect(x: 0.05, y: 0.60, w: 0.40, h: 0.20), shape: .roundedRect),
            ButtonSpec(input: .a, frame: NormRect(x: 0.74, y: 0.60, w: 0.20, h: 0.095)),
            ButtonSpec(input: .b, frame: NormRect(x: 0.55, y: 0.69, w: 0.20, h: 0.095)),
            ButtonSpec(input: .select, frame: NormRect(x: 0.28, y: 0.86, w: 0.20, h: 0.04), shape: .pill, labelSize: 11),
            ButtonSpec(input: .start, frame: NormRect(x: 0.52, y: 0.86, w: 0.20, h: 0.04), shape: .pill, labelSize: 11),
            ButtonSpec(input: .menu, frame: NormRect(x: 0.44, y: 0.93, w: 0.12, h: 0.04), shape: .pill, labelSize: 14),
            ButtonSpec(input: .fastForward, frame: NormRect(x: 0.82, y: 0.93, w: 0.12, h: 0.04), shape: .pill, labelSize: 14),
            ButtonSpec(input: .rewind, frame: NormRect(x: 0.06, y: 0.93, w: 0.12, h: 0.04), shape: .pill, labelSize: 14),
        ]
        if hasShoulders {
            p.append(ButtonSpec(input: .l, frame: NormRect(x: 0.03, y: 0.52, w: 0.24, h: 0.045), shape: .pill, labelSize: 14))
            p.append(ButtonSpec(input: .r, frame: NormRect(x: 0.73, y: 0.52, w: 0.24, h: 0.045), shape: .pill, labelSize: 14))
        }
        let portrait = ControllerLayout(screen: NormRect(x: 0, y: 0.06, w: 1, h: screenH), buttons: p)

        // Landscape: screen centered, controls on the sides.
        let screenW = 0.56
        var l: [ButtonSpec] = [
            ButtonSpec(input: .dpad, frame: NormRect(x: 0.03, y: 0.40, w: 0.18, h: 0.42), shape: .roundedRect),
            ButtonSpec(input: .a, frame: NormRect(x: 0.88, y: 0.42, w: 0.10, h: 0.20)),
            ButtonSpec(input: .b, frame: NormRect(x: 0.79, y: 0.60, w: 0.10, h: 0.20)),
            ButtonSpec(input: .select, frame: NormRect(x: 0.04, y: 0.88, w: 0.11, h: 0.08), shape: .pill, labelSize: 10),
            ButtonSpec(input: .start, frame: NormRect(x: 0.85, y: 0.88, w: 0.11, h: 0.08), shape: .pill, labelSize: 10),
            ButtonSpec(input: .menu, frame: NormRect(x: 0.46, y: 0.90, w: 0.08, h: 0.08), shape: .pill, labelSize: 13),
            ButtonSpec(input: .fastForward, frame: NormRect(x: 0.89, y: 0.24, w: 0.08, h: 0.10), shape: .pill, labelSize: 13),
            ButtonSpec(input: .rewind, frame: NormRect(x: 0.03, y: 0.24, w: 0.08, h: 0.10), shape: .pill, labelSize: 13),
        ]
        if hasShoulders {
            l.append(ButtonSpec(input: .l, frame: NormRect(x: 0.02, y: 0.05, w: 0.15, h: 0.12), shape: .pill, labelSize: 14))
            l.append(ButtonSpec(input: .r, frame: NormRect(x: 0.83, y: 0.05, w: 0.15, h: 0.12), shape: .pill, labelSize: 14))
        }
        let landscape = ControllerLayout(
            screen: NormRect(x: (1 - screenW) / 2, y: 0.03, w: screenW, h: 0.86), buttons: l)

        return ControllerSkin(portrait: portrait, landscape: landscape)
    }

    /// Restyles every button at once (used by built-in themes and the "apply to all" editor button).
    func restyled(_ transform: (inout ButtonSpec) -> Void) -> ControllerSkin {
        var copy = self
        for i in copy.portrait.buttons.indices { transform(&copy.portrait.buttons[i]) }
        for i in copy.landscape.buttons.indices { transform(&copy.landscape.buttons[i]) }
        return copy
    }
}
