import Foundation

/// Default on-screen controllers for every system. Positions are in 0…1 units of the play view,
/// so they fit any iPhone. Players can move, resize and restyle everything in the layout editor.
extension ControllerSkin {
    /// Height ÷ width of a typical modern iPhone screen (portrait).
    private static let phoneRatio = 2.17

    private enum Face {
        /// Two buttons on a diagonal, the first one up and to the right (Nintendo, Sega Master System…).
        case two(ControlInput, ControlInput)
        case one(ControlInput)
        /// Three in a row, left to right (Atari Jaguar A B C).
        case three(ControlInput, ControlInput, ControlInput)
        /// Four buttons in a diamond: top, right, bottom, left.
        case diamond(ControlInput, ControlInput, ControlInput, ControlInput)
        /// Genesis: A B C on the bottom row, X Y Z above.
        case sixButton
        /// Nintendo 64: A, B and the four C buttons.
        case n64
    }

    private struct Plan {
        var face: Face
        var shoulders: [ControlInput] = []        // left side first, then right
        var middle: [ControlInput] = [.select, .start]
        var leftStick = false
        var secondDPad = false
        var extraFace: [ControlInput] = []        // small buttons beside the face cluster
    }

    private static func plan(for system: GameSystem) -> Plan {
        switch system {
        case .gb, .gbc, .nes: return Plan(face: .two(.a, .b))
        case .gba: return Plan(face: .two(.a, .b), shoulders: [.l, .r])
        case .snes, .nds: return Plan(face: .diamond(.x, .a, .b, .y), shoulders: [.l, .r])
        case .n64: return Plan(face: .n64, shoulders: [.l, .l2, .r], middle: [.start], leftStick: true)
        case .vb: return Plan(face: .two(.a, .b), shoulders: [.l, .r], secondDPad: true)
        case .pokemini: return Plan(face: .two(.a, .b), shoulders: [.l], middle: [.select], extraFace: [.r])
        case .genesis, .segacd: return Plan(face: .sixButton, middle: [.select, .start])
        case .sms, .sg1000, .gamegear: return Plan(face: .two(.a, .b), middle: [.start])
        case .ps1: return Plan(face: .diamond(.triangle, .circle, .cross, .square), shoulders: [.l2, .l, .r2, .r])
        case .psp: return Plan(face: .diamond(.triangle, .circle, .cross, .square), shoulders: [.l, .r], leftStick: true)
        case .pce, .pcecd, .supergrafx: return Plan(face: .two(.a, .b))
        case .ngp, .ngpc, .wswan, .wswanc: return Plan(face: .two(.a, .b), middle: [.start])
        case .lynx: return Plan(face: .two(.a, .b), shoulders: [.l, .r], middle: [.start])
        case .atari2600: return Plan(face: .one(.b))
        case .atari5200: return Plan(face: .two(.a, .b))
        case .atari7800: return Plan(face: .two(.a, .b))
        case .jaguar: return Plan(face: .three(.a, .b, .y))
        case .c64, .amiga: return Plan(face: .two(.a, .b), middle: [.select, .start], extraFace: [.keyboard])
        case .dos: return Plan(face: .diamond(.x, .a, .b, .y), shoulders: [.l, .r], extraFace: [.keyboard])
        case .doom: return Plan(face: .diamond(.y, .x, .b, .a), shoulders: [.l2, .l, .r2, .r])
        }
    }

    static func standard(for system: GameSystem) -> ControllerSkin {
        let p = plan(for: system)
        var skin = ControllerSkin(portrait: portraitLayout(system, p), landscape: landscapeLayout(system, p))
        // Print each button with the name it has on that console.
        skin = skin.restyled { b in
            if b.label == nil, let label = system.label(for: b.input) {
                b.label = label
                if label.count > 2 { b.labelSize = min(b.labelSize, label.count > 4 ? 10 : 13) }
            }
            if let color = b.input.symbolColor { b.labelColor = color }
        }
        return skin
    }

    // MARK: Portrait — screen on top, controls underneath

