import GameController
import Combine

/// Bluetooth controllers (Xbox, PlayStation, MFi, Backbone…) and hardware keyboards.
@MainActor
final class PhysicalInput: ObservableObject {
    @Published private(set) var controllerConnected = false
    @Published private(set) var controllerName: String?

    var onButtons: ((UInt32) -> Void)?
    var onAction: ((ControlInput) -> Void)?
    var onActionReleased: ((ControlInput) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var keyboardMask: UInt32 = 0
    private var padMask: UInt32 = 0

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(center.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setupKeyboard() }
        })
        GCController.startWirelessControllerDiscovery {}
        refresh()
        setupKeyboard()
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func refresh() {
        let pad = GCController.controllers().first { $0.extendedGamepad != nil }
        #if targetEnvironment(simulator)
        // The Simulator always reports a virtual controller; keep touch controls visible there.
        controllerConnected = false
        #else
        controllerConnected = pad != nil
        #endif
        controllerName = pad?.vendorName
        guard let gamepad = pad?.extendedGamepad else { return }
        gamepad.valueChangedHandler = { [weak self] gamepad, _ in
            Task { @MainActor in self?.read(gamepad) }
        }
        // Menu / home buttons open the in-game menu.
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { Task { @MainActor in self?.onAction?(.menu) } }
        }
    }

    private func read(_ g: GCExtendedGamepad) {
        var mask: UInt32 = 0
        func bit(_ b: E4Button) -> UInt32 { UInt32(b.rawValue) }
        // Nintendo layout: east = A, south = B.
        if g.buttonB.isPressed { mask |= bit(E4ButtonA) }
        if g.buttonA.isPressed { mask |= bit(E4ButtonB) }
        if g.leftShoulder.isPressed { mask |= bit(E4ButtonL) }
        if g.rightShoulder.isPressed { mask |= bit(E4ButtonR) }
        if g.buttonOptions?.isPressed == true { mask |= bit(E4ButtonSelect) }
        let stick = g.leftThumbstick
        let dpad = g.dpad
        if dpad.up.isPressed || stick.yAxis.value > 0.5 { mask |= bit(E4ButtonUp) }
        if dpad.down.isPressed || stick.yAxis.value < -0.5 { mask |= bit(E4ButtonDown) }
        if dpad.left.isPressed || stick.xAxis.value < -0.5 { mask |= bit(E4ButtonLeft) }
        if dpad.right.isPressed || stick.xAxis.value > 0.5 { mask |= bit(E4ButtonRight) }
        // Start = Menu button is taken, so use the right stick click; triggers do speed controls.
        if g.rightThumbstickButton?.isPressed == true { mask |= bit(E4ButtonStart) }
        if g.buttonX.isPressed { mask |= bit(E4ButtonStart) }
        if g.buttonY.isPressed { mask |= bit(E4ButtonSelect) }

        if g.rightTrigger.isPressed != rightTriggerDown {
            rightTriggerDown = g.rightTrigger.isPressed
            if rightTriggerDown { onAction?(.fastForward) }
        }
        if g.leftTrigger.isPressed != leftTriggerDown {
            leftTriggerDown = g.leftTrigger.isPressed
            leftTriggerDown ? onAction?(.rewind) : onActionReleased?(.rewind)
        }
        padMask = mask
        onButtons?(padMask | keyboardMask)
    }

    private var rightTriggerDown = false
    private var leftTriggerDown = false

    // MARK: Keyboard (arrows, Z = B, X = A, A = L, S = R, Enter = Start, Shift = Select, O = quick save, P = quick load, Tab = fast forward, Esc = menu)

    private func setupKeyboard() {
        guard let keyboard = GCKeyboard.coalesced?.keyboardInput else { return }
        keyboard.keyChangedHandler = { [weak self] _, _, code, pressed in
            Task { @MainActor in self?.key(code, pressed: pressed) }
        }
    }

    private func key(_ code: GCKeyCode, pressed: Bool) {
        let map: [GCKeyCode: E4Button] = [
            .upArrow: E4ButtonUp, .downArrow: E4ButtonDown, .leftArrow: E4ButtonLeft, .rightArrow: E4ButtonRight,
            .keyX: E4ButtonA, .keyZ: E4ButtonB, .keyA: E4ButtonL, .keyS: E4ButtonR,
            .returnOrEnter: E4ButtonStart, .rightShift: E4ButtonSelect, .leftShift: E4ButtonSelect,
        ]
        if code == .escape, pressed { onAction?(.menu); return }
        if code == .tab, pressed { onAction?(.fastForward); return }
        if code == .keyO, pressed { onAction?(.quickSave); return }
        if code == .keyP, pressed { onAction?(.quickLoad); return }
        guard let button = map[code] else { return }
        let bit = UInt32(button.rawValue)
        if pressed { keyboardMask |= bit } else { keyboardMask &= ~bit }
        onButtons?(padMask | keyboardMask)
    }
}
