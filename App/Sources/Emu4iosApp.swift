import SwiftUI

@main
struct Emu4iosApp: App {
    @StateObject private var library = GameLibrary()
    @StateObject private var themes = ThemeStore()
    @StateObject private var gestures = GestureSettings()
    @StateObject private var router = AppRouter()

    init() {
        CloudSync.shared.start()
        Task { @MainActor in
            Achievements.shared.start()
            LiveActivityController.shared.setUp() // clears a "playing" timer left by older builds
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(themes)
                .environmentObject(gestures)
                .environmentObject(router)
                .onOpenURL { url in router.handle(url, library: library, themes: themes) }
        }
    }
}

/// App-wide navigation state: which game is running and any pending shared theme.
@MainActor
final class AppRouter: ObservableObject {
    @Published var playing: Game?
    @Published var incomingTheme: Theme?
    @Published var errorMessage: String?
    @Published var selectedTab: Tab = .library

    enum Tab: Hashable { case library, themes, stats, settings }

    func handle(_ url: URL, library: GameLibrary, themes: ThemeStore) {
        if url.scheme == "emu4ios" {
            switch url.host {
            case "theme":
                do { incomingTheme = try ThemeSharing.theme(fromLink: url) }
                catch { errorMessage = error.localizedDescription }
            case "play":
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let id = items.first { $0.name == "id" }?.value
                let file = items.first { $0.name == "file" }?.value
                library.scanForNewFiles()
                if let game = id.flatMap(library.game(id:)) ?? library.games.first(where: { $0.fileName == file }) {
                    play(game)
                }
            case "tab":
                let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "name" }?.value
                switch name {
                case "themes": selectedTab = .themes
                case "stats": selectedTab = .stats
                case "settings": selectedTab = .settings
                default: selectedTab = .library
                }
            default:
                break
            }
            return
        }
        // Files opened from the Files app, AirDrop, Messages…
        if url.pathExtension.lowercased() == "deltaskin" {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do { incomingTheme = try DeltaSkinImporter.makeTheme(from: url, base: themes.active) }
            catch { errorMessage = error.localizedDescription }
            selectedTab = .themes
            return
        }
        if url.pathExtension.lowercased() == "e4theme" {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do { incomingTheme = try ThemeSharing.decode(Data(contentsOf: url)) }
            catch { errorMessage = error.localizedDescription }
        } else if GameSystem.allExtensions.contains(url.pathExtension.lowercased()) {
            library.importFiles([url])
            selectedTab = .library
        }
    }

    func play(_ game: Game) {
        guard playing == nil else { return }
        playing = game
    }
}
