import Foundation

/// All on-disk locations. Games and saves live in Documents so they also show up in the Files app.
enum AppPaths {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var games: URL { folder(documents, "Games") }
    static var saves: URL { folder(documents, "Saves") }
    static var states: URL { folder(documents, "Save States") }
    static var themes: URL { folder(documents, "Themes") }
    static var screenshots: URL { folder(documents, "Screenshots") }
    static var covers: URL { folder(support, "Covers") }
    static var libraryFile: URL { folder(support, "Data").appendingPathComponent("library.json") }

    static func saveFile(for game: Game) -> URL {
        saves.appendingPathComponent((game.fileName as NSString).deletingPathExtension + ".sav")
    }

    static func statesFolder(for game: Game) -> URL {
        folder(states, game.id)
    }

    private static func folder(_ base: URL, _ name: String) -> URL {
        let url = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
