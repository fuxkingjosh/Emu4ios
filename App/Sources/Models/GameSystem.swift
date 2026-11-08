import Foundation
import CoreGraphics

/// Every console Emu4ios plays. The raw value is stored in the library, so never rename one.
enum GameSystem: String, Codable, CaseIterable, Identifiable {
    // Nintendo
    case gb, gbc, gba, nes, snes, n64, nds, vb, pokemini
    // Sega
    case genesis, segacd, sms, gamegear, sg1000
    // Sony
    case ps1, psp
    // NEC
    case pce, pcecd, supergrafx
    // SNK / Bandai
    case ngp, ngpc, wswan, wswanc
    // Atari
    case atari2600, atari5200, atari7800, lynx, jaguar
    // Computers & games
    case c64, amiga, dos, doom

    var id: String { rawValue }

    enum Maker: String, CaseIterable {
        case nintendo = "Nintendo", sega = "Sega", sony = "Sony", nec = "NEC", snk = "SNK & Bandai",
             atari = "Atari", computer = "Computers"
    }

    var maker: Maker {
        switch self {
        case .gb, .gbc, .gba, .nes, .snes, .n64, .nds, .vb, .pokemini: return .nintendo
        case .genesis, .segacd, .sms, .gamegear, .sg1000: return .sega
        case .ps1, .psp: return .sony
        case .pce, .pcecd, .supergrafx: return .nec
        case .ngp, .ngpc, .wswan, .wswanc: return .snk
        case .atari2600, .atari5200, .atari7800, .lynx, .jaguar: return .atari
        case .c64, .amiga, .dos, .doom: return .computer
        }
    }

    var name: String {
        switch self {
        case .gb: return "Game Boy"
        case .gbc: return "Game Boy Color"
        case .gba: return "Game Boy Advance"
        case .nes: return "NES / Famicom"
        case .snes: return "Super Nintendo"
        case .n64: return "Nintendo 64"
        case .nds: return "Nintendo DS"
        case .vb: return "Virtual Boy"
        case .pokemini: return "Pokémon mini"
        case .genesis: return "Genesis / Mega Drive"
        case .segacd: return "Sega CD / Mega-CD"
        case .sms: return "Master System"
        case .gamegear: return "Game Gear"
        case .sg1000: return "SG-1000"
        case .ps1: return "PlayStation"
        case .psp: return "PlayStation Portable"
        case .pce: return "TurboGrafx-16 / PC Engine"
        case .pcecd: return "TurboGrafx-CD / PC Engine CD"
        case .supergrafx: return "SuperGrafx"
        case .ngp: return "Neo Geo Pocket"
        case .ngpc: return "Neo Geo Pocket Color"
        case .wswan: return "WonderSwan"
        case .wswanc: return "WonderSwan Color"
        case .atari2600: return "Atari 2600"
        case .atari5200: return "Atari 5200"
        case .atari7800: return "Atari 7800"
        case .lynx: return "Atari Lynx"
        case .jaguar: return "Atari Jaguar"
        case .c64: return "Commodore 64"
        case .amiga: return "Amiga"
        case .dos: return "MS-DOS"
        case .doom: return "DOOM engine"
        }
    }

    var shortName: String {
        switch self {
        case .gb: return "GB"
        case .gbc: return "GBC"
        case .gba: return "GBA"
        case .nes: return "NES"
        case .snes: return "SNES"
        case .n64: return "N64"
        case .nds: return "DS"
        case .vb: return "VB"
        case .pokemini: return "MINI"
        case .genesis: return "MD"
        case .segacd: return "MCD"
        case .sms: return "SMS"
        case .gamegear: return "GG"
        case .sg1000: return "SG"
        case .ps1: return "PS1"
        case .psp: return "PSP"
        case .pce: return "PCE"
        case .pcecd: return "PCECD"
        case .supergrafx: return "SGX"
        case .ngp: return "NGP"
        case .ngpc: return "NGPC"
        case .wswan: return "WS"
        case .wswanc: return "WSC"
        case .atari2600: return "2600"
        case .atari5200: return "5200"
        case .atari7800: return "7800"
        case .lynx: return "LYNX"
        case .jaguar: return "JAG"
        case .c64: return "C64"
        case .amiga: return "AMIGA"
        case .dos: return "DOS"
        case .doom: return "DOOM"
        }
    }

