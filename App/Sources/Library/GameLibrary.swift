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
                current.databaseName = match.databaseName
                update(current)
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
        games.filter { $0.lastPlayed != nil && $0.system.isEnabled }.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
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

    /// Files whose console couldn't be worked out; the library asks the player to pick one.
    @Published var needsSystemChoice: [String] = []

    /// Copies picked files into the library. Returns how many games were added.
    @discardableResult
    func importFiles(_ urls: [URL]) -> Int {
        var added = 0
        var skipped: [String] = []
        // Disc track files (.bin) that belong to a .cue sheet go in first, so the sheet can be identified.
        let companions = urls.filter {
            GameSystem.companionExtensions.contains($0.pathExtension.lowercased()) && Self.isReferencedByCueSheet($0.lastPathComponent, among: urls)
        }
        for url in companions {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let dest = AppPaths.games.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
        }
        for url in urls where !companions.contains(url) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.lowercased()
            if ext == "e4theme" { continue }
            if ext == "zip", !(SystemDetector.detect(url) == .dos) {
                let unpacked = unpackArchive(url)
                if unpacked == 0 { skipped.append(url.lastPathComponent) }
                added += unpacked
                continue
            }
            guard GameSystem.allExtensions.contains(ext) else {
                skipped.append(url.lastPathComponent)
                continue
            }
            let destination = uniqueDestination(for: url.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: url, to: destination)
                if let system = SystemDetector.detect(destination), !system.isEnabled {
                    try? FileManager.default.removeItem(at: destination)
                    skipped.append("\(url.lastPathComponent) (\(system.shortName) is turned off)")
                } else if let system = SystemDetector.detect(destination) {
                    add(fileName: destination.lastPathComponent, system: system)
                    added += 1
                } else {
                    needsSystemChoice.append(destination.lastPathComponent)
                }
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

    /// Pulls games out of a .zip (one archive can hold several). Returns how many were added.
    private func unpackArchive(_ url: URL) -> Int {
        guard let zip = try? ZipArchive(url: url) else { return 0 }
        var added = 0
        let files = zip.entries.filter { !$0.isDirectory && !$0.name.hasPrefix("__MACOSX") }
        // Track files first so their .cue can be identified.
        func isTrack(_ e: ZipArchive.Entry) -> Bool { GameSystem.companionExtensions.contains((e.name as NSString).pathExtension.lowercased()) }
        let ordered = files.filter(isTrack) + files.filter { !isTrack($0) }
        var extracted: [URL] = []
        for entry in ordered {
            let name = (entry.name as NSString).lastPathComponent
            let ext = (name as NSString).pathExtension.lowercased()
            guard GameSystem.allExtensions.contains(ext) || GameSystem.companionExtensions.contains(ext),
                  let data = try? zip.extract(entry) else { continue }
            let dest = GameSystem.companionExtensions.contains(ext)
                ? AppPaths.games.appendingPathComponent(name) : uniqueDestination(for: name)
            guard (try? data.write(to: dest, options: .atomic)) != nil else { continue }
            extracted.append(dest)
        }
        let referenced = Self.cueReferencedFiles(in: extracted)
        for file in extracted where !referenced.contains(file.lastPathComponent) {
            if let system = SystemDetector.detect(file) {
                add(fileName: file.lastPathComponent, system: system)
                added += 1
            } else {
                needsSystemChoice.append(file.lastPathComponent)
            }
        }
        return added
    }

    /// The player picked the console for a file we couldn't identify.
    func assignSystem(_ system: GameSystem, to fileName: String) {
        needsSystemChoice.removeAll { $0 == fileName }
        guard !games.contains(where: { $0.fileName == fileName }) else { return }
        add(fileName: fileName, system: system)
        save()
        autoFindArt()
    }

    /// Fixes a game that was filed under the wrong console.
    func changeSystem(of game: Game, to system: GameSystem) {
        guard let i = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[i].system = system
        save()
        findArt(for: games[i], manual: false)
    }

    /// Picks up games dropped into the Games folder through the Files app.
    func scanForNewFiles() {
        let files = (try? FileManager.default.contentsOfDirectory(at: AppPaths.games, includingPropertiesForKeys: nil)) ?? []
        let known = Set(games.map(\.fileName))
        var changed = false
        let referenced = Self.cueReferencedFiles(in: files)
        for file in files where !known.contains(file.lastPathComponent) && !referenced.contains(file.lastPathComponent) {
            let ext = file.pathExtension.lowercased()
            guard GameSystem.allExtensions.contains(ext), !needsSystemChoice.contains(file.lastPathComponent) else { continue }
            if ext == "zip", SystemDetector.detect(file) != .dos { continue } // archives are unpacked on import only
            if let system = SystemDetector.detect(file) {
                add(fileName: file.lastPathComponent, system: system)
                changed = true
            } else {
                needsSystemChoice.append(file.lastPathComponent)
            }
        }
        // Drop entries whose file was deleted in the Files app (and track files that now belong to a cue).
        let present = Set(files.map(\.lastPathComponent))
        let before = games.count
        games.removeAll { !present.contains($0.fileName) || referenced.contains($0.fileName) }
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

    /// File names listed in .cue/.ccd sheets and .m3u playlists (their parts shouldn't show up as separate games).
    static func cueReferencedFiles(in files: [URL]) -> Set<String> {
        var names = Set<String>()
        for list in files where list.pathExtension.lowercased() == "m3u" {
            guard let text = try? String(contentsOf: list, encoding: .utf8) else { continue }
            for line in text.components(separatedBy: .newlines) {
                let entry = line.trimmingCharacters(in: .whitespaces)
                if !entry.isEmpty, !entry.hasPrefix("#") { names.insert((entry as NSString).lastPathComponent) }
            }
        }
        for sheet in files where ["cue", "ccd"].contains(sheet.pathExtension.lowercased()) {
            let base = sheet.deletingPathExtension().lastPathComponent
            if sheet.pathExtension.lowercased() == "ccd" {
                names.insert(base + ".img"); names.insert(base + ".sub")
                continue
            }
            guard let text = (try? String(contentsOf: sheet, encoding: .utf8)) ?? (try? String(contentsOf: sheet, encoding: .isoLatin1)) else { continue }
            for line in text.components(separatedBy: .newlines) where line.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("FILE") {
                if let first = line.firstIndex(of: "\""), let last = line.lastIndex(of: "\""), first < last {
                    names.insert(String(line[line.index(after: first)..<last]))
                }
            }
        }
        return names
    }

    private static func isReferencedByCueSheet(_ name: String, among urls: [URL]) -> Bool {
        if cueReferencedFiles(in: urls).contains(name) { return true }
        // The sheet might already be in the library folder.
        let existing = (try? FileManager.default.contentsOfDirectory(at: AppPaths.games, includingPropertiesForKeys: nil)) ?? []
        return cueReferencedFiles(in: existing).contains(name)
    }

    /// "Pokemon - Emerald Version (USA, Europe).gba" → "Pokemon - Emerald Version"
    static func prettyTitle(from fileName: String) -> String {
        var name = (fileName as NSString).deletingPathExtension
        while let range = name.range(of: #"\s*[\(\[][^\)\]]*[\)\]]\s*$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        name = name.replacingOccurrences(of: "_", with: " ")
        // Release-list numbers in front ("0294 - Fight Night Round 3").
        name = name.replacingOccurrences(of: #"^\s*\d{3,5}\s*[-–.]\s*"#, with: "", options: .regularExpression)
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
        PlayStats.shared.recordPlay(game: g, seconds: seconds)
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
