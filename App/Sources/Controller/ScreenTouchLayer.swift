import SwiftUI
import UIKit

/// Touches on the game screen itself: the Nintendo DS touch screen, or a trackpad-style mouse for computers.
struct ScreenTouchLayer: UIViewRepresentable {
    enum Mode { case touchScreen, mouse }
    var mode: Mode
    /// The game picture inside this view (the bezel around it doesn't count).
    var pictureRect: CGRect
    var onTouch: (Double, Double, Bool) -> Void = { _, _, _ in }
    var onMouseMove: (Double, Double) -> Void = { _, _ in }
    var onMouseButtons: (Bool, Bool) -> Void = { _, _ in }

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        update(view)
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) { update(view) }

    private func update(_ view: TouchView) {
        view.mode = mode
        view.pictureRect = pictureRect
        view.onTouch = onTouch
        view.onMouseMove = onMouseMove
        view.onMouseButtons = onMouseButtons
    }

    final class TouchView: UIView {
        var mode: Mode = .touchScreen
        var pictureRect: CGRect = .zero
        var onTouch: (Double, Double, Bool) -> Void = { _, _, _ in }
        var onMouseMove: (Double, Double) -> Void = { _, _ in }
        var onMouseButtons: (Bool, Bool) -> Void = { _, _ in }

        private var tracking: UITouch?
        private var start: (point: CGPoint, time: TimeInterval) = (.zero, 0)
        private var moved = false
        private var dragging = false
        private var holdTimer: Timer?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isMultipleTouchEnabled = true
        }

        required init?(coder: NSCoder) { fatalError() }

        private func normalized(_ p: CGPoint) -> (Double, Double) {
            guard pictureRect.width > 0, pictureRect.height > 0 else { return (0.5, 0.5) }
            let x = (p.x - pictureRect.minX) / pictureRect.width
            let y = (p.y - pictureRect.minY) / pictureRect.height
            return (min(max(x, 0), 1), min(max(y, 0), 1))
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            let all = event?.touches(for: self) ?? touches
            if mode == .mouse, all.count >= 2 {
                // Two-finger tap = right click.
                tracking = nil
                holdTimer?.invalidate()
                onMouseButtons(false, true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in self?.onMouseButtons(false, false) }
                return
            }
            guard tracking == nil, let touch = touches.first else { return }
            tracking = touch
            let p = touch.location(in: self)
            start = (p, touch.timestamp)
            moved = false
            dragging = false
            switch mode {
            case .touchScreen:
                let (x, y) = normalized(p)
                onTouch(x, y, true)
            case .mouse:
                // Hold still for a moment, then drag = hold the left button (select, drag windows).
                holdTimer?.invalidate()
                holdTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                    guard let self, !self.moved else { return }
                    self.dragging = true
                    self.onMouseButtons(true, false)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = tracking, touches.contains(touch) else { return }
            let p = touch.location(in: self)
            switch mode {
            case .touchScreen:
                let (x, y) = normalized(p)
                onTouch(x, y, true)
            case .mouse:
                let prev = touch.previousLocation(in: self)
                if hypot(p.x - start.point.x, p.y - start.point.y) > 6 { moved = true }
                // Scale finger movement to the emulated screen's pixels.
                let scale = pictureRect.width > 0 ? 640 / pictureRect.width : 2
                onMouseMove(Double(p.x - prev.x) * scale, Double(p.y - prev.y) * scale)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }

        private func finish(_ touches: Set<UITouch>) {
            guard let touch = tracking, touches.contains(touch) else { return }
            tracking = nil
            holdTimer?.invalidate()
            switch mode {
            case .touchScreen:
                let (x, y) = normalized(touch.location(in: self))
                onTouch(x, y, false)
            case .mouse:
                if dragging {
                    onMouseButtons(false, false)
                } else if !moved && touch.timestamp - start.time < 0.3 {
                    // Quick tap = left click.
                    onMouseButtons(true, false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in self?.onMouseButtons(false, false) }
                }
            }
        }
    }
}

/// The iPhone keyboard, typing into DOS / C64 / Amiga games. A row of special keys sits above it.
struct ComputerKeyboard: UIViewRepresentable {
    @Binding var visible: Bool
    var onCharacter: (Character) -> Void
    var onKey: (UInt32, Bool) -> Void

    func makeUIView(context: Context) -> KeyField {
        let field = KeyField()
        field.onCharacter = onCharacter
        field.onKey = onKey
        field.onDismiss = { visible = false }
        return field
    }

