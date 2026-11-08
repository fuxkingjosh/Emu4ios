import SwiftUI
import Photos

/// Everything about one play session: the running emulator plus what the UI needs to show.
@MainActor
final class EmulatorSession: ObservableObject {
    let game: Game
    let loop: EmulationLoop
    var core: EmulatorCore { loop.core }

    @Published var isMenuOpen = false
    @Published private(set) var isFastForwarding = false
    @Published private(set) var isRewinding = false
    @Published var speedPreset: Double = 2 {
        didSet { if isFastForwarding { loop.speed = speedPreset } }
    }
    @Published var toast: String?
    /// On-screen computer keyboard (DOS, C64, Amiga).
    @Published var keyboardVisible = false
    @Published private(set) var saveStates: [SaveStateInfo] = []

    private var heldInputs: [String: UInt32] = [:]   // touch id → button bits
    private var physicalButtons: UInt32 = 0
    private var turboInputs: Set<String> = []
    private var toastTask: Task<Void, Never>?

    static let quickSlot = 10
    static let autoSlot = 0

    let romURL: URL

    init?(game: Game, romURL: URL) {
        guard let core = EmulatorCores.make(system: game.system, romURL: romURL, saveURL: AppPaths.saveFile(for: game)) else { return nil }
        self.game = game
        self.romURL = romURL
        loop = EmulationLoop(core: core)
        loop.rewindEnabled = game.system.supportsRewind && (UserDefaults.standard.object(forKey: "rewindEnabled") as? Bool ?? true)
        applyCheats(game.cheats)
        refreshSaveStates()
    }

    // MARK: Lifecycle

    /// Hardcore RetroAchievements forbid save states, rewind, cheats and slow motion.
    private var hardcoreLocked: Bool {
        let ra = Achievements.shared
        return ra.hardcore && ra.isLoggedIn && ra.enabled && e4ra_console_id(game.system.rawValue) != 0
    }

    func start(resumeAutoSave: Bool) {
        if resumeAutoSave, !hardcoreLocked, let auto = saveStates.first(where: { $0.isAuto }) {
            _ = core.loadState(from: auto.url)
        }
        Achievements.shared.onResetRequested = { [weak self] in self?.restart() }
        ControllerLink.shared.onInput = { [weak self] port, buttons, left, right in
            guard let self else { return }
            self.setPhysicalButtons(buttons, port: port)
            self.setStick(.leftStick, x: left.x, y: left.y, port: port)
            self.setStick(.rightStick, x: right.x, y: right.y, port: port)
        }
        Achievements.shared.gameStarted(core: core, romURL: romURL)
        if hardcoreLocked { loop.rewindEnabled = false }
        ClipRecorder.shared.begin(system: game.system, fps: core.fps, sampleRate: AudioOutput.outputRate)
        loop.start()
        loop.paused = false
    }

    /// Stops the game, writes the auto-save, and returns seconds played.
    func finish() -> (seconds: Double, lastFrame: UIImage?) {
        loop.paused = true
        if game.system.autoSavesState { _ = writeState(slot: Self.autoSlot, announce: false) }
        let image = loop.frame.makeImage().map { UIImage(cgImage: $0) }
        let seconds = loop.activePlaySeconds
        loop.stop()
        core.flushSave()
        CloudSync.shared.didChangeFile(AppPaths.saveFile(for: game), kind: .save)
        ClipRecorder.shared.end()
        LiveActivityController.shared.end()
        Achievements.shared.gameEnded()
        if ControllerLink.shared.hosting { ControllerLink.shared.stop() }
        ControllerLink.shared.onInput = nil
        return (seconds, image)
    }

    func pause() { loop.paused = true }
    func resume() { if !isMenuOpen { loop.paused = false } }

    func openMenu() {
        isMenuOpen = true
        loop.paused = true
        LiveActivityController.shared.setPaused(true)
        refreshSaveStates()
    }