    /// File types that only ever mean this system. Shared types (.bin, .iso, .cue, .chd…) are in `sharedExtensions`.
    var fileExtensions: [String] {
        switch self {
        case .gb: return ["gb"]
        case .gbc: return ["gbc"]
        case .gba: return ["gba"]
        case .nes: return ["nes", "fds", "unf", "unif"]
        case .snes: return ["sfc", "smc", "bs", "st"]
        case .n64: return ["n64", "z64", "v64", "ndd"]
        case .nds: return ["nds", "dsi"]
        case .vb: return ["vb", "vboy"]
        case .pokemini: return ["min"]
        case .genesis: return ["md", "gen", "smd", "68k", "sgd"]
        case .segacd: return []
        case .sms: return ["sms"]
        case .gamegear: return ["gg"]
        case .sg1000: return ["sg", "sc"]
        case .ps1: return ["pbp", "m3u", "ccd", "exe"]
        case .psp: return ["cso", "elf", "prx"]
        case .pce: return ["pce"]
        case .pcecd: return []
        case .supergrafx: return ["sgx"]
        case .ngp: return ["ngp"]
        case .ngpc: return ["ngc", "npc"]
        case .wswan: return ["ws"]
        case .wswanc: return ["wsc", "pc2"]
        case .atari2600: return ["a26"]
        case .atari5200: return ["a52", "car", "xfd", "atr"]
        case .atari7800: return ["a78"]
        case .lynx: return ["lnx", "lyx", "o"]
        case .jaguar: return ["j64", "jag", "rom", "abs", "cof"]
        case .c64: return ["d64", "t64", "prg", "crt", "tap", "d71", "d81", "g64", "p00", "x64", "nib"]
        case .amiga: return ["adf", "adz", "hdf", "hdz", "ipf", "dms", "lha", "uae"]
        case .dos: return ["dosz", "com", "bat", "conf", "ima", "vhd"]
        case .doom: return ["wad", "iwad", "pwad"]
        }
    }

    /// File types several systems use; `SystemDetector` looks inside the file to decide.
    static let sharedExtensions: Set<String> = ["bin", "iso", "cue", "chd", "img", "zip", "7z", "exe", "pbp", "m3u", "ccd", "toc"]

    /// The shape the screen is shown at (pixel size for handhelds, 4:3 for TV consoles).
    var screenSize: CGSize {
        switch self {
        case .gb, .gbc: return CGSize(width: 160, height: 144)
        case .gba: return CGSize(width: 240, height: 160)
        case .nds: return CGSize(width: 256, height: 384)
        case .vb: return CGSize(width: 384, height: 224)
        case .pokemini: return CGSize(width: 96, height: 64)
        case .gamegear: return CGSize(width: 160, height: 144)
        case .ngp, .ngpc: return CGSize(width: 160, height: 152)
        case .wswan, .wswanc: return CGSize(width: 224, height: 144)
        case .lynx: return CGSize(width: 160, height: 102)
        case .psp: return CGSize(width: 480, height: 272)
        default: return CGSize(width: 320, height: 240) // TV consoles and computers: 4:3
        }
    }

    /// Handhelds look best scaled by whole pixels; TV systems are stretched to 4:3.
    var prefersIntegerScaling: Bool {
        switch self {
        case .gb, .gbc, .gba, .nds, .vb, .pokemini, .gamegear, .ngp, .ngpc, .wswan, .wswanc, .lynx: return true
        default: return false
        }
    }

    var isHandheld: Bool {
        switch self {
        case .gb, .gbc, .gba, .nds, .vb, .pokemini, .gamegear, .ngp, .ngpc, .wswan, .wswanc, .lynx, .psp: return true
        default: return false
        }
    }

