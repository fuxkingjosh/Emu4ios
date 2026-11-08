import SwiftUI
import WidgetKit

@MainActor
final class GameLibrary: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published var lastImportMessage: String?

    @Published private(set) var findingArt: Set<String> = []

    init() {
        load()
        scanForNewFiles()
        autoFindArt()
    }

    // MARK: Cover art

    private var artAttempted: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "artAttempted") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "artAttempted") }
    }

    /// Looks up box art for any game that doesn't have it yet (once per game).
    func autoFindArt() {
        guard CoverArtService.isEnabled else { return }
        for game in games where game.coverFileName == nil && !artAttempted.contains(game.id) {
            findArt(for: game, manual: false)
        }
    }

    /// Finds the official name and box art. `manual` = user tapped "Find Cover Art".
    func findArt(for game: Game, manual: Bool) {
        guard !findingArt.contains(game.id) else { return }
        findingArt.insert(game.id)
        artAttempted.insert(game.id)
        let url = romURL(for: game)
        Task {
            let match = await CoverArtService.shared.lookup(romURL: url, system: game.system)
            findingArt.remove(game.id)
            guard var current = self.game(id: game.id) else { return }
            if let match {
                // Only replace the title if the user hasn't renamed the game.
                if current.title == Self.prettyTitle(from: current.fileName) || manual {
                    current.title = match.cleanTitle
                    update(current)
                }
                if let image = match.image, current.coverFileName == nil || manual {
                    setCover(image, for: current)
                    if manual { lastImportMessage = "Found cover art for \(match.cleanTitle)" }
                } else if manual {
                    lastImportMessage = "Found \(match.cleanTitle), but no box art for it yet"
                }
            } else if manual {
                lastImportMessage = "Couldn't identify this game"
            }
        }
    }

    var recentlyPlayed: [Game] {
        games.filter { $0.lastPlayed != nil }.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
    }

    var totalPlayTime: Double { games.reduce(0) { $0 + $1.playTimeSeconds } }

    func game(id: String) -> Game? { games.first { $0.id == id } }

    func romURL(for game: Game) -> URL {
        AppPaths.games.appendingPathComponent(game.fileName)
    }

    func coverImage(for game: Game) -> UIImage? {
        guard let name = game.coverFileName else { return nil }
        return UIImage(contentsOfFile: AppPaths.covers.appendingPathComponent(name).path)
    }

    // MARK: Import

    /// Copies picked files into the library. Returns how many games were added.
    @discardableResult
    func importFiles(_ urls: [URL]) -> Int {
        var added = 0
        var skipped: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            if url.pathExtension.lowercased() == "e4theme" { continue }
            guard let system = GameSystem(fileExtension: url.pathExtension) else {
                skipped.append(url.lastPathComponent)
                continue
            }
            let destination = uniqueDestination(for: url.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: url, to: destination)
                add(fileName: destination.lastPathComponent, system: system)
                added += 1
            } catch {
                skipped.append(url.lastPathComponent)
            }
        }
        save()
        autoFindArt()
        if !skipped.isEmpty {
            lastImportMessage = "Couldn't import: " + skipped.joined(separator: ", ")
        } else if added > 0 {
            lastImportMessage = added == 1 ? "Added 1 game" : "Added \(added) games"
        }
        return added
    }

    /// Picks up games dropped into the Games folder through the Files app.
    func scanForNewFiles() {
        let files = (try? FileManager.default.contentsOfDirectory(at: AppPaths.games, includingPropertiesForKeys: nil)) ?? []
        let known = Set(games.map(\.fileName))
        var changed = false
        for file in files where !known.contains(file.lastPathComponent) {
            if let system = GameSystem(fileExtension: file.pathExtension) {
                add(fileName: file.lastPathComponent, system: system)
                changed = true
            }
        }
        // Drop entries whose file was deleted in the Files app.
        let present = Set(files.map(\.lastPathComponent))
        let before = games.count
        games.removeAll { !present.contains($0.fileName) }
        if changed || games.count != before { save() }
        if changed { autoFindArt() }
    }

    private func add(fileName: String, system: GameSystem) {
        let title = Self.prettyTitle(from: fileName)
        games.append(Game(title: title, fileName: fileName, system: system))
    }

    private func uniqueDestination(for name: String) -> URL {
        var url = AppPaths.games.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = AppPaths.games.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return url
    }

    /// "Pokemon - Emerald Version (USA, Europe).gba" → "Pokemon - Emerald Version"
    static func prettyTitle(from fileName: String) -> String {
        var name = (fileName as NSString).deletingPathExtension
        while let range = name.range(of: #"\s*[\(\[][^\)\]]*[\)\]]\s*$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        name = name.replacingOccurrences(of: "_", with: " ")
        return name.trimmingCharacters(in: .whitespaces).isEmpty ? fileName : name
    }

    // MARK: Editing

    func update(_ game: Game) {
        guard let i = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[i] = game
        save()
    }

    func toggleFavorite(_ game: Game) {
        var g = game
        g.favorite.toggle()
        update(g)
    }

    func setCover(_ image: UIImage, for game: Game) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let name = "\(game.id).jpg"
        try? data.write(to: AppPaths.covers.appendingPathComponent(name), options: .atomic)
        var g = game
        g.coverFileName = name
        update(g)
    }

    func removeCover(for game: Game) {
        var g = game
        if let name = g.coverFileName { try? FileManager.default.removeItem(at: AppPaths.covers.appendingPathComponent(name)) }
        g.coverFileName = nil
        update(g)
    }

    func delete(_ game: Game, keepSaves: Bool = true) {
        try? FileManager.default.removeItem(at: romURL(for: game))
        if !keepSaves {
            try? FileManager.default.removeItem(at: AppPaths.saveFile(for: game))
            try? FileManager.default.removeItem(at: AppPaths.statesFolder(for: game))
        }
        games.removeAll { $0.id == game.id }
        save()
    }

    /// Called by the play session when the player leaves a game.
    func recordSession(gameID: String, seconds: Double, lastFrame: UIImage?, accentHex: String) {
        guard var g = game(id: gameID) else { return }
        g.playTimeSeconds += seconds
        g.sessions += 1
        g.lastPlayed = .now
        update(g)

        let thumb = lastFrame.flatMap { Self.thumbnail($0) }
        WidgetShared.save(.init(gameID: g.id, title: g.title, systemName: g.system.name,
                                playTimeSeconds: g.playTimeSeconds, lastPlayed: .now,
                                thumbnail: thumb, accentHex: accentHex))
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.widgetKind)
    }

    private static func thumbnail(_ image: UIImage) -> Data? {
        let target = CGSize(width: 240, height: 240 * image.size.height / max(image.size.width, 1))
        let renderer = UIGraphicsImageRenderer(size: target)
        let small = renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .none
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return small.jpegData(compressionQuality: 0.7)
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.libraryFile),
              let decoded = try? JSONDecoder().decode([Game].self, from: data) else { return }
        games = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(games) else { return }
        try? data.write(to: AppPaths.libraryFile, options: .atomic)
    }
}
