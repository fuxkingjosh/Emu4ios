import SwiftUI

enum ControlInput: String, Codable, CaseIterable, Identifiable {
    case dpad, a, b, l, r, start, select
    // PlayStation
    case cross, circle, square, triangle, l2, r2
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
        case .cross: return "✕"
        case .circle: return "○"
        case .square: return "□"
        case .triangle: return "△"
        case .l2: return "L2"
        case .r2: return "R2"
        }
    }

    var displayName: String {
        switch self {
        case .dpad: return "D-Pad"
        case .fastForward: return "Fast Forward"
        case .quickSave: return "Quick Save"
        case .quickLoad: return "Quick Load"
        case .clip: return "Save Clip"
        case .l2: return "L2"
        case .r2: return "R2"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// RetroPad bits for game inputs.
    var buttonMask: UInt32 {
        switch self {
        case .a, .circle: return RetroPad.a
        case .b, .cross: return RetroPad.b
        case .square: return RetroPad.y
        case .triangle: return RetroPad.x
        case .l: return RetroPad.l
        case .r: return RetroPad.r
        case .l2: return RetroPad.l2
        case .r2: return RetroPad.r2
        case .start: return RetroPad.start
        case .select: return RetroPad.select
        default: return 0
        }
    }

    /// PlayStation-style label colors.
    var symbolColor: ThemeColor? {
        switch self {
        case .cross: return ThemeColor(hex: "#7CB2E8")
        case .circle: return ThemeColor(hex: "#FF6B6B")
        case .square: return ThemeColor(hex: "#F49AC1")
        case .triangle: return ThemeColor(hex: "#40E2A0")
        default: return nil
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
    /// Custom picture for the button (PNG, JPEG or animated GIF). Replaces the drawn shape.
    var imageData: Data? = nil
    /// Optional picture while pressed (otherwise the normal picture dims).
    var pressedImageData: Data? = nil
    /// Custom vibration pattern; replaces `haptic` when set.
    var hapticPattern: [HapticBeat]? = nil

    var displayLabel: String { label ?? input.defaultLabel }
    var hasImage: Bool { imageData != nil }
}

/// A picture or animated GIF placed anywhere on the controller screen.
struct Decoration: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var imageData: Data
    var frame: NormRect
    var opacity: Double = 1
    /// Draw on top of the buttons (touches still pass through to the buttons).
    var aboveButtons: Bool = false
    var cornerRadius: Double = 0
}

struct ControllerLayout: Codable, Hashable {
    /// Where the game screen sits, in 0...1 units of the whole view.
    var screen: NormRect
    var buttons: [ButtonSpec]
    /// Color of the controller area (behind the buttons). Clear = show the background.
    var deckColor = ThemeColor.clear
    /// Stickers, GIFs and pictures placed on the controller.
    var decorations: [Decoration] = []
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
        if system == .ps1 { return standardPlayStation() }
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

    /// PlayStation layout: four face buttons in a diamond, two shoulder buttons per side.
    static func standardPlayStation() -> ControllerSkin {
        func face(_ input: ControlInput, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> ButtonSpec {
            var b = ButtonSpec(input: input, frame: NormRect(x: x, y: y, w: w, h: h), labelSize: 22)
            b.labelColor = input.symbolColor ?? b.labelColor
            return b
        }
        let pw = 0.15, ph = pw * 0.46 // circles on a ~9:19.5 phone
        let pcx = 0.73, pcy = 0.70
        let portrait = ControllerLayout(screen: NormRect(x: 0, y: 0.06, w: 1, h: 0.36), buttons: [
            ButtonSpec(input: .dpad, frame: NormRect(x: 0.04, y: 0.59, w: 0.40, h: 0.185), shape: .roundedRect),
            face(.triangle, pcx - pw / 2, pcy - ph * 1.5, pw, ph),
            face(.circle, pcx + pw * 0.5, pcy - ph / 2, pw, ph),
            face(.cross, pcx - pw / 2, pcy + ph * 0.5, pw, ph),
            face(.square, pcx - pw * 1.5, pcy - ph / 2, pw, ph),
            ButtonSpec(input: .l2, frame: NormRect(x: 0.03, y: 0.45, w: 0.2, h: 0.04), shape: .pill, labelSize: 13),
            ButtonSpec(input: .l, frame: NormRect(x: 0.03, y: 0.50, w: 0.2, h: 0.04), shape: .pill, label: "L1", labelSize: 13),
            ButtonSpec(input: .r2, frame: NormRect(x: 0.77, y: 0.45, w: 0.2, h: 0.04), shape: .pill, labelSize: 13),
            ButtonSpec(input: .r, frame: NormRect(x: 0.77, y: 0.50, w: 0.2, h: 0.04), shape: .pill, label: "R1", labelSize: 13),
            ButtonSpec(input: .select, frame: NormRect(x: 0.28, y: 0.86, w: 0.20, h: 0.04), shape: .pill, labelSize: 11),
            ButtonSpec(input: .start, frame: NormRect(x: 0.52, y: 0.86, w: 0.20, h: 0.04), shape: .pill, labelSize: 11),
            ButtonSpec(input: .menu, frame: NormRect(x: 0.44, y: 0.93, w: 0.12, h: 0.04), shape: .pill, labelSize: 14),
            ButtonSpec(input: .fastForward, frame: NormRect(x: 0.82, y: 0.93, w: 0.12, h: 0.04), shape: .pill, labelSize: 14),
            ButtonSpec(input: .rewind, frame: NormRect(x: 0.06, y: 0.93, w: 0.12, h: 0.04), shape: .pill, labelSize: 14),
        ])
        let lw = 0.075, lh = lw * 2.17
        let lcx = 0.905, lcy = 0.58
        let landscape = ControllerLayout(screen: NormRect(x: 0.19, y: 0.03, w: 0.62, h: 0.86), buttons: [
            ButtonSpec(input: .dpad, frame: NormRect(x: 0.02, y: 0.40, w: 0.17, h: 0.40), shape: .roundedRect),
            face(.triangle, lcx - lw / 2, lcy - lh * 1.5, lw, lh),
            face(.circle, lcx + lw * 0.5, lcy - lh / 2, lw, lh),
            face(.cross, lcx - lw / 2, lcy + lh * 0.5, lw, lh),
            face(.square, lcx - lw * 1.5, lcy - lh / 2, lw, lh),
            ButtonSpec(input: .l2, frame: NormRect(x: 0.02, y: 0.03, w: 0.12, h: 0.10), shape: .pill, labelSize: 13),
            ButtonSpec(input: .l, frame: NormRect(x: 0.02, y: 0.15, w: 0.12, h: 0.10), shape: .pill, label: "L1", labelSize: 13),
            ButtonSpec(input: .r2, frame: NormRect(x: 0.86, y: 0.03, w: 0.12, h: 0.10), shape: .pill, labelSize: 13),
            ButtonSpec(input: .r, frame: NormRect(x: 0.86, y: 0.15, w: 0.12, h: 0.10), shape: .pill, label: "R1", labelSize: 13),
            ButtonSpec(input: .select, frame: NormRect(x: 0.03, y: 0.88, w: 0.11, h: 0.08), shape: .pill, labelSize: 10),
            ButtonSpec(input: .start, frame: NormRect(x: 0.86, y: 0.88, w: 0.11, h: 0.08), shape: .pill, labelSize: 10),
            ButtonSpec(input: .menu, frame: NormRect(x: 0.46, y: 0.90, w: 0.08, h: 0.08), shape: .pill, labelSize: 13),
            ButtonSpec(input: .fastForward, frame: NormRect(x: 0.86, y: 0.27, w: 0.06, h: 0.09), shape: .pill, labelSize: 13),
            ButtonSpec(input: .rewind, frame: NormRect(x: 0.08, y: 0.27, w: 0.06, h: 0.09), shape: .pill, labelSize: 13),
        ])
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

// MARK: - Tolerant decoding (fills in defaults for missing fields)

extension ControllerSkin {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ControllerSkin.standard(for: .gba)
        self.init(portrait: c.value(.portrait, fallback.portrait), landscape: c.value(.landscape, fallback.landscape))
        hapticsEnabled = c.value(.hapticsEnabled, hapticsEnabled)
        soundsEnabled = c.value(.soundsEnabled, soundsEnabled)
        hideWhenControllerConnected = c.value(.hideWhenControllerConnected, hideWhenControllerConnected)
    }
}

extension ControllerLayout {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(screen: c.value(.screen, NormRect(x: 0, y: 0.06, w: 1, h: 0.4)),
                  buttons: c.value(.buttons, []))
        deckColor = c.value(.deckColor, deckColor)
        decorations = c.value(.decorations, decorations)
    }
}

extension ButtonSpec {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(input: try c.decode(ControlInput.self, forKey: .input),
                  frame: try c.decode(NormRect.self, forKey: .frame))
        id = c.value(.id, id)
        shape = c.value(.shape, shape)
        fill = c.value(.fill, fill)
        pressedFill = c.value(.pressedFill, pressedFill)
        border = c.value(.border, border)
        borderWidth = c.value(.borderWidth, borderWidth)
        label = c.value(.label, label)
        labelColor = c.value(.labelColor, labelColor)
        labelSize = c.value(.labelSize, labelSize)
        opacity = c.value(.opacity, opacity)
        hidden = c.value(.hidden, hidden)
        haptic = c.value(.haptic, haptic)
        sound = c.value(.sound, sound)
        turbo = c.value(.turbo, turbo)
        dpadStyle = c.value(.dpadStyle, dpadStyle)
        dpadDiagonals = c.value(.dpadDiagonals, dpadDiagonals)
        imageData = c.value(.imageData, imageData)
        pressedImageData = c.value(.pressedImageData, pressedImageData)
        hapticPattern = c.value(.hapticPattern, hapticPattern)
    }
}

extension Decoration {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(imageData: try c.decode(Data.self, forKey: .imageData), frame: try c.decode(NormRect.self, forKey: .frame))
        id = c.value(.id, id)
        opacity = c.value(.opacity, opacity)
        aboveButtons = c.value(.aboveButtons, aboveButtons)
        cornerRadius = c.value(.cornerRadius, cornerRadius)
    }
}
