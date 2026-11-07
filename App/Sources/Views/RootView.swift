import SwiftUI

struct RootView: View {
    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var library: GameLibrary
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let theme = themes.active
        TabView(selection: $router.selectedTab) {
            LibraryView()
                .tabItem { Label(theme.label(.libraryTitle), systemImage: "square.grid.2x2.fill") }
                .tag(AppRouter.Tab.library)
            ThemesView()
                .tabItem { Label(theme.label(.themesTitle), systemImage: "paintpalette.fill") }
                .tag(AppRouter.Tab.themes)
            StatsView()
                .tabItem { Label(theme.label(.statsTitle), systemImage: "chart.bar.fill") }
                .tag(AppRouter.Tab.stats)
            SettingsView()
                .tabItem { Label(theme.label(.settingsTitle), systemImage: "gearshape.fill") }
                .tag(AppRouter.Tab.settings)
        }
        .tint(theme.style.accent.color)
        .preferredColorScheme(theme.style.darkMode ? .dark : .light)
        .fullScreenCover(item: $router.playing) { game in
            GameContainerView(game: game)
        }
        .sheet(item: $router.incomingTheme) { incoming in
            ThemeImportSheet(theme: incoming)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { router.errorMessage != nil },
            set: { if !$0 { router.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(router.errorMessage ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library.scanForNewFiles() }
        }
        #if DEBUG
        .task { debugLaunchOptions() }
        #endif
    }

    #if DEBUG
    /// Used by the cloud build to take screenshots: `-E4AutoPlay "file.gba"`, `-E4StartTab themes`.
    private func debugLaunchOptions() {
        let defaults = UserDefaults.standard
        if let tab = defaults.string(forKey: "E4StartTab") {
            router.handle(URL(string: "emu4ios://tab?name=\(tab)")!, library: library, themes: themes)
        }
        if let file = defaults.string(forKey: "E4AutoPlay") {
            library.scanForNewFiles()
            if let game = library.games.first(where: { $0.fileName == file }) { router.play(game) }
        }
    }
    #endif
}

/// Shown when someone opens a shared theme link, QR code or file.
struct ThemeImportSheet: View {
    let theme: Theme
    @EnvironmentObject var themes: ThemeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ThemePreviewCard(theme: theme)
                    .frame(height: 320)
                    .padding(.horizontal)
                VStack(spacing: 4) {
                    Text(theme.name).font(.title2.bold())
                    if !theme.author.isEmpty { Text("by \(theme.author)").foregroundStyle(.secondary) }
                }
                Button {
                    let saved = themes.importTheme(theme)
                    themes.activeThemeID = saved.id
                    dismiss()
                } label: {
                    Text("Add & Use Theme").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                Button("Just Add It") {
                    themes.importTheme(theme)
                    dismiss()
                }
                Spacer()
            }
            .padding(.top)
            .navigationTitle("Shared Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
