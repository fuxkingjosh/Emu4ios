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
    @Published private(set) var saveStates: [SaveStateInfo] = []

    private var heldInputs: [String: UInt32] = [:]   // touch id → button bits
    private var physicalButtons: UInt32 = 0
    private var turboInputs: Set<String> = []
    private var toastTask: Task<Void, Never>?

    static let quickSlot = 10
    static let autoSlot = 0

    init?(game: Game, romURL: URL) {
        guard let core = EmulatorCore(romURL: romURL, saveURL: AppPaths.saveFile(for: game)) else { return nil }
        self.game = game
        loop = EmulationLoop(core: core)
        loop.rewindEnabled = UserDefaults.standard.object(forKey: "rewindEnabled") as? Bool ?? true
        applyCheats(game.cheats)
        refreshSaveStates()
    }

    // MARK: Lifecycle

    func start(resumeAutoSave: Bool) {
        if resumeAutoSave, let auto = saveStates.first(where: { $0.isAuto }) {
            _ = core.loadState(from: auto.url)
        }
        let size = core.videoSize
        ClipRecorder.shared.begin(width: size.width, height: size.height, fps: core.fps, sampleRate: core.sampleRate)
        loop.start()
        loop.paused = false
    }

    /// Stops the game, writes the auto-save, and returns seconds played.
    func finish() -> (seconds: Double, lastFrame: UIImage?) {
        loop.paused = true
        _ = writeState(slot: Self.autoSlot, announce: false)
        let image = loop.frame.makeImage().map { UIImage(cgImage: $0) }
        let seconds = loop.activePlaySeconds
        loop.stop()
        CloudSync.shared.didChangeFile(AppPaths.saveFile(for: game), kind: .save)
        ClipRecorder.shared.end()
        return (seconds, image)
    }

    func pause() { loop.paused = true }
    func resume() { if !isMenuOpen { loop.paused = false } }

    func openMenu() {
        isMenuOpen = true
        loop.paused = true
        refreshSaveStates()
    }

    func closeMenu() {
        isMenuOpen = false
        loop.paused = false
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

    /// Game controller / keyboard input.
    func setPhysicalButtons(_ mask: UInt32) {
        physicalButtons = mask
        pushButtons()
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
        loop.speed = isFastForwarding ? speedPreset : 1
    }

    func setSpeed(_ value: Double) {
        isFastForwarding = value != 1
        if value != 1 { speedPreset = value }
        loop.speed = value
    }

    func setRewinding(_ on: Bool) {
        guard loop.rewindEnabled else {
            if on { showToast("Rewind is off in Settings") }
            return
        }
        isRewinding = on
        loop.rewinding = on
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
        refreshSaveStates()
        return ok
    }

    @discardableResult
    func loadState(_ info: SaveStateInfo) -> Bool {
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
        loop.perform { core in core.reset() }
        loop.clearRewind()
        closeMenu()
    }

    // MARK: Cheats

    func applyCheats(_ cheats: [Cheat]) {
        let active = cheats.filter(\.enabled)
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
    }

    func saveClip() {
        showToast("Saving clip…")
        ClipRecorder.shared.exportLastClip { [weak self] message in
            Task { @MainActor in self?.showToast(message) }
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