    private static func portraitLayout(_ system: GameSystem, _ p: Plan) -> ControllerLayout {
        let R = phoneRatio
        let aspect = Double(system.screenSize.width / system.screenSize.height)
        let screenTop = 0.06
        var screenH = min(0.52, (1 / aspect) / R)
        var screenW = 1.0
        if screenH >= 0.52 { screenW = 0.52 * aspect * R }
        if system == .nds { screenH = 0.50; screenW = min(1, 0.50 * aspect * R) }
        let screen = NormRect(x: (1 - screenW) / 2, y: screenTop, w: screenW, h: screenH)

        let top = screenTop + screenH + (p.shoulders.isEmpty ? 0.03 : 0.015)
        let bottom = 0.905
        let H = bottom - top
        let s = min(1.0, max(0.62, H / 0.46))
        var buttons: [ButtonSpec] = []

        // Shoulder buttons along the top of the control area.
        var mainTop = top
        if !p.shoulders.isEmpty {
            let h = 0.045 * s, w = 0.22
            let half = (p.shoulders.count + 1) / 2
            for (i, input) in p.shoulders.enumerated() {
                let left = i < half
                let slot = left ? i : i - half
                let x = left ? 0.03 + Double(slot) * (w + 0.02) : 0.97 - w - Double(slot) * (w + 0.02)
                buttons.append(pill(input, NormRect(x: x, y: top, w: w, h: h), size: 13))
            }
            mainTop = top + h + 0.01
        }
        let middleY = bottom - 0.045 * s
        let cy = mainTop + (middleY - mainTop) * 0.5

        // Left side: D-pad and/or stick.
        let dw = 0.40 * s, dh = dw / R
        if p.leftStick && system == .n64 {
            let st = 0.36 * s
            buttons.append(ButtonSpec(input: .leftStick, frame: NormRect(x: 0.25 - st / 2, y: cy - st / R / 2, w: st, h: st / R)))
            let small = 0.2 * s
            buttons.append(dpad(.dpad, NormRect(x: 0.03, y: middleY - small / R - 0.005, w: small, h: small / R)))
        } else if p.leftStick {
            let small = 0.32 * s
            buttons.append(dpad(.dpad, NormRect(x: 0.25 - small / 2, y: cy - small / R - 0.01, w: small, h: small / R)))
            let st = 0.24 * s
            buttons.append(ButtonSpec(input: .leftStick, frame: NormRect(x: 0.25 - st / 2, y: cy + 0.01, w: st, h: st / R)))
        } else {
            buttons.append(dpad(.dpad, NormRect(x: 0.25 - dw / 2, y: cy - dh / 2, w: dw, h: dh)))
        }

        // Right side: face buttons (or the Virtual Boy's second D-pad).
        let cx = 0.745
        if p.secondDPad {
            let w2 = 0.34 * s
            buttons.append(dpad(.dpad2, NormRect(x: cx - w2 / 2, y: cy - w2 / R / 2 - 0.02, w: w2, h: w2 / R)))
            let d = 0.12 * s
            buttons.append(circle(.b, cx: cx - 0.07, cy: cy + w2 / R / 2 + 0.01, d: d))
            buttons.append(circle(.a, cx: cx + 0.09, cy: cy + w2 / R / 2 - 0.005, d: d))
        } else {
            buttons += faceButtons(p.face, cx: cx, cy: cy, s: s, R: R, landscape: false)
        }
        for (i, input) in p.extraFace.enumerated() {
            let d = 0.11 * s
            buttons.append(circle(input, cx: 0.93 - Double(i) * 0.13, cy: mainTop + d / R / 2, d: d, size: 14))
        }

        // Start / Select in the middle.
        let mw = 0.2, mh = 0.04 * s
        let totalW = Double(p.middle.count) * mw + Double(max(0, p.middle.count - 1)) * 0.04
        for (i, input) in p.middle.enumerated() {
            let x = 0.5 - totalW / 2 + Double(i) * (mw + 0.04)
            buttons.append(pill(input, NormRect(x: x, y: middleY, w: mw, h: mh), size: 11))
        }

        // App buttons on the bottom row.
        buttons.append(pill(.menu, NormRect(x: 0.44, y: 0.93, w: 0.12, h: 0.04), size: 14))
        buttons.append(pill(.fastForward, NormRect(x: 0.82, y: 0.93, w: 0.12, h: 0.04), size: 14))
        buttons.append(pill(.rewind, NormRect(x: 0.06, y: 0.93, w: 0.12, h: 0.04), size: 14))
        return ControllerLayout(screen: screen, buttons: buttons)
    }

    // MARK: Landscape — screen in the middle, controls on both sides

