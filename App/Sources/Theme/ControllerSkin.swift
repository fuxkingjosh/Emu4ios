import SwiftUI

enum ControlInput: String, Codable, CaseIterable, Identifiable {
    case dpad, a, b, l, r, start, select
    // PlayStation
    case cross, circle, square, triangle, l2, r2
    // Super Nintendo / DS / Genesis 6-button and friends
    case x, y, l3, r3
    // Second D-pad (Virtual Boy), analog sticks, N64 C buttons
    case dpad2, leftStick, rightStick, cUp, cDown, cLeft, cRight
    // App actions that can be placed on the controller like any button.
    case menu, fastForward, rewind, quickSave, quickLoad, screenshot, clip, keyboard

    var id: String { rawValue }

    var isAction: Bool {
        [.menu, .fastForward, .rewind, .quickSave, .quickLoad, .screenshot, .clip, .keyboard].contains(self)
    }

    /// Inputs that slide like a D-pad (finger can move around without lifting).
    var isDirectional: Bool { self == .dpad || self == .dpad2 }
    var isStick: Bool { self == .leftStick || self == .rightStick }

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
        case .keyboard: return "⌨︎"
        case .x: return "X"
        case .y: return "Y"
        case .l3: return "L3"
        case .r3: return "R3"
        case .dpad2, .leftStick, .rightStick: return ""
        case .cUp: return "C▲"
        case .cDown: return "C▼"
        case .cLeft: return "C◀"
        case .cRight: return "C▶"
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
        case .keyboard: return "Keyboard"
        case .dpad2: return "Second D-Pad"
        case .leftStick: return "Left Stick"
        case .rightStick: return "Right Stick"
        case .cUp: return "C Up"
        case .cDown: return "C Down"
        case .cLeft: return "C Left"
        case .cRight: return "C Right"
        case .l3: return "L3"
        case .r3: return "R3"
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
        case .x: return RetroPad.x
        case .y: return RetroPad.y
        case .l3: return RetroPad.l3
        case .r3: return RetroPad.r3
        case .cUp: return RetroPad.cUp
        case .cDown: return RetroPad.cDown
        case .cLeft: return RetroPad.cLeft
        case .cRight: return RetroPad.cRight
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
            // Name buttons the way this console does (Genesis "A" is the C-button bit, and so on).
            for i in l.buttons.indices where l.buttons[i].label == nil {
                l.buttons[i].label = system.label(for: l.buttons[i].input)
            }
            return l
        }
        copy.portrait = adapt(portrait, portrait: true)
        copy.landscape = adapt(landscape, portrait: false)
        return copy
    }

    /// This system's default layout, painted like `style` (used when a theme has no layout for a system yet).
    static func standard(for system: GameSystem, styledLike style: ControllerSkin) -> ControllerSkin {
        var skin = standard(for: system)
        func paint(_ layout: inout ControllerLayout, from source: ControllerLayout) {
            layout.deckColor = source.deckColor
            layout.decorations = source.decorations
            let face = source.buttons.first { !$0.input.isAction && !$0.input.isDirectional && !$0.input.isStick && $0.shape != .pill }
            let pillStyle = source.buttons.first { $0.shape == .pill }
            let pad = source.buttons.first { $0.input == .dpad }
            for i in layout.buttons.indices {
                let b = layout.buttons[i]
                let match = source.buttons.first { $0.input == b.input }
                    ?? (b.input.isDirectional || b.input.isStick ? pad : (b.shape == .pill ? pillStyle : face))
                guard let m = match else { continue }
                var n = b
                n.fill = m.fill; n.pressedFill = m.pressedFill; n.border = m.border; n.borderWidth = m.borderWidth
                n.opacity = m.opacity; n.haptic = m.haptic; n.sound = m.sound; n.hapticPattern = m.hapticPattern
                if b.input.symbolColor == nil { n.labelColor = m.labelColor }
                if b.input.isDirectional { n.dpadStyle = m.dpadStyle }
                if m.input == b.input { n.imageData = m.imageData; n.pressedImageData = m.pressedImageData }
                layout.buttons[i] = n
            }
        }
        paint(&skin.portrait, from: style.portrait)
        paint(&skin.landscape, from: style.landscape)
        skin.hapticsEnabled = style.hapticsEnabled
        skin.soundsEnabled = style.soundsEnabled
        skin.hideWhenControllerConnected = style.hideWhenControllerConnected
        return skin
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