    /// Which buttons this system's controller has.
    var inputs: [ControlInput] {
        switch self {
        case .gb, .gbc, .nes: return [.dpad, .a, .b, .start, .select]
        case .gba: return [.dpad, .a, .b, .l, .r, .start, .select]
        case .snes, .nds: return [.dpad, .a, .b, .x, .y, .l, .r, .start, .select]
        case .n64: return [.leftStick, .dpad, .b, .y, .l2, .l, .r, .start, .cUp, .cDown, .cLeft, .cRight]
        case .vb: return [.dpad, .dpad2, .a, .b, .l, .r, .start, .select]
        case .pokemini: return [.dpad, .a, .b, .r, .l, .select]
        case .genesis, .segacd: return [.dpad, .y, .b, .a, .l, .x, .r, .start, .select]
        case .sms, .sg1000, .gamegear: return [.dpad, .b, .a, .start]
        case .ps1: return [.dpad, .cross, .circle, .square, .triangle, .l, .r, .l2, .r2, .start, .select]
        case .psp: return [.dpad, .leftStick, .cross, .circle, .square, .triangle, .l, .r, .start, .select]
        case .pce, .pcecd, .supergrafx: return [.dpad, .b, .a, .start, .select]
        case .ngp, .ngpc, .wswan, .wswanc: return [.dpad, .b, .a, .start]
        case .lynx: return [.dpad, .b, .a, .l, .r, .start]
        case .atari2600: return [.dpad, .b, .select, .start]
        case .atari5200: return [.dpad, .a, .b, .start, .select]
        case .atari7800: return [.dpad, .b, .a, .select, .start]
        case .jaguar: return [.dpad, .y, .b, .a, .start, .select]
        case .c64, .amiga: return [.dpad, .b, .a, .start, .select, .keyboard]
        case .dos: return [.dpad, .b, .a, .y, .x, .l, .r, .start, .select, .keyboard]
        case .doom: return [.dpad, .x, .a, .b, .y, .l, .r, .l2, .r2, .start, .select]
        }
    }

    /// What each button is printed as on this system's real controller.
    func label(for input: ControlInput) -> String? {
        switch (self, input) {
        case (.genesis, .y), (.segacd, .y): return "A"
        case (.genesis, .b), (.segacd, .b): return "B"
        case (.genesis, .a), (.segacd, .a): return "C"
        case (.genesis, .l), (.segacd, .l): return "X"
        case (.genesis, .x), (.segacd, .x): return "Y"
        case (.genesis, .r), (.segacd, .r): return "Z"
        case (.genesis, .select), (.segacd, .select): return "MODE"
        case (.sms, .b), (.sg1000, .b), (.gamegear, .b), (.atari7800, .b): return "1"
        case (.sms, .a), (.sg1000, .a), (.gamegear, .a), (.atari7800, .a): return "2"
        case (.sms, .start), (.sg1000, .start): return "PAUSE"
        case (.pce, .b), (.pcecd, .b), (.supergrafx, .b): return "II"
        case (.pce, .a), (.pcecd, .a), (.supergrafx, .a): return "I"
        case (.pce, .start), (.pcecd, .start), (.supergrafx, .start): return "RUN"
        case (.ngp, .b), (.ngpc, .b), (.lynx, .b): return "A"
        case (.ngp, .a), (.ngpc, .a), (.lynx, .a): return "B"
        case (.ngp, .start), (.ngpc, .start): return "OPTION"
        case (.lynx, .l): return "OPT 1"
        case (.lynx, .r): return "OPT 2"
        case (.lynx, .start): return "PAUSE"
        case (.pokemini, .r): return "C"
        case (.pokemini, .l): return "SHAKE"
        case (.pokemini, .select): return "POWER"
        case (.n64, .b): return "A"
        case (.n64, .y): return "B"
        case (.n64, .l2): return "Z"
        case (.atari2600, .b): return "FIRE"
        case (.atari2600, .start): return "RESET"
        case (.atari5200, .a): return "FIRE 1"
        case (.atari5200, .b): return "FIRE 2"
        case (.atari5200, .select): return "PAUSE"
        case (.jaguar, .y): return "C"
        case (.jaguar, .select): return "PAUSE"
        case (.jaguar, .start): return "OPTION"
        case (.c64, .b), (.amiga, .b): return "FIRE"
        case (.c64, .a), (.amiga, .a): return "FIRE 2"
        case (.doom, .x): return "FIRE"
        case (.doom, .a): return "USE"
        case (.doom, .b): return "STRAFE"
        case (.doom, .y): return "RUN"
        case (.doom, .l): return "◀ STEP"
        case (.doom, .r): return "STEP ▶"
        case (.doom, .l2): return "◀ GUN"
        case (.doom, .r2): return "GUN ▶"
        case (.doom, .start): return "MENU"
        case (.doom, .select): return "MAP"
        default: return nil
        }
    }

    // MARK: Engine

    /// Engine that runs this system.
    var usesLibretro: Bool { !(self == .gb || self == .gbc || self == .gba) }