    private static func landscapeLayout(_ system: GameSystem, _ p: Plan) -> ControllerLayout {
        let R = 1 / phoneRatio // height of one width unit
        let aspect = Double(system.screenSize.width / system.screenSize.height)
        // Fit the screen between the two control columns.
        let maxW = 0.58, maxH = 0.88
        var w = maxW, h = w / aspect * phoneRatio
        if h > maxH { h = maxH; w = h * aspect / phoneRatio }
        var screen = NormRect(x: (1 - w) / 2, y: 0.03 + (maxH - h) / 2 * 0.3, w: w, h: h)
        if fullScreenLandscape(system) {
            // Like a real PSP: the picture fills the whole height and the controls float over it.
            let fh = 1.0, fw = min(1.0, fh * aspect / phoneRatio)
            screen = NormRect(x: (1 - fw) / 2, y: 0, w: fw, h: fh)
        }
        var buttons: [ButtonSpec] = []

        // Shoulders in the top corners.
        let half = (p.shoulders.count + 1) / 2
        for (i, input) in p.shoulders.enumerated() {
            let left = i < half
            let slot = left ? i : i - half
            let y = 0.04 + Double(half - 1 - slot) * 0.12
            buttons.append(pill(input, NormRect(x: left ? 0.02 : 0.83, y: y, w: 0.15, h: 0.10), size: 13))
        }
        let shoulderRows = Double(half)
        let colTop = 0.06 + shoulderRows * 0.12
        let colBottom = 0.84
        let cy = (colTop + colBottom) / 2 + 0.03

        // Left column.
        if p.leftStick && system == .n64 {
            let st = 0.16
            buttons.append(ButtonSpec(input: .leftStick, frame: NormRect(x: 0.11 - st / 2, y: cy - st / R / 2, w: st, h: st / R)))
            buttons.append(dpad(.dpad, NormRect(x: 0.005, y: 0.80, w: 0.08, h: 0.08 / R)))
        } else if p.leftStick {
            let dw = 0.13
            buttons.append(dpad(.dpad, NormRect(x: 0.11 - dw / 2, y: colTop, w: dw, h: dw / R)))
            let st = 0.11
            buttons.append(ButtonSpec(input: .leftStick, frame: NormRect(x: 0.11 - st / 2, y: colTop + dw / R + 0.02, w: st, h: st / R)))
        } else {
            let dw = 0.18
            buttons.append(dpad(.dpad, NormRect(x: 0.11 - dw / 2, y: cy - dw / R / 2, w: dw, h: min(0.44, dw / R))))
        }

        // Right column.
        let cx = 0.885
        if p.secondDPad {
            let dw = 0.15
            buttons.append(dpad(.dpad2, NormRect(x: cx - dw / 2, y: colTop, w: dw, h: dw / R)))
            buttons.append(circle(.b, cx: cx - 0.04, cy: colTop + dw / R + 0.10, d: 0.065, ratio: R))
            buttons.append(circle(.a, cx: cx + 0.045, cy: colTop + dw / R + 0.07, d: 0.065, ratio: R))
        } else {
            buttons += faceButtons(p.face, cx: cx, cy: cy, s: 1, R: R, landscape: true)
        }
        for (i, input) in p.extraFace.enumerated() {
            buttons.append(circle(input, cx: 0.79 - Double(i) * 0.06, cy: colTop + 0.02, d: 0.05, ratio: R, size: 13))
        }

        // Start / Select in the bottom corners, app buttons along the bottom.
        let corners: [(Double, ControlInput)] = p.middle.count == 1 ? [(0.86, p.middle[0])]
            : zip([0.03, 0.86], p.middle).map { ($0, $1) }
        for (x, input) in corners {
            buttons.append(pill(input, NormRect(x: x, y: 0.88, w: 0.11, h: 0.08), size: 10))
        }
        buttons.append(pill(.menu, NormRect(x: 0.46, y: 0.90, w: 0.08, h: 0.08), size: 13))
        buttons.append(pill(.fastForward, NormRect(x: 0.60, y: 0.90, w: 0.07, h: 0.08), size: 13))
        buttons.append(pill(.rewind, NormRect(x: 0.33, y: 0.90, w: 0.07, h: 0.08), size: 13))
        if fullScreenLandscape(system) {
            for i in buttons.indices { buttons[i].opacity = 0.45 }
        }
        return ControllerLayout(screen: screen, buttons: buttons)
    }

    /// Wide-screen and 3D consoles play full screen when the phone is sideways.
    static func fullScreenLandscape(_ system: GameSystem) -> Bool {
        [.psp, .ps1, .n64].contains(system)
    }

