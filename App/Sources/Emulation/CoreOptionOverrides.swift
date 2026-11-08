import Foundation

/// Per-console emulator settings the player can change (Settings → Console Settings).
/// Only a curated, safe set is offered; everything else uses Emu4ios' tuned defaults.
enum CoreOptionOverrides {
    struct Choice: Identifiable, Hashable {
        let value: String
        let title: String
        var id: String { value }
    }

    struct Setting: Identifiable {
        let system: GameSystem
        let key: String
        let title: String
        let detail: String
        let choices: [Choice]
        var id: String { system.rawValue + key }
        var defaultValue: String { system.coreOptions[key] ?? choices[0].value }
    }

    static let settings: [Setting] = [
        Setting(system: .n64, key: "mupen64plus-43screensize", title: "Resolution",
                detail: "Higher looks sharper but needs a newer iPhone.",
                choices: [Choice(value: "320x240", title: "Original (320×240)"), Choice(value: "640x480", title: "2× (640×480)"),
                          Choice(value: "960x720", title: "3× (960×720)")]),
        Setting(system: .psp, key: "ppsspp_internal_resolution", title: "Resolution",
                detail: "Higher looks sharper but needs a newer iPhone.",
                choices: [Choice(value: "480x272", title: "Original (480×272)"), Choice(value: "960x544", title: "2× (960×544)"),
                          Choice(value: "1440x816", title: "3× (1440×816)")]),
        Setting(system: .psp, key: "ppsspp_frameskip", title: "Frame Skip",
                detail: "Skipping frames keeps heavy games at full speed.",
                choices: [Choice(value: "disabled", title: "Off"), Choice(value: "1", title: "1"), Choice(value: "2", title: "2")]),
        Setting(system: .ps1, key: "pcsx_rearmed_neon_enhancement_enable", title: "Enhanced Resolution",
                detail: "Doubles the internal resolution for sharper 3D.",
                choices: [Choice(value: "disabled", title: "Off"), Choice(value: "enabled", title: "On")]),
        Setting(system: .nds, key: "melonds_screen_layout1", title: "Screen Order",
                detail: "Which screen is on top.",
                choices: [Choice(value: "top-bottom", title: "Top screen first"), Choice(value: "bottom-top", title: "Touch screen first")]),
        Setting(system: .nds, key: "melonds_console_mode", title: "Console",
                detail: "DSi mode needs your own DSi system files in the BIOS folder.",
                choices: [Choice(value: "ds", title: "Nintendo DS"), Choice(value: "dsi", title: "Nintendo DSi")]),
        Setting(system: .snes, key: "bsnes_ppu_fast", title: "Fast Graphics",
                detail: "Turn off only for the rare game that needs exact timing.",
                choices: [Choice(value: "ON", title: "On"), Choice(value: "OFF", title: "Off")]),
        Setting(system: .gamegear, key: "gearsystem_glasses", title: "3D Glasses",
                detail: "For the few Master System 3D games.",
                choices: [Choice(value: "Both Eyes / OFF", title: "Off"), Choice(value: "Left Eye", title: "Left eye"),
                          Choice(value: "Right Eye", title: "Right eye")]),
        Setting(system: .dos, key: "dosbox_pure_cycles", title: "CPU Speed",
                detail: "Raise for later DOS games, lower if a game runs too fast.",
                choices: [Choice(value: "auto", title: "Automatic"), Choice(value: "max", title: "Maximum"),
                          Choice(value: "2750", title: "286"), Choice(value: "13400", title: "386"),
                          Choice(value: "26800", title: "486"), Choice(value: "77000", title: "Pentium")]),
        Setting(system: .amiga, key: "puae_model", title: "Amiga Model",
                detail: "Automatic picks the best model for each game.",
                choices: [Choice(value: "auto", title: "Automatic"), Choice(value: "A500", title: "Amiga 500"),
                          Choice(value: "A1200", title: "Amiga 1200")]),
    ]

    private static let storeKey = "coreOptionOverrides"

    private static var store: [String: [String: String]] {
        get { UserDefaults.standard.dictionary(forKey: storeKey) as? [String: [String: String]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: storeKey) }
    }

    static func values(for system: GameSystem) -> [String: String] { store[system.rawValue] ?? [:] }

    static func value(for setting: Setting) -> String { values(for: setting.system)[setting.key] ?? setting.defaultValue }

    static func set(_ value: String, for setting: Setting) {
        var all = store
        var dict = all[setting.system.rawValue] ?? [:]
        dict[setting.key] = value == setting.defaultValue ? nil : value
        all[setting.system.rawValue] = dict.isEmpty ? nil : dict
        store = all
    }
}