    /// The bundled libretro core (framework name inside the app).
    var coreFramework: String? {
        switch self {
        case .gb, .gbc, .gba: return nil
        case .nes: return "Mesen"
        case .snes: return "BSNES"
        case .n64: return "Mupen64Plus"
        case .nds: return "MelonDSDS"
        case .vb: return "MednafenVB"
        case .pokemini: return "PokeMini"
        case .genesis, .segacd: return "ClownMDEmu"
        case .sms, .gamegear, .sg1000: return "Gearsystem"
        case .ps1: return "PCSXReARMed"
        case .psp: return "PPSSPP"
        case .pce, .pcecd: return "MednafenPCE"
        case .supergrafx: return "Geargrafx"
        case .ngp, .ngpc: return "MednafenNGP"
        case .wswan, .wswanc: return "MednafenWSwan"
        case .atari2600: return "Stella"
        case .atari5200: return "A5200"
        case .atari7800: return "ProSystem"
        case .lynx: return "MednafenLynx"
        case .jaguar: return "VirtualJaguar"
        case .c64: return "VICE"
        case .amiga: return "PUAE"
        case .dos: return "DOSBoxPure"
        case .doom: return "PrBoom"
        }
    }

    /// Core settings chosen so every system runs well on a phone without JIT.
    var coreOptions: [String: String] {
        switch self {
        case .ps1:
            return ["pcsx_rearmed_bios": "auto", "pcsx_rearmed_show_bios_bootlogo": "disabled",
                    "pcsx_rearmed_frameskip_type": "disabled", "pcsx_rearmed_drc": "disabled"]
        case .n64:
            return ["mupen64plus-cpucore": "cached_interpreter", "mupen64plus-rdp-plugin": "gliden64",
                    "mupen64plus-rsp-plugin": "hle", "mupen64plus-43screensize": "640x480",
                    "mupen64plus-EnableFBEmulation": "True", "mupen64plus-ThreadedRenderer": "False"]
        case .psp:
            return ["ppsspp_cpu_core": "IR JIT", "ppsspp_internal_resolution": "960x544",
                    "ppsspp_fast_memory": "disabled", "ppsspp_auto_frameskip": "disabled",
                    "ppsspp_frame_duplication": "enabled", "ppsspp_backend": "opengl",
                    // Finish each frame before it's handed over; buffered frames could be read half-drawn
                    // (missing characters, stray pieces of the previous frame).
                    "ppsspp_inflight_frames": "No buffer",
                    "ppsspp_texture_filtering": "Auto max quality"]
        case .nds:
            return ["melonds_render_mode": "software", "melonds_threaded_renderer": "enabled",
                    "melonds_console_mode": "ds", "melonds_sysfile_mode": "builtin",
                    "melonds_touch_mode": "touch", "melonds_show_cursor": "touching"]
        case .snes: return ["bsnes_ppu_fast": "ON", "bsnes_dsp_fast": "ON", "bsnes_aspect_ratio": "4:3"]
        case .atari5200: return ["a5200_bios": "internal"]
        case .vb: return ["vb_anaglyph_preset": "disabled", "vb_color_mode": "black & red"]
        case .dos: return ["dosbox_pure_auto_mapping": "true", "dosbox_pure_on_screen_keyboard": "false"]
        case .c64: return ["vice_retropad_options": "jump"]
        case .amiga: return ["puae_kickstart": "auto", "puae_model": "auto"]
        case .segacd, .genesis: return ["clownmdemu_tv_standard": "auto"]
        default: return [:]
        }
    }

    /// Systems whose core can't play anything without a firmware file the player adds.
    var requiredBIOS: [String] {
        switch self {
        case .lynx: return ["lynxboot.img"]
        case .pcecd: return ["syscard3.pce"]
        default: return []
        }
    }

    /// Touches on the game screen: DS touch screen, computer mouse, or nothing.
    enum ScreenTouch { case none, touchScreen, mouse }
    var screenTouch: ScreenTouch {
        switch self {
        case .nds: return .touchScreen
        case .dos, .amiga: return .mouse
        default: return .none
        }
    }

    /// Rewind keeps many save states in memory; consoles with huge states (or cores that can only save
    /// at safe moments, like PSP during loading) skip it.
    var supportsRewind: Bool { ![.psp, .n64, .nds, .dos, .amiga, .c64, .jaguar].contains(self) }
    /// PSP can't make a save state while a game is still loading, so it relies on the game's own saves
    /// instead of the automatic save state when you quit.
    var autoSavesState: Bool { self != .psp }