    // MARK: Face clusters

    /// `R` converts a width into the same physical height (portrait: ÷2.17, landscape: ×2.17).
    private static func faceButtons(_ face: Face, cx: Double, cy: Double, s: Double, R: Double, landscape: Bool) -> [ButtonSpec] {
        let k = landscape ? 0.45 : 1.0 // landscape columns are narrower in width units
        func h(_ d: Double) -> Double { d / R }
        switch face {
        case .one(let input):
            let d = 0.22 * s * k
            return [circle(input, cx: cx, cy: cy, d: d, ratio: R)]
        case .two(let first, let second):
            let d = 0.20 * s * k
            return [circle(first, cx: cx + 0.095 * s * k, cy: cy - h(d) * 0.33, d: d, ratio: R),
                    circle(second, cx: cx - 0.095 * s * k, cy: cy + h(d) * 0.33, d: d, ratio: R)]
        case .diamond(let top, let right, let bottom, let left):
            let d = 0.15 * s * k
            return [circle(top, cx: cx, cy: cy - h(d), d: d, ratio: R, size: 20),
                    circle(right, cx: cx + d, cy: cy, d: d, ratio: R, size: 20),
                    circle(bottom, cx: cx, cy: cy + h(d), d: d, ratio: R, size: 20),
                    circle(left, cx: cx - d, cy: cy, d: d, ratio: R, size: 20)]
        case .three(let first, let second, let third):
            let d = 0.14 * s * k
            return [first, second, third].enumerated().map { i, input in
                circle(input, cx: cx + (Double(i) - 1) * d * 1.1, cy: cy + h(d) * 0.3 - Double(i) * h(d) * 0.3, d: d, ratio: R)
            }
        case .sixButton:
            let d = 0.14 * s * k, small = d * 0.78
            let row = [ControlInput.y, .b, .a], upper = [ControlInput.l, .x, .r]
            var list: [ButtonSpec] = []
            for (i, input) in row.enumerated() {
                let x = cx + (Double(i) - 1) * d * 1.08
                list.append(circle(input, cx: x, cy: cy + h(d) * 0.55 - Double(i) * h(d) * 0.12, d: d, ratio: R))
            }
            for (i, input) in upper.enumerated() {
                let x = cx + (Double(i) - 1) * d * 1.08
                list.append(circle(input, cx: x, cy: cy - h(d) * 0.75 - Double(i) * h(d) * 0.12, d: small, ratio: R, size: 15))
            }
            return list
        case .n64:
            let a = 0.17 * s * k, b = 0.14 * s * k, c = 0.085 * s * k
            var list = [circle(.b, cx: cx + 0.02 * k, cy: cy + h(a) * 0.75, d: a, ratio: R),
                        circle(.y, cx: cx - 0.13 * s * k, cy: cy + h(a) * 0.35, d: b, ratio: R)]
            let ccx = cx + 0.08 * s * k, ccy = cy - h(a) * 0.55
            list += [circle(.cUp, cx: ccx, cy: ccy - h(c), d: c, ratio: R, size: 10),
                     circle(.cRight, cx: ccx + c, cy: ccy, d: c, ratio: R, size: 10),
                     circle(.cDown, cx: ccx, cy: ccy + h(c), d: c, ratio: R, size: 10),
                     circle(.cLeft, cx: ccx - c, cy: ccy, d: c, ratio: R, size: 10)]
            for i in list.indices { list[i].fill = ThemeColor(hex: list[i].input == .b ? "#3B6FE02E" : "#FFFFFF2E") }
            for i in list.indices where list[i].input.rawValue.hasPrefix("c") { list[i].labelColor = ThemeColor(hex: "#F5D142") }
            return list
        }
    }

    // MARK: Helpers

    private static func circle(_ input: ControlInput, cx: Double, cy: Double, d: Double, ratio: Double = phoneRatio, size: Double = 18) -> ButtonSpec {
        let h = d / ratio
        return ButtonSpec(input: input, frame: NormRect(x: cx - d / 2, y: cy - h / 2, w: d, h: h), labelSize: size)
    }

    private static func pill(_ input: ControlInput, _ frame: NormRect, size: Double) -> ButtonSpec {
        ButtonSpec(input: input, frame: frame, shape: .pill, labelSize: size)
    }

    private static func dpad(_ input: ControlInput, _ frame: NormRect) -> ButtonSpec {
        ButtonSpec(input: input, frame: frame, shape: .roundedRect)
    }
}
