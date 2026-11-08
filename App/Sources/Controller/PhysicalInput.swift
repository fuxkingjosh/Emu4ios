import GameController
import Combine

/// Bluetooth controllers (Xbox, PlayStation, MFi, Backbone…) and hardware keyboards.
/// Up to four controllers are players 1–4.
@MainActor
final class PhysicalInput: ObservableObject {
    @Published private(set) var controllerConnected = false
    @Published private(set) var controllerName: String?
    @Published private(set) var playerCount = 0

    /// Buttons for a port (0 = player 1).
    var onButtons: ((UInt32, Int) -> Void)?
    /// Analog stick: stick (0 left, 1 right), x, y (−1…1, y down), port.
    var onStick: ((Int, Double, Double, Int) -> Void)?
    /// Computer systems: every key goes straight to the emulated keyboard.
    var onKey: ((UInt32, Bool) -> Void)?
    var onAction: ((ControlInput) -> Void)?
    var onActionReleased: ((ControlInput) -> Void)?

    /// Set by the game screen; decides how buttons map.
    var system: GameSystem = .gba

    private var observers: [NSObjectProtocol] = []
    private var keyboardMask: UInt32 = 0
    private var padMasks: [UInt32] = [0, 0, 0, 0]
    private var triggerState: [ObjectIdentifier: (left: Bool, right: Bool)] = [:]

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
        let pads = GCController.controllers().filter { $0.extendedGamepad != nil }
        #if targetEnvironment(simulator)
        // The Simulator always reports a virtual controller; keep touch controls visible there.
        controllerConnected = false
        #else
        controllerConnected = !pads.isEmpty
        #endif
        controllerName = pads.first?.vendorName
        playerCount = pads.count
        for (index, pad) in pads.prefix(4).enumerated() {
            pad.playerIndex = GCControllerPlayerIndex(rawValue: index) ?? .indexUnset
            guard let gamepad = pad.extendedGamepad else { continue }
            let port = index
            gamepad.valueChangedHandler = { [weak self] gamepad, _ in
                Task { @MainActor in self?.read(gamepad, port: port) }
            }
            // Menu / home buttons open the in-game menu.
            gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { Task { @MainActor in self?.onAction?(.menu) } }
            }
        }
        // Clear players whose controller went away.
        for port in pads.count..<4 where padMasks[port] != 0 {
            padMasks[port] = 0
            onButtons?(port == 0 ? keyboardMask : 0, port)
        }
    }

    private func read(_ g: GCExtendedGamepad, port: Int) {
        let has = Set(system.inputs)
        var mask: UInt32 = 0
        var triggersFree = true

        switch system {
        case .ps1, .psp:
            // Same positions as a PlayStation pad: south ✕, east ○, west □, north △.
            if g.buttonA.isPressed { mask |= RetroPad.b }
            if g.buttonB.isPressed { mask |= RetroPad.a }
            if g.buttonX.isPressed { mask |= RetroPad.y }
            if g.buttonY.isPressed { mask |= RetroPad.x }
            if has.contains(.l2) {
                if g.leftTrigger.isPressed { mask |= RetroPad.l2 }
                if g.rightTrigger.isPressed { mask |= RetroPad.r2 }
                triggersFree = false
            }
        case .genesis, .segacd:
            if g.buttonX.isPressed { mask |= RetroPad.y }   // A
            if g.buttonA.isPressed { mask |= RetroPad.b }   // B
            if g.buttonB.isPressed { mask |= RetroPad.a }   // C
            if g.buttonY.isPressed { mask |= RetroPad.x }   // Y
        case .n64:
            if g.buttonA.isPressed { mask |= RetroPad.b }   // A
            if g.buttonX.isPressed { mask |= RetroPad.y }   // B
            if g.buttonB.isPressed { mask |= RetroPad.cDown }
            if g.buttonY.isPressed { mask |= RetroPad.cLeft }
            if g.leftTrigger.isPressed { mask |= RetroPad.l2 } // Z
            if g.rightTrigger.isPressed { mask |= RetroPad.l2 }
            triggersFree = false
        default:
            // Nintendo positions: east A, south B, north X, west Y.
            if g.buttonB.isPressed { mask |= RetroPad.a }
            if g.buttonA.isPressed { mask |= RetroPad.b }
            if has.contains(.x) {
                if g.buttonY.isPressed { mask |= RetroPad.x }
                if g.buttonX.isPressed { mask |= RetroPad.y }
            } else {
                // Two-button systems: the spare face buttons work as Start / Select.
                if g.buttonX.isPressed { mask |= RetroPad.start }
                if g.buttonY.isPressed { mask |= RetroPad.select }
            }
            if has.contains(.l2) {
                if g.leftTrigger.isPressed { mask |= RetroPad.l2 }
                if g.rightTrigger.isPressed { mask |= RetroPad.r2 }
                triggersFree = false
            }
        }
        if g.leftShoulder.isPressed { mask |= RetroPad.l }
        if g.rightShoulder.isPressed { mask |= RetroPad.r }
        if g.buttonOptions?.isPressed == true { mask |= RetroPad.select }
        if has.contains(.l3) || system == .ps1 {
            if g.leftThumbstickButton?.isPressed == true { mask |= RetroPad.l3 }
            if g.rightThumbstickButton?.isPressed == true { mask |= RetroPad.r3 }
        } else if g.rightThumbstickButton?.isPressed == true {
            mask |= RetroPad.start
        }

        let stick = g.leftThumbstick
        let dpad = g.dpad
        if dpad.up.isPressed { mask |= RetroPad.up }
        if dpad.down.isPressed { mask |= RetroPad.down }
        if dpad.left.isPressed { mask |= RetroPad.left }
        if dpad.right.isPressed { mask |= RetroPad.right }
        if system.hasAnalogStick || system == .ps1 {
            onStick?(0, Double(stick.xAxis.value), Double(-stick.yAxis.value), port)
            let right = g.rightThumbstick
            if system == .n64 {
                // Right stick = C buttons.
                if right.yAxis.value > 0.5 { mask |= RetroPad.cUp }
                if right.yAxis.value < -0.5 { mask |= RetroPad.cDown }
                if right.xAxis.value < -0.5 { mask |= RetroPad.cLeft }
                if right.xAxis.value > 0.5 { mask |= RetroPad.cRight }
            } else {
                onStick?(1, Double(right.xAxis.value), Double(-right.yAxis.value), port)
            }
        } else {
            if stick.yAxis.value > 0.5 { mask |= RetroPad.up }
            if stick.yAxis.value < -0.5 { mask |= RetroPad.down }
            if stick.xAxis.value < -0.5 { mask |= RetroPad.left }
            if stick.xAxis.value > 0.5 { mask |= RetroPad.right }
        }

        if triggersFree && port == 0 {
            // Spare triggers: left = rewind (hold), right = fast forward (toggle).
            let id = ObjectIdentifier(g)
            var state = triggerState[id] ?? (false, false)
            if g.rightTrigger.isPressed != state.right {
                state.right = g.rightTrigger.isPressed
                if state.right { onAction?(.fastForward) }
            }
            if g.leftTrigger.isPressed != state.left {
                state.left = g.leftTrigger.isPressed
                if state.left { onAction?(.rewind) } else { onActionReleased?(.rewind) }
            }
            triggerState[id] = state
        }
        padMasks[port] = mask
        onButtons?(port == 0 ? mask | keyboardMask : mask, port)
    }

    // MARK: Keyboard
    // Consoles: arrows, X = A/○, Z = B/✕, C = Y/□, V = X/△, A/S = L/R, Q/W = L2/R2, Enter = Start, Shift = Select,
    // O = quick save, P = quick load, Tab = fast forward, Esc = menu.
    // Computers (DOS, C64, Amiga): every key is typed into the game.

    private func setupKeyboard() {
        guard let keyboard = GCKeyboard.coalesced?.keyboardInput else { return }
        keyboard.keyChangedHandler = { [weak self] _, _, code, pressed in
            Task { @MainActor in self?.key(code, pressed: pressed) }
        }
    }

    private func key(_ code: GCKeyCode, pressed: Bool) {
        if system.hasKeyboard {
            if let retro = RetroKey.code(for: code) { onKey?(retro, pressed) }
            return
        }
        let map: [GCKeyCode: UInt32] = [
            .upArrow: RetroPad.up, .downArrow: RetroPad.down, .leftArrow: RetroPad.left, .rightArrow: RetroPad.right,
            .keyX: RetroPad.a, .keyZ: RetroPad.b, .keyA: RetroPad.l, .keyS: RetroPad.r,
            .keyC: RetroPad.y, .keyV: RetroPad.x, .keyQ: RetroPad.l2, .keyW: RetroPad.r2,
            .returnOrEnter: RetroPad.start, .rightShift: RetroPad.select, .leftShift: RetroPad.select,
            .keyI: RetroPad.cUp, .keyK: RetroPad.cDown, .keyJ: RetroPad.cLeft, .keyL: RetroPad.cRight,
        ]
        if code == .escape, pressed { onAction?(.menu); return }
        if code == .tab, pressed { onAction?(.fastForward); return }
        if code == .keyO, pressed { onAction?(.quickSave); return }
        if code == .keyP, pressed { onAction?(.quickLoad); return }
        guard let bit = map[code] else { return }
        if pressed { keyboardMask |= bit } else { keyboardMask &= ~bit }
        onButtons?(padMasks[0] | keyboardMask, 0)
    }
}
