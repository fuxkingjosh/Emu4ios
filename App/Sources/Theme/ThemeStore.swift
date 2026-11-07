import SwiftUI

@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var userThemes: [Theme] = []
    @Published var activeThemeID: String {
        didSet { UserDefaults.standard.set(activeThemeID, forKey: "activeThemeID") }
    }
    /// Optional theme per system, e.g. a Game Boy-only look.
    @Published var systemThemeIDs: [String: String] {
        didSet { UserDefaults.standard.set(systemThemeIDs, forKey: "systemThemeIDs") }
    }

    private let folder: URL

    init() {
        folder = AppPaths.themes
        activeThemeID = UserDefaults.standard.string(forKey: "activeThemeID") ?? BuiltInThemes.defaultTheme.id
        systemThemeIDs = UserDefaults.standard.dictionary(forKey: "systemThemeIDs") as? [String: String] ?? [:]
        loadUserThemes()
    }

    var allThemes: [Theme] { BuiltInThemes.all + userThemes }

    var active: Theme { theme(id: activeThemeID) ?? BuiltInThemes.defaultTheme }

    func theme(id: String?) -> Theme? {
        guard let id else { return nil }
        return allThemes.first { $0.id == id }
    }

    /// The theme used while playing: game override → system theme → active theme.
    func theme(for game: Game) -> Theme {
        theme(id: game.themeOverrideID) ?? theme(id: systemThemeIDs[game.system.rawValue]) ?? active
    }

    // MARK: Editing

    func save(_ theme: Theme) {
        var t = theme
        if t.isBuiltIn { t = t.duplicated() }
        if let i = userThemes.firstIndex(where: { $0.id == t.id }) {
            userThemes[i] = t
        } else {
            userThemes.append(t)
        }
        write(t)
    }

    @discardableResult
    func duplicate(_ theme: Theme) -> Theme {
        let copy = theme.duplicated()
        save(copy)
        return copy
    }

    /// Returns a theme that can be edited: user themes as-is, built-ins as a new copy that
    /// replaces the built-in wherever it was in use (active, per-system, and the given game).
    func editableTheme(_ theme: Theme, library: GameLibrary? = nil) -> Theme {
        guard theme.isBuiltIn else { return theme }
        let copy = duplicate(theme)
        if activeThemeID == theme.id { activeThemeID = copy.id }
        for (key, value) in systemThemeIDs where value == theme.id { systemThemeIDs[key] = copy.id }
        if let library {
            for var game in library.games where game.themeOverrideID == theme.id {
                game.themeOverrideID = copy.id
                library.update(game)
            }
        }
        return copy
    }

    func delete(_ theme: Theme) {
        guard !theme.isBuiltIn else { return }
        userThemes.removeAll { $0.id == theme.id }
        try? FileManager.default.removeItem(at: fileURL(for: theme.id))
        if activeThemeID == theme.id { activeThemeID = BuiltInThemes.defaultTheme.id }
        systemThemeIDs = systemThemeIDs.filter { $0.value != theme.id }
    }

    /// Adds a theme someone shared. Always stored as a new user theme.
    @discardableResult
    func importTheme(_ incoming: Theme) -> Theme {
        var t = incoming
        t.isBuiltIn = false
        if allThemes.contains(where: { $0.id == t.id }) { t.id = UUID().uuidString }
        save(t)
        return t
    }

    // MARK: Disk

    private func fileURL(for id: String) -> URL {
        folder.appendingPathComponent("\(id).e4theme")
    }

    private func write(_ theme: Theme) {
        guard let data = try? ThemeSharing.encode(theme, pretty: true) else { return }
        try? data.write(to: fileURL(for: theme.id), options: .atomic)
        CloudSync.shared.didChangeFile(fileURL(for: theme.id), kind: .theme)
    }

    func loadUserThemes() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        userThemes = files.filter { $0.pathExtension == "e4theme" }
            .compactMap { try? ThemeSharing.decode(Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }
}
