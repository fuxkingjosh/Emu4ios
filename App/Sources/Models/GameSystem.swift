import Foundation

enum GameSystem: String, Codable, CaseIterable, Identifiable {
    case gb, gbc, gba

    var id: String { rawValue }

    var name: String {
        switch self {
        case .gb: return "Game Boy"
        case .gbc: return "Game Boy Color"
        case .gba: return "Game Boy Advance"
        }
    }

    var shortName: String {
        switch self {
        case .gb: return "GB"
        case .gbc: return "GBC"
        case .gba: return "GBA"
        }
    }

    var fileExtensions: [String] {
        switch self {
        case .gb: return ["gb"]
        case .gbc: return ["gbc"]
        case .gba: return ["gba"]
        }
    }

    var screenSize: CGSize {
        switch self {
        case .gb, .gbc: return CGSize(width: 160, height: 144)
        case .gba: return CGSize(width: 240, height: 160)
        }
    }

    /// Which buttons this system's controller has.
    var inputs: [ControlInput] {
        switch self {
        case .gb, .gbc: return [.dpad, .a, .b, .start, .select]
        case .gba: return [.dpad, .a, .b, .l, .r, .start, .select]
        }
    }

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

    static var allExtensions: [String] { allCases.flatMap(\.fileExtensions) }
}

/// Systems we plan to add, shown as "coming soon" in the library.
enum UpcomingSystem: String, CaseIterable {
    case nes = "NES", snes = "SNES", n64 = "N64", ds = "Nintendo DS", genesis = "Genesis"
}
