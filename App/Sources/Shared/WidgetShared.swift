import Foundation

/// Data the app shares with the Home Screen widget through the App Group.
enum WidgetShared {
    static let appGroup = "group.com.fuxkingjosh.emu4ios"
    static let lastPlayedKey = "lastPlayedGame"
    static let widgetKind = "ContinuePlayingWidget"

    struct LastPlayed: Codable, Equatable {
        var gameID: String
        var title: String
        var systemName: String
        var playTimeSeconds: Double
        var lastPlayed: Date
        /// JPEG of the last frame, small enough for a widget.
        var thumbnail: Data?
        var accentHex: String
    }

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func save(_ value: LastPlayed) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults?.set(data, forKey: lastPlayedKey)
    }

    static func load() -> LastPlayed? {
        guard let data = defaults?.data(forKey: lastPlayedKey) else { return nil }
        return try? JSONDecoder().decode(LastPlayed.self, from: data)
    }

    static func playURL(gameID: String) -> URL {
        URL(string: "emu4ios://play?id=\(gameID)")!
    }
}