    func closeMenu() {
        isMenuOpen = false
        loop.paused = false
        LiveActivityController.shared.setPaused(false)
    }

    // MARK: Input

    func press(_ input: ControlInput, touch: String, mask: UInt32? = nil, turbo: Bool = false) {
        switch input {
        case .menu: openMenu()
        case .fastForward: toggleFastForward()
        case .rewind: setRewinding(true)
        case .quickSave: quickSave()
        case .quickLoad: quickLoad()
        case .screenshot: takeScreenshot()
        case .clip: saveClip()
        case .keyboard: keyboardVisible.toggle()
        default:
            let bits = mask ?? input.buttonMask
            heldInputs[touch] = bits
            if turbo { turboInputs.insert(touch) } else { turboInputs.remove(touch) }
            pushButtons()
        }
    }

    func updateDirection(touch: String, mask: UInt32) {
        heldInputs[touch] = mask
        pushButtons()
    }

    func release(_ input: ControlInput, touch: String) {
        if input == .rewind { setRewinding(false) }
        heldInputs[touch] = nil
        turboInputs.remove(touch)
        pushButtons()
    }

    /// Game controller / keyboard input. Port 0 is player 1 (merged with the touch controls).
    func setPhysicalButtons(_ mask: UInt32, port: Int = 0) {
        if port == 0 {
            physicalButtons = mask
            pushButtons()
        } else {
            loop.setButtons(mask, port: port)
        }
    }

    /// On-screen or controller analog stick.
    func setStick(_ input: ControlInput, x: Double, y: Double, port: Int = 0) {
        loop.setStick(input == .rightStick ? 1 : 0, x: x, y: y, port: port)
    }

    /// DS touch screen: position in 0…1 of the game picture.
    func touchScreen(x: Double, y: Double, down: Bool) {
        loop.setPointer(x: x, y: y, down: down)
    }

    /// Computer games: the screen works like a laptop trackpad.
    func moveMouse(dx: Double, dy: Double) { loop.moveMouse(dx: dx, dy: dy) }
    func mouseButtons(left: Bool, right: Bool) { loop.setMouseButtons(left: left, right: right) }

    /// Computer games: a key from the on-screen or a hardware keyboard.
    func key(_ code: UInt32, down: Bool, character: UInt32 = 0) {
        loop.sendKey(KeyEvent(code: code, down: down, character: character))
    }

    /// Types a character (press + release).
    func type(_ character: Character) {
        guard let (code, shift) = RetroKey.code(for: character) else { return }
        let scalar = character.unicodeScalars.first.map { $0.value } ?? 0
        if shift { key(RetroKey.leftShift, down: true) }
        key(code, down: true, character: scalar)
        key(code, down: false)
        if shift { key(RetroKey.leftShift, down: false) }
    }

    private func pushButtons() {
        var held: UInt32 = physicalButtons
        var turbo: UInt32 = 0
        for (touch, bits) in heldInputs {
            if turboInputs.contains(touch) { turbo |= bits } else { held |= bits }
        }
        loop.buttons = held
        loop.turboButtons = turbo
    }

    // MARK: Speed / rewind

    func toggleFastForward() {
        isFastForwarding.toggle()
        if isFastForwarding { PlayStats.shared.log(.fastForward) }
        loop.speed = isFastForwarding ? speedPreset : 1
    }

    func setSpeed(_ value: Double) {
        if value < 1 && hardcoreLocked { showToast("Slow motion is off in Hardcore mode"); return }
        isFastForwarding = value != 1
        if value != 1 { speedPreset = value }
        loop.speed = value
    }

    func setRewinding(_ on: Bool) {
        if on && hardcoreLocked { showToast("Rewind is off in Hardcore mode"); return }
        guard loop.rewindEnabled else {
            if on { showToast(game.system.supportsRewind ? "Rewind is off in Settings" : "Rewind isn't available for \(game.system.shortName)") }
            return
        }
        isRewinding = on
        loop.rewinding = on
        if on { PlayStats.shared.log(.rewind) }
    }

