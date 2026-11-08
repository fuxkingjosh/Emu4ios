import SwiftUI
import UIKit
import AudioToolbox
import AVFoundation

/// Callbacks from the controller to whoever is listening (the play session, or nothing in the editor).
struct ControllerActions {
    var press: (ControlInput, String, UInt32?, Bool) -> Void = { _, _, _, _ in }
    var direction: (String, UInt32) -> Void = { _, _ in }
    var release: (ControlInput, String) -> Void = { _, _ in }
    /// Analog stick moved: x, y in −1…1 (y down positive). Sent with 0, 0 on release.
    var analog: (ControlInput, Double, Double) -> Void = { _, _, _ in }
}

struct ControllerOverlay: UIViewRepresentable {
    var layout: ControllerLayout
    var skin: ControllerSkin
    var actions: ControllerActions

    func makeUIView(context: Context) -> ControllerTouchView {
        let view = ControllerTouchView()
        view.actions = actions
        view.apply(layout: layout, skin: skin)
        return view
    }

    func updateUIView(_ view: ControllerTouchView, context: Context) {
        view.actions = actions
        view.apply(layout: layout, skin: skin)
    }
}

final class ControllerTouchView: UIView {
    var actions = ControllerActions()
    private(set) var layout = ControllerLayout(screen: NormRect(x: 0, y: 0, w: 1, h: 0.4), buttons: [])
    private var skin: ControllerSkin?

    /// Which button each finger is on, and the D-pad direction bits it's producing.
    private var touchButtons: [ObjectIdentifier: String] = [:]
    private var dpadMasks: [ObjectIdentifier: UInt32] = [:]
    private var pressed: [String: UInt32] = [:] // button id → mask (for drawing the D-pad arms)
    private var stickOffsets: [String: CGPoint] = [:] // button id → knob position (−1…1)

    private var generators: [HapticStrength: UIImpactFeedbackGenerator] = [:]

    // Layers: pictures behind buttons → drawn buttons → picture buttons → pictures above buttons.
    private let deckCanvas = ButtonCanvasView()
    private let behindLayer = UIView()
    private let canvas = ButtonCanvasView()
    private let frontLayer = UIView()
    private var buttonImageViews: [String: UIImageView] = [:]
    private var decorationViews: [String: UIImageView] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        for layerView in [deckCanvas, behindLayer, canvas, frontLayer] {
            layerView.isUserInteractionEnabled = false
            layerView.backgroundColor = .clear
            addSubview(layerView)
        }
        canvas.contentMode = .redraw
        canvas.drawHandler = { [weak self] _ in self?.drawButtons() }
        deckCanvas.contentMode = .redraw
        deckCanvas.drawHandler = { [weak self] _ in self?.drawDeck() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for layerView in [deckCanvas, behindLayer, canvas, frontLayer] { layerView.frame = bounds }
        deckCanvas.setNeedsDisplay()
        syncImageViews()
        canvas.setNeedsDisplay()
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(layout: ControllerLayout, skin: ControllerSkin) {
        guard layout != self.layout || skin != self.skin else { return }
        self.layout = layout
        self.skin = skin
        syncImageViews()
        deckCanvas.setNeedsDisplay()
        refresh()
    }

    private func refresh() {
        canvas.setNeedsDisplay()
        for spec in layout.buttons where spec.hasImage {
            guard let view = buttonImageViews[spec.id] else { continue }
            let isPressed = pressed[spec.id] != nil
            if let pressedData = spec.pressedImageData {
                let data = isPressed ? pressedData : spec.imageData!
                if view.accessibilityIdentifier != (isPressed ? "p" : "n") {
                    view.image = AnimatedImage.image(from: data)
                    view.accessibilityIdentifier = isPressed ? "p" : "n"
                    view.startAnimating()
                }
                view.alpha = spec.opacity
            } else {
                view.alpha = spec.opacity * (isPressed ? 0.55 : 1)
                view.transform = isPressed ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
            }
        }
    }

    /// Creates/updates image views for picture buttons and decorations.
    private func syncImageViews() {
        let size = bounds.size
        var seenButtons = Set<String>()
        for spec in layout.buttons where spec.hasImage && !spec.hidden {
            seenButtons.insert(spec.id)
            let view = buttonImageViews[spec.id] ?? {
                let v = UIImageView()
                v.contentMode = .scaleAspectFit
                frontLayer.insertSubview(v, at: 0)
                buttonImageViews[spec.id] = v
                return v
            }()
            if view.accessibilityValue != "\(spec.imageData!.hashValue)" {
                view.image = AnimatedImage.image(from: spec.imageData!)
                view.accessibilityValue = "\(spec.imageData!.hashValue)"
                view.accessibilityIdentifier = "n"
                view.startAnimating()
            }
            view.transform = .identity
            view.frame = spec.frame.rect(in: size)
            view.alpha = spec.opacity
        }
        for (id, view) in buttonImageViews where !seenButtons.contains(id) {
            view.removeFromSuperview()
            buttonImageViews[id] = nil
        }

        var seenDecorations = Set<String>()
        for deco in layout.decorations {
            seenDecorations.insert(deco.id)
            let view = decorationViews[deco.id] ?? {
                let v = UIImageView()
                v.contentMode = .scaleAspectFit
                v.clipsToBounds = true
                decorationViews[deco.id] = v
                return v
            }()
            let parent = deco.aboveButtons ? frontLayer : behindLayer
            if view.superview !== parent { view.removeFromSuperview(); parent.addSubview(view) }
            if view.accessibilityValue != "\(deco.imageData.hashValue)" {
                view.image = AnimatedImage.image(from: deco.imageData)
                view.accessibilityValue = "\(deco.imageData.hashValue)"
                view.startAnimating()
            }
            view.frame = deco.frame.rect(in: size)
            view.alpha = deco.opacity
            view.layer.cornerRadius = deco.cornerRadius
        }
        for (id, view) in decorationViews where !seenDecorations.contains(id) {
            view.removeFromSuperview()
            decorationViews[id] = nil
        }
    }

    // MARK: Hit testing

    private func frame(of spec: ButtonSpec) -> CGRect { spec.frame.rect(in: bounds.size) }

    private func button(at point: CGPoint) -> ButtonSpec? {
        let visible = layout.buttons.filter { !$0.hidden }
        // Exact hit first, then a slightly larger touch area so near-misses still count.
        if let exact = visible.last(where: { frame(of: $0).contains(point) }) { return exact }
        return visible
            .filter { frame(of: $0).insetBy(dx: -14, dy: -14).contains(point) }
            .min { distance(point, frame(of: $0)) < distance(point, frame(of: $1)) }
    }

    private func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(p.x - r.midX, p.y - r.midY)
    }