    var hasAnalogStick: Bool { inputs.contains(.leftStick) }
    var hasKeyboard: Bool { inputs.contains(.keyboard) }
    /// Uses PlayStation face-button names on physical controllers.
    var usesPlayStationButtons: Bool { self == .ps1 || self == .psp }
    /// Disc-based systems need the .cue sheet's track files kept together.
    var isDiscBased: Bool { [.ps1, .psp, .segacd, .pcecd].contains(self) }

    // MARK: Box art (libretro-thumbnails)

    var thumbnailDatabase: String {
        switch self {
        case .gb: return "Nintendo - Game Boy"
        case .gbc: return "Nintendo - Game Boy Color"
        case .gba: return "Nintendo - Game Boy Advance"
        case .nes: return "Nintendo - Nintendo Entertainment System"
        case .snes: return "Nintendo - Super Nintendo Entertainment System"
        case .n64: return "Nintendo - Nintendo 64"
        case .nds: return "Nintendo - Nintendo DS"
        case .vb: return "Nintendo - Virtual Boy"
        case .pokemini: return "Nintendo - Pokemon Mini"
        case .genesis: return "Sega - Mega Drive - Genesis"
        case .segacd: return "Sega - Mega-CD - Sega CD"
        case .sms: return "Sega - Master System - Mark III"
        case .gamegear: return "Sega - Game Gear"
        case .sg1000: return "Sega - SG-1000"
        case .ps1: return "Sony - PlayStation"
        case .psp: return "Sony - PlayStation Portable"
        case .pce: return "NEC - PC Engine - TurboGrafx 16"
        case .pcecd: return "NEC - PC Engine CD - TurboGrafx-CD"
        case .supergrafx: return "NEC - PC Engine SuperGrafx"
        case .ngp: return "SNK - Neo Geo Pocket"
        case .ngpc: return "SNK - Neo Geo Pocket Color"
        case .wswan: return "Bandai - WonderSwan"
        case .wswanc: return "Bandai - WonderSwan Color"
        case .atari2600: return "Atari - 2600"
        case .atari5200: return "Atari - 5200"
        case .atari7800: return "Atari - 7800"
        case .lynx: return "Atari - Lynx"
        case .jaguar: return "Atari - Jaguar"
        case .c64: return "Commodore - 64"
        case .amiga: return "Commodore - Amiga"
        case .dos: return "DOS"
        case .doom: return "DOOM"
        }
    }

    var thumbnailRepo: String { thumbnailDatabase.replacingOccurrences(of: " ", with: "_") }

    /// Cartridge systems whose No-Intro DAT lets us match box art by checksum.
    var matchesByChecksum: Bool { !isDiscBased && ![.c64, .amiga, .dos, .doom].contains(self) }

    // MARK: Lookup

    init?(fileExtension ext: String) {
        let lower = ext.lowercased()
        guard let match = GameSystem.allCases.first(where: { $0.fileExtensions.contains(lower) }) else { return nil }
        self = match
    }

    init?(_ system: E4System) {
        switch system {
        case E4SystemGB: self = .gb
        case E4SystemGBC: self = .gbc
        case E4SystemGBA: self = .gba
        default: return nil
        }
    }

    /// Disc track files that belong to a .cue sheet aren't games on their own.
    static let companionExtensions: Set<String> = ["bin", "sub", "img", "wav", "ape", "flac", "ogg", "mp3"]

    static var allExtensions: [String] { Array(Set(allCases.flatMap(\.fileExtensions)).union(sharedExtensions)) }

    /// Systems whose core shipped in this build (cores that failed to build are left out).
    static var available: [GameSystem] {
        allCases.filter { system in
            guard let fw = system.coreFramework else { return true }
            return CoreRegistry.isAvailable(fw)
        }
    }

    var isAvailable: Bool { coreFramework.map(CoreRegistry.isAvailable) ?? true }
}

/// Which libretro cores are inside the app.
enum CoreRegistry {
    private static let bundled: Set<String>? = {
        guard let url = Bundle.main.url(forResource: "cores-available", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return Set(list)
    }()

    static func isAvailable(_ framework: String) -> Bool {
        if let bundled { return bundled.contains(framework) }
        return path(for: framework) != nil
    }

    /// Full path to a core's binary inside the app.
    static func path(for framework: String) -> String? {
        guard let dir = Bundle.main.privateFrameworksPath else { return nil }
        let path = "\(dir)/\(framework).framework/\(framework)"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }
}
