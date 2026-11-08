import Foundation

/// Controller layouts saved for one specific game (they override the theme's layout for that game).
@MainActor
final class LayoutStore: ObservableObject {
    static let shared = LayoutStore()
    @Published private(set) var version = 0

    private var folder: URL {
        let url = AppPaths.documents.appendingPathComponent("Layouts", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func url(_ gameID: String) -> URL { folder.appendingPathComponent("\(gameID).json") }

    func skin(for gameID: String) -> ControllerSkin? {
        guard let data = try? Data(contentsOf: url(gameID)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .base64
        return try? decoder.decode(ControllerSkin.self, from: data)
    }

    func hasCustomLayout(_ gameID: String) -> Bool { FileManager.default.fileExists(atPath: url(gameID).path) }

    func save(_ skin: ControllerSkin, for gameID: String) {
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .base64
        if let data = try? encoder.encode(skin) { try? data.write(to: url(gameID), options: .atomic) }
        version += 1
    }

    func remove(_ gameID: String) {
        try? FileManager.default.removeItem(at: url(gameID))
        version += 1
    }
}