    func updateUIView(_ field: KeyField, context: Context) {
        field.onCharacter = onCharacter
        field.onKey = onKey
        field.onDismiss = { visible = false }
        DispatchQueue.main.async {
            if visible && !field.isFirstResponder { field.becomeFirstResponder() }
            if !visible && field.isFirstResponder { field.resignFirstResponder() }
        }
    }

    final class KeyField: UIView, UIKeyInput {
        var onCharacter: (Character) -> Void = { _ in }
        var onKey: (UInt32, Bool) -> Void = { _, _ in }
        var onDismiss: () -> Void = {}
        private var ctrlHeld = false
        private var altHeld = false

        override var canBecomeFirstResponder: Bool { true }
        var hasText: Bool { true }
        var autocorrectionType: UITextAutocorrectionType { get { .no } set {} }
        var autocapitalizationType: UITextAutocapitalizationType { get { .none } set {} }
        var spellCheckingType: UITextSpellCheckingType { get { .no } set {} }
        var smartQuotesType: UITextSmartQuotesType { get { .no } set {} }
        var smartDashesType: UITextSmartDashesType { get { .no } set {} }
        var keyboardAppearance: UIKeyboardAppearance { get { .dark } set {} }

        func insertText(_ text: String) {
            for ch in text { onCharacter(ch) }
            releaseModifiers()
        }

        func deleteBackward() { tap(RetroKey.backspace) }

        private func tap(_ code: UInt32) {
            onKey(code, true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                self?.onKey(code, false)
                self?.releaseModifiers()
            }
        }

        private func releaseModifiers() {
            if ctrlHeld { ctrlHeld = false; onKey(RetroKey.leftCtrl, false) }
            if altHeld { altHeld = false; onKey(RetroKey.leftAlt, false) }
            refreshBar()
        }

        // MARK: Special keys bar

        private lazy var bar: UIInputView = {
            let bar = UIInputView(frame: CGRect(x: 0, y: 0, width: 0, height: 46), inputViewStyle: .keyboard)
            let scroll = UIScrollView()
            scroll.showsHorizontalScrollIndicator = false
            scroll.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: bar.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            ])
            let stack = UIStackView()
            stack.axis = .horizontal
            stack.spacing = 6
            stack.translatesAutoresizingMaskIntoConstraints = false
            scroll.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
                stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
                stack.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
                stack.heightAnchor.constraint(equalToConstant: 34),
            ])
            var keys: [(String, UInt32)] = [("Esc", RetroKey.escape), ("Ctrl", RetroKey.leftCtrl), ("Alt", RetroKey.leftAlt),
                                            ("Tab", RetroKey.tab), ("↑", RetroKey.up), ("↓", RetroKey.down),
                                            ("←", RetroKey.left), ("→", RetroKey.right), ("Enter", RetroKey.enter)]
            keys += (1...12).map { ("F\($0)", RetroKey.f1 + UInt32($0 - 1)) }
            keys += [("Del", RetroKey.delete), ("Home", RetroKey.home), ("End", RetroKey.end),
                     ("PgUp", RetroKey.pageUp), ("PgDn", RetroKey.pageDown)]
            for (title, code) in keys {
                let b = UIButton(type: .system)
                var config = UIButton.Configuration.gray()
                config.title = title
                config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
                b.configuration = config
                b.tag = Int(code)
                b.addTarget(self, action: #selector(special(_:)), for: .touchUpInside)
                stack.addArrangedSubview(b)
            }
            let done = UIButton(type: .system)
            var config = UIButton.Configuration.filled()
            config.title = "Hide"
            done.configuration = config
            done.addTarget(self, action: #selector(hide), for: .touchUpInside)
            stack.addArrangedSubview(done)
            return bar
        }()

        override var inputAccessoryView: UIView? { bar }

        @objc private func special(_ sender: UIButton) {
            let code = UInt32(sender.tag)
            switch code {
            case RetroKey.leftCtrl:
                ctrlHeld.toggle(); onKey(code, ctrlHeld)
            case RetroKey.leftAlt:
                altHeld.toggle(); onKey(code, altHeld)
            default:
                tap(code)
            }
            refreshBar()
        }

        private func refreshBar() {
            for case let b as UIButton in (bar.subviews.first?.subviews.first as? UIStackView)?.arrangedSubviews ?? [] {
                let on = (b.tag == Int(RetroKey.leftCtrl) && ctrlHeld) || (b.tag == Int(RetroKey.leftAlt) && altHeld)
                b.configuration?.baseBackgroundColor = on ? .systemBlue : nil
            }
        }

        @objc private func hide() {
            resignFirstResponder()
            onDismiss()
        }
    }
}