    // MARK: Save states

    @discardableResult
    func writeState(slot: Int, announce: Bool = true) -> Bool {
        let folder = AppPaths.statesFolder(for: game)
        let stateURL = folder.appendingPathComponent("slot-\(slot).state")
        let shotURL = folder.appendingPathComponent("slot-\(slot).png")
        let ok = loop.perform { core in core.saveState(to: stateURL) }
        if ok, let image = loop.frame.makeImage(scale: 2) {
            try? UIImage(cgImage: image).pngData()?.write(to: shotURL, options: .atomic)
        }
        if ok {
            CloudSync.shared.didChangeFile(stateURL, kind: .state)
            CloudSync.shared.didChangeFile(shotURL, kind: .state)
        }
        if announce { showToast(ok ? (slot == Self.quickSlot ? "Quick saved" : "Saved to slot \(slot)") : "Couldn't save") }
        if ok && announce { PlayStats.shared.log(.saveState) }
        refreshSaveStates()
        return ok
    }

    @discardableResult
    func loadState(_ info: SaveStateInfo) -> Bool {
        if hardcoreLocked { showToast("Loading save states is off in Hardcore mode"); return false }
        let ok = loop.perform { core in core.loadState(from: info.url) }
        loop.clearRewind()
        showToast(ok ? "Loaded" : "Couldn't load that save state")
        return ok
    }

    func deleteState(_ info: SaveStateInfo) {
        try? FileManager.default.removeItem(at: info.url)
        try? FileManager.default.removeItem(at: info.screenshotURL)
        refreshSaveStates()
    }

    func quickSave() { writeState(slot: Self.quickSlot) }

    func quickLoad() {
        guard let quick = saveStates.first(where: { $0.slot == Self.quickSlot }) else {
            showToast("No quick save yet")
            return
        }
        loadState(quick)
    }

    func refreshSaveStates() {
        let folder = AppPaths.statesFolder(for: game)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        saveStates = files.filter { $0.pathExtension == "state" }.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard let slot = Int(name.replacingOccurrences(of: "slot-", with: "")) else { return nil }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return SaveStateInfo(url: url, screenshotURL: folder.appendingPathComponent("slot-\(slot).png"), date: date, slot: slot)
        }.sorted { $0.date > $1.date }
    }

    func restart() {
        loop.perform { core in core.reset(); e4ra_reset() }
        loop.clearRewind()
        closeMenu()
    }

    // MARK: Cheats

    func applyCheats(_ cheats: [Cheat]) {
        let active = hardcoreLocked ? [] : cheats.filter(\.enabled)
        loop.perform { core in
            core.clearCheats()
            for cheat in active { core.addCheat(name: cheat.name, code: cheat.code) }
        }
    }

    /// Checks a code without keeping it.
    func validateCheat(_ code: String) -> Bool {
        loop.perform { core in
            let ok = core.addCheat(name: "test", code: code)
            return ok
        }
    }

    // MARK: Screenshots & clips

    func takeScreenshot() {
        guard let cg = loop.frame.makeImage(scale: 4) else { return }
        let image = UIImage(cgImage: cg)
        let name = "\(game.title) \(Date.now.formatted(.iso8601)).png".replacingOccurrences(of: ":", with: "-")
        try? image.pngData()?.write(to: AppPaths.screenshots.appendingPathComponent(name))
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAsset(from: image) }, completionHandler: nil)
        }
        showToast("Screenshot saved")
        PlayStats.shared.log(.screenshot)
    }

    func saveClip() {
        showToast("Saving clip…")
        ClipRecorder.shared.exportLastClip { [weak self] message in
            Task { @MainActor in
                self?.showToast(message)
                if message.contains("saved") { PlayStats.shared.log(.clip) }
            }
        }
    }

    // MARK: Toast

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
