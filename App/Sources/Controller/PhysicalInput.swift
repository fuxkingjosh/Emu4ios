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

    /// Set by the game screen: PlayStation games use the triggers as L2/R2.
    var system: GameSystem = .gba

    private func read(_ g: GCExtendedGamepad) {
        var mask: UInt32 = 0
        let isPlayStation = system == .ps1
        if isPlayStation {
            // Same positions as a PlayStation pad: south ✕, east ○, west □, north △.
            if g.buttonA.isPressed { mask |= RetroPad.b }
            if g.buttonB.isPressed { mask |= RetroPad.a }
            if g.buttonX.isPressed { mask |= RetroPad.y }
            if g.buttonY.isPressed { mask |= RetroPad.x }
            if g.leftTrigger.isPressed { mask |= RetroPad.l2 }
            if g.rightTrigger.isPressed { mask |= RetroPad.r2 }
        } else {
            // Nintendo layout: east = A, south = B; X/Y double as Start/Select.
            if g.buttonB.isPressed { mask |= RetroPad.a }
            if g.buttonA.isPressed { mask |= RetroPad.b }
            if g.buttonX.isPressed { mask |= RetroPad.start }
            if g.buttonY.isPressed { mask |= RetroPad.select }
        }
        if g.leftShoulder.isPressed { mask |= RetroPad.l }
        if g.rightShoulder.isPressed { mask |= RetroPad.r }
        if g.buttonOptions?.isPressed == true { mask |= RetroPad.select }
        if g.rightThumbstickButton?.isPressed == true { mask |= RetroPad.start }
        let stick = g.leftThumbstick
        let dpad = g.dpad
        if dpad.up.isPressed || stick.yAxis.value > 0.5 { mask |= RetroPad.up }
        if dpad.down.isPressed || stick.yAxis.value < -0.5 { mask |= RetroPad.down }
        if dpad.left.isPressed || stick.xAxis.value < -0.5 { mask |= RetroPad.left }
        if dpad.right.isPressed || stick.xAxis.value > 0.5 { mask |= RetroPad.right }

        if !isPlayStation {
            // Triggers: left = rewind (hold), right = fast forward (toggle).
            if g.rightTrigger.isPressed != rightTriggerDown {
                rightTriggerDown = g.rightTrigger.isPressed
                if rightTriggerDown { onAction?(.fastForward) }
            }
            if g.leftTrigger.isPressed != leftTriggerDown {
                leftTriggerDown = g.leftTrigger.isPressed
                if leftTriggerDown { onAction?(.rewind) } else { onActionReleased?(.rewind) }
            }
        }
        padMask = mask
        onButtons?(padMask | keyboardMask)
    }

    private var rightTriggerDown = false
    private var leftTriggerDown = false

    // MARK: Keyboard (arrows, X = A/○, Z = B/✕, C = □, V = △, A/S = L/R, Q/W = L2/R2, Enter = Start, Shift = Select,
    // O = quick save, P = quick load, Tab = fast forward, Esc = menu)

    private func setupKeyboard() {
        guard let keyboard = GCKeyboard.coalesced?.keyboardInput else { return }
        keyboard.keyChangedHandler = { [weak self] _, _, code, pressed in
            Task { @MainActor in self?.key(code, pressed: pressed) }
        }
    }

    private func key(_ code: GCKeyCode, pressed: Bool) {
        let map: [GCKeyCode: UInt32] = [
            .upArrow: RetroPad.up, .downArrow: RetroPad.down, .leftArrow: RetroPad.left, .rightArrow: RetroPad.right,
            .keyX: RetroPad.a, .keyZ: RetroPad.b, .keyA: RetroPad.l, .keyS: RetroPad.r,
            .keyC: RetroPad.y, .keyV: RetroPad.x, .keyQ: RetroPad.l2, .keyW: RetroPad.r2,
            .returnOrEnter: RetroPad.start, .rightShift: RetroPad.select, .leftShift: RetroPad.select,
        ]
        if code == .escape, pressed { onAction?(.menu); return }
        if code == .tab, pressed { onAction?(.fastForward); return }
        if code == .keyO, pressed { onAction?(.quickSave); return }
        if code == .keyP, pressed { onAction?(.quickLoad); return }
        guard let bit = map[code] else { return }
        if pressed { keyboardMask |= bit } else { keyboardMask &= ~bit }
        onButtons?(padMask | keyboardMask)
    }
}
