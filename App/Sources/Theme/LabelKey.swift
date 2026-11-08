import Foundation

/// Every piece of text in the app that a theme can rename.
enum LabelKey: String, CaseIterable, Identifiable {
    case appTitle = "app.title"
    case libraryTitle = "library.title"
    case libraryEmpty = "library.empty"
    case libraryEmptyHint = "library.emptyHint"
    case importGames = "library.import"
    case continuePlaying = "library.continue"
    case favorites = "library.favorites"
    case allGames = "library.all"
    case search = "library.search"
    case themesTitle = "themes.title"
    case settingsTitle = "settings.title"
    case statsTitle = "stats.title"
    case resume = "menu.resume"
    case saveState = "menu.saveState"
    case loadState = "menu.loadState"
    case restart = "menu.restart"
    case cheats = "menu.cheats"
    case screenFilter = "menu.filter"
    case editController = "menu.editController"
    case speed = "menu.speed"
    case quit = "menu.quit"
    case comingSoon = "common.comingSoon"

    var id: String { rawValue }

    var defaultText: String {
        switch self {
        case .appTitle: return "Emu4ios"
        case .libraryTitle: return "Library"
        case .libraryEmpty: return "No games yet"
        case .libraryEmptyHint: return "Import your own game files — Game Boy, NES, SNES, N64, DS, PlayStation, PSP, Genesis and 20+ more consoles."
        case .importGames: return "Import Games"
        case .continuePlaying: return "Continue Playing"
        case .favorites: return "Favorites"
        case .allGames: return "All Games"
        case .search: return "Search games"
        case .themesTitle: return "Themes"
        case .settingsTitle: return "Settings"
        case .statsTitle: return "Play Stats"
        case .resume: return "Resume"
        case .saveState: return "Save State"
        case .loadState: return "Load State"
        case .restart: return "Restart Game"
        case .cheats: return "Cheats"
        case .screenFilter: return "Screen Filter"
        case .editController: return "Edit Controller"
        case .speed: return "Speed"
        case .quit: return "Quit Game"
        case .comingSoon: return "Supported consoles"
        }
    }

    /// Short description shown in the label editor.
    var whereShown: String {
        switch self {
        case .appTitle, .libraryTitle, .libraryEmpty, .libraryEmptyHint, .importGames,
             .continuePlaying, .favorites, .allGames, .search:
            return "Library"
        case .themesTitle, .settingsTitle, .statsTitle: return "Tabs"
        case .comingSoon: return "General"
        default: return "In-game menu"
        }
    }
}
