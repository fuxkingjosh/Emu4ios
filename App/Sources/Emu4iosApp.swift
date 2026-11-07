import SwiftUI

@main
struct Emu4iosApp: App {
    @StateObject private var library = GameLibrary()
    @StateObject private var themes = ThemeStore()
    @StateObject private var gestures = GestureSettings()
    @StateObject private var router = AppRouter()

    init() {
        CloudSync.shared.start()
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
                let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value
                if let id, let game = library.game(id: id) { play(game) }
            default:
                break
            }
            return
        }
        // Files opened from the Files app, AirDrop, Messages…
        if url.pathExtension.lowercased() == "e4theme" {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do { incomingTheme = try ThemeSharing.decode(Data(contentsOf: url)) }
            catch { errorMessage = error.localizedDescription }
        } else if GameSystem(fileExtension: url.pathExtension) != nil {
            library.importFiles([url])
            selectedTab = .library
        }
    }

    func play(_ game: Game) {
        guard playing == nil else { return }
        playing = game
    }
}