    /// Virtual Boy right D-pad: same directions, different RetroPad bits.
    static func translated(_ mask: UInt32, for input: ControlInput) -> UInt32 {
        guard input == .dpad2 else { return mask }
        var out: UInt32 = 0
        if mask & RetroPad.up != 0 { out |= RetroPad.l2 }
        if mask & RetroPad.down != 0 { out |= RetroPad.l3 }
        if mask & RetroPad.left != 0 { out |= RetroPad.r2 }
        if mask & RetroPad.right != 0 { out |= RetroPad.r3 }
        return out
    }

    private func stickVector(for spec: ButtonSpec, at point: CGPoint) -> CGPoint {
        let r = frame(of: spec)
        let radius = min(r.width, r.height) / 2
        var dx = (point.x - r.midX) / (radius * 0.75)
        var dy = (point.y - r.midY) / (radius * 0.75)
        let length = hypot(dx, dy)
        if length > 1 { dx /= length; dy /= length }
        if length < 0.12 { return .zero } // dead zone
        return CGPoint(x: dx, y: dy)
    }

    private func dpadMask(for spec: ButtonSpec, at point: CGPoint) -> UInt32 {
        let r = frame(of: spec)
        let dx = (point.x - r.midX) / (r.width / 2)
        let dy = (point.y - r.midY) / (r.height / 2)
        guard hypot(dx, dy) > 0.18 else { return 0 }
        let angle = atan2(-dy, dx) * 180 / .pi // 0 = right, 90 = up
        let right = RetroPad.right, left = RetroPad.left, up = RetroPad.up, down = RetroPad.down
        if !spec.dpadDiagonals {
            switch angle {
            case -45..<45: return right
            case 45..<135: return up
            case -135 ..< -45: return down
            default: return left
            }
        }
        switch angle {
        case -22.5..<22.5: return right
        case 22.5..<67.5: return right | up
        case 67.5..<112.5: return up
        case 112.5..<157.5: return up | left
        case -67.5 ..< -22.5: return right | down
        case -112.5 ..< -67.5: return down
        case -157.5 ..< -112.5: return down | left
        default: return left
        }
    }

