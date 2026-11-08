import Foundation

struct Game: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var fileName: String
    var system: GameSystem
    var addedAt: Date = .now
    var lastPlayed: Date?
    var playTimeSeconds: Double = 0
    var sessions: Int = 0
    var favorite: Bool = false
    /// File name of a custom cover image in the Covers folder.
    var coverFileName: String?
    /// Theme to use only for this game (nil = use the system/global theme).
    var themeOverrideID: String?
    var cheats: [Cheat] = []
    /// Official name from the game database (e.g. "Pokemon - Emerald Version (USA, Europe)"), once identified.
    var databaseName: String?

    var formattedPlayTime: String {
        let total = Int(playTimeSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return total > 0 ? "<1m" : "Never played"
    }
}

struct Cheat: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var code: String
    var enabled: Bool = true
}

struct SaveStateInfo: Identifiable, Hashable {
    var id: String { url.lastPathComponent }
    var url: URL
    var screenshotURL: URL
    var date: Date
    var slot: Int
    var isAuto: Bool { slot == 0 }
}
