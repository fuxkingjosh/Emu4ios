import SwiftUI

struct RootView: View {
    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var library: GameLibrary
    @Environment(\.scenePhase) private var scenePhase
    @State private var debugEditorSystem: GameSystem?

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
        .overlay(alignment: .top) { BadgeBanner() }
        #if DEBUG
        .task { debugLaunchOptions() }
        .fullScreenCover(item: $debugEditorSystem) { system in
            LayoutEditorView(theme: themes.active, system: system)
        }
        #endif
    }

    #if DEBUG
    /// Used by the cloud build to take screenshots: `-E4AutoPlay "file.gba"`, `-E4StartTab themes`.
    private func debugLaunchOptions() {
        let defaults = UserDefaults.standard
        if let tab = defaults.string(forKey: "E4StartTab") {
            router.handle(URL(string: "emu4ios://tab?name=\(tab)")!, library: library, themes: themes)
        }
        if let system = defaults.string(forKey: "E4OpenEditor").flatMap(GameSystem.init(rawValue:)) {
            debugEditorSystem = system
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

/// Pops up when a badge is earned.
struct BadgeBanner: View {
    @ObservedObject private var stats = PlayStats.shared
    @EnvironmentObject var themes: ThemeStore

    var body: some View {
        if let badge = stats.newlyEarned {
            HStack(spacing: 12) {
                Image(systemName: badge.icon).font(.title2).foregroundStyle(themes.active.style.accent.color)
                VStack(alignment: .leading) {
                    Text("Badge unlocked: \(badge.title)").font(.subheadline.bold())
                    Text(badge.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: badge.id) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                try? await Task.sleep(for: .seconds(3))
                withAnimation { stats.newlyEarned = nil }
            }
        }
    }
}