    // MARK: Touches

    /// Only claim touches that land on (or near) a button, so screen gestures underneath still work.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        button(at: point) != nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { handle(touch, began: true) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { handle(touch, began: false) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { end(touch) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { end(touch) }
    }

    private func handle(_ touch: UITouch, began: Bool) {
        let key = ObjectIdentifier(touch)
        let point = touch.location(in: self)
        let touchID = "\(key.hashValue)"
        let current = touchButtons[key].flatMap { id in layout.buttons.first { $0.id == id } }

        // Stay on the D-pad / stick while the finger slides around it.
        if let current, current.input.isDirectional, began == false {
            let mask = dpadMask(for: current, at: point)
            if mask != dpadMasks[key] {
                if mask != 0 { feedback(current) }
                dpadMasks[key] = mask
                pressed[current.id] = mask
                actions.direction(touchID, Self.translated(mask, for: current.input))
                refresh()
            }
            return
        }
        if let current, current.input.isStick, began == false {
            let v = stickVector(for: current, at: point)
            stickOffsets[current.id] = v
            actions.analog(current.input, v.x, v.y)
            refresh()
            return
        }

        let target = button(at: point)
        guard target?.id != current?.id else { return }

        // Finger slid off one button onto another (or onto nothing).
        if let current {
            actions.release(current.input, touchID)
            if current.input.isStick { actions.analog(current.input, 0, 0); stickOffsets[current.id] = nil }
            pressed[current.id] = nil
            touchButtons[key] = nil
        }
        guard let target else { refresh(); return }
        // Only game buttons can be slid onto; app actions need a fresh tap.
        if !began && target.input.isAction { refresh(); return }

        touchButtons[key] = target.id
        if target.input.isDirectional {
            let mask = dpadMask(for: target, at: point)
            dpadMasks[key] = mask
            pressed[target.id] = mask
            actions.press(target.input, touchID, Self.translated(mask, for: target.input), false)
        } else if target.input.isStick {
            let v = stickVector(for: target, at: point)
            stickOffsets[target.id] = v
            pressed[target.id] = 1
            actions.analog(target.input, v.x, v.y)
        } else {
            pressed[target.id] = 1
            actions.press(target.input, touchID, nil, target.turbo)
        }
        feedback(target)
        refresh()
    }

    private func end(_ touch: UITouch) {
        let key = ObjectIdentifier(touch)
        guard let id = touchButtons[key], let spec = layout.buttons.first(where: { $0.id == id }) else { return }
        actions.release(spec.input, "\(key.hashValue)")
        if spec.input.isStick { actions.analog(spec.input, 0, 0); stickOffsets[id] = nil }
        touchButtons[key] = nil
        dpadMasks[key] = nil
        pressed[id] = nil
        refresh()
    }

    // MARK: Feedback

    private func feedback(_ spec: ButtonSpec) {
        if skin?.hapticsEnabled ?? true, let pattern = spec.hapticPattern, !pattern.isEmpty {
            HapticPlayer.shared.play(pattern)
        } else if skin?.hapticsEnabled ?? true, spec.haptic != .off {
            let generator = generators[spec.haptic] ?? {
                let style: UIImpactFeedbackGenerator.FeedbackStyle
                switch spec.haptic {
                case .soft: style = .soft
                case .light: style = .light
                case .medium: style = .medium
                case .heavy: style = .heavy
                case .rigid: style = .rigid
                case .off: style = .light
                }
                let g = UIImpactFeedbackGenerator(style: style)
                generators[spec.haptic] = g
                return g
            }()
            generator.impactOccurred()
        }
        if skin?.soundsEnabled ?? true {
            ButtonSoundPlayer.play(spec.sound)
        }
    }

    // MARK: Drawing

    private func drawDeck() {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        if layout.deckColor.components.a > 0 {
            let screenBottom = layout.screen.rect(in: bounds.size)
            ctx.setFillColor(layout.deckColor.uiColor.cgColor)
            if bounds.width < bounds.height {
                ctx.fill(CGRect(x: 0, y: screenBottom.maxY, width: bounds.width, height: bounds.height - screenBottom.maxY))
            } else {
                // Everything except the game screen.
                let path = UIBezierPath(rect: bounds)
                path.append(UIBezierPath(rect: screenBottom))
                path.usesEvenOddFillRule = true
                ctx.addPath(path.cgPath)
                ctx.fillPath(using: .evenOdd)
            }
        }
    }

    private func drawButtons() {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        for spec in layout.buttons where !spec.hidden && !spec.hasImage {
            ButtonRenderer.draw(spec, in: frame(of: spec), pressedMask: pressed[spec.id], context: ctx,
                                stick: stickOffsets[spec.id] ?? .zero)
        }
    }
}

/// Plain view whose drawing is supplied by the controller.
final class ButtonCanvasView: UIView {
    var drawHandler: ((CGRect) -> Void)?
    override func draw(_ rect: CGRect) { drawHandler?(rect) }
}

enum ButtonSoundPlayer {
    static func play(_ sound: ButtonSound) {
        let id: SystemSoundID
        switch sound {
        case .none: return
        case .click: id = 1104
        case .tick: id = 1105
        case .pop: id = 1306
        case .retro: id = 1057
        case .bubble: id = 1103
        }
        AudioServicesPlaySystemSound(id)
    }
}

/// Draws one button. Shared by the live controller and the theme editor preview.
enum ButtonRenderer {
    static func path(for shape: ButtonShape, in r: CGRect) -> UIBezierPath {
        switch shape {
        case .circle: return UIBezierPath(ovalIn: r)
        case .roundedRect: return UIBezierPath(roundedRect: r, cornerRadius: min(r.width, r.height) * 0.22)
        case .pill: return UIBezierPath(roundedRect: r, cornerRadius: min(r.width, r.height) / 2)
        case .square: return UIBezierPath(roundedRect: r, cornerRadius: 3)
        case .diamond:
            let p = UIBezierPath()
            p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.midY)); p.close()
            return p
        case .hexagon:
            let p = UIBezierPath()
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3
                let pt = CGPoint(x: r.midX + cos(a) * r.width / 2, y: r.midY + sin(a) * r.height / 2)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.close()
            return p
        }
    }

    /// `scale` shrinks labels and borders for small previews (1 = real size).
    static func draw(_ spec: ButtonSpec, in r: CGRect, pressedMask: UInt32?, context ctx: CGContext, scale: CGFloat = 1,
                     stick: CGPoint = .zero) {
        var spec = spec
        spec.labelSize *= scale
        spec.borderWidth *= scale
        ctx.saveGState()
        ctx.setAlpha(spec.opacity)
        if let data = (pressedMask != nil ? spec.pressedImageData : nil) ?? spec.imageData,
           let image = AnimatedImage.image(from: data) {
            // Picture buttons (previews/editor); the live controller animates them with image views.
            let still = image.images?.first ?? image
            let fit = AVMakeRect(aspectRatio: still.size, insideRect: r)
            still.draw(in: fit)
            ctx.restoreGState()
            return
        }
        if spec.input.isDirectional {
            drawDPad(spec, in: r, mask: pressedMask ?? 0, context: ctx)
        } else if spec.input.isStick {
            drawStick(spec, in: r, offset: stick, active: pressedMask != nil)
        } else {
            let isPressed = pressedMask != nil
            let p = path(for: spec.shape, in: r.insetBy(dx: spec.borderWidth / 2, dy: spec.borderWidth / 2))
            (isPressed ? spec.pressedFill : spec.fill).uiColor.setFill()
            p.fill()
            if spec.borderWidth > 0 {
                spec.border.uiColor.setStroke()
                p.lineWidth = spec.borderWidth
                p.stroke()
            }
            drawLabel(spec.displayLabel, color: spec.labelColor.uiColor, size: spec.labelSize, in: r)
        }
        ctx.restoreGState()
    }

    private static func drawStick(_ spec: ButtonSpec, in r: CGRect, offset: CGPoint, active: Bool) {
        let side = min(r.width, r.height)
        let square = CGRect(x: r.midX - side / 2, y: r.midY - side / 2, width: side, height: side)
        let base = UIBezierPath(ovalIn: square.insetBy(dx: spec.borderWidth, dy: spec.borderWidth))
        spec.fill.uiColor.setFill(); base.fill()
        if spec.borderWidth > 0 { spec.border.uiColor.setStroke(); base.lineWidth = spec.borderWidth; base.stroke() }
        let knobSize = side * 0.48
        let travel = (side - knobSize) / 2
        let knob = UIBezierPath(ovalIn: CGRect(x: square.midX - knobSize / 2 + offset.x * travel,
                                               y: square.midY - knobSize / 2 + offset.y * travel,
                                               width: knobSize, height: knobSize))
        (active ? spec.pressedFill : spec.fill).uiColor.setFill(); knob.fill()
        spec.border.uiColor.setStroke(); knob.lineWidth = max(1, spec.borderWidth); knob.stroke()
        if let label = spec.label, !label.isEmpty {
            drawLabel(label, color: spec.labelColor.uiColor, size: spec.labelSize, in: knob.bounds)
        }
    }

    private static func drawDPad(_ spec: ButtonSpec, in r: CGRect, mask: UInt32, context ctx: CGContext) {
        let side = min(r.width, r.height)
        let square = CGRect(x: r.midX - side / 2, y: r.midY - side / 2, width: side, height: side)
        let arm = side / 3
        let up = RetroPad.up, down = RetroPad.down, left = RetroPad.left, right = RetroPad.right

        switch spec.dpadStyle {
        case .circlePad:
            let base = UIBezierPath(ovalIn: square.insetBy(dx: spec.borderWidth, dy: spec.borderWidth))
            spec.fill.uiColor.setFill(); base.fill()
            spec.border.uiColor.setStroke(); base.lineWidth = spec.borderWidth; base.stroke()
            var offset = CGPoint.zero
            if mask & up != 0 { offset.y -= arm * 0.6 }
            if mask & down != 0 { offset.y += arm * 0.6 }
            if mask & left != 0 { offset.x -= arm * 0.6 }
            if mask & right != 0 { offset.x += arm * 0.6 }
            let knob = UIBezierPath(ovalIn: CGRect(x: square.midX - arm * 0.7 + offset.x, y: square.midY - arm * 0.7 + offset.y,
                                                   width: arm * 1.4, height: arm * 1.4))
            (mask != 0 ? spec.pressedFill : spec.fill).uiColor.setFill(); knob.fill()
            spec.border.uiColor.setStroke(); knob.lineWidth = spec.borderWidth; knob.stroke()
        case .cross, .fourButtons:
            let arms: [(CGRect, UInt32, String)] = [
                (CGRect(x: square.minX + arm, y: square.minY, width: arm, height: arm), up, "▲"),
                (CGRect(x: square.minX + arm, y: square.maxY - arm, width: arm, height: arm), down, "▼"),
                (CGRect(x: square.minX, y: square.minY + arm, width: arm, height: arm), left, "◀"),
                (CGRect(x: square.maxX - arm, y: square.minY + arm, width: arm, height: arm), right, "▶"),
            ]
            if spec.dpadStyle == .cross {
                let cross = UIBezierPath()
                cross.append(UIBezierPath(roundedRect: CGRect(x: square.minX + arm, y: square.minY, width: arm, height: side), cornerRadius: arm * 0.18))
                cross.append(UIBezierPath(roundedRect: CGRect(x: square.minX, y: square.minY + arm, width: side, height: arm), cornerRadius: arm * 0.18))
                cross.usesEvenOddFillRule = false
                spec.fill.uiColor.setFill(); cross.fill()
                if spec.borderWidth > 0 { spec.border.uiColor.setStroke(); cross.lineWidth = spec.borderWidth; cross.stroke() }
                for (rect, bit, glyph) in arms {
                    if mask & bit != 0 {
                        spec.pressedFill.uiColor.setFill()
                        UIBezierPath(roundedRect: rect, cornerRadius: arm * 0.18).fill()
                    }
                    drawLabel(glyph, color: spec.labelColor.uiColor.withAlphaComponent(0.5), size: arm * 0.32, in: rect)
                }
            } else {
                for (rect, bit, glyph) in arms {
                    let p = UIBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
                    (mask & bit != 0 ? spec.pressedFill : spec.fill).uiColor.setFill(); p.fill()
                    if spec.borderWidth > 0 { spec.border.uiColor.setStroke(); p.lineWidth = spec.borderWidth; p.stroke() }
                    drawLabel(glyph, color: spec.labelColor.uiColor, size: arm * 0.35, in: rect)
                }
            }
        }
    }

    static func drawLabel(_ text: String, color: UIColor, size: CGFloat, in r: CGRect) {
        guard !text.isEmpty else { return }
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let s = NSAttributedString(string: text, attributes: attrs)
        let bounds = s.size()
        s.draw(at: CGPoint(x: r.midX - bounds.width / 2, y: r.midY - bounds.height / 2))
    }
}
