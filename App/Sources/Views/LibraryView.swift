import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct LibraryView: View {
    @EnvironmentObject var library: GameLibrary
    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var router: AppRouter
    @State private var showImporter = false
    @State private var showWebDAV = false
    @State private var search = ""
    @State private var filter: GameSystem?
    @State private var favoritesOnly = false
    @State private var editing: Game?

    private var theme: Theme { themes.active }
    private var style: AppStyle { theme.style }

    private var filtered: [Game] {
        library.games
            .filter { $0.system.isEnabled }
            .filter { filter == nil || $0.system == filter }
            .filter { !favoritesOnly || $0.favorite }
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemeBackground(style: theme.background)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let recent = library.recentlyPlayed.first {
                            continueCard(recent)
                        }
                        filterBar
                        if library.games.isEmpty {
                            emptyState
                        } else if filtered.isEmpty {
                            Text("No matches").font(style.font(.body)).foregroundStyle(style.secondaryText.color)
                                .frame(maxWidth: .infinity).padding(.top, 40)
                        } else {
                            gamesView
                        }
                        comingSoon
                    }
                    .padding()
                }
            }
            .navigationTitle(theme.label(.appTitle))
            .searchable(text: $search, prompt: theme.label(.search))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showImporter = true } label: { Label("Import from Files", systemImage: "folder") }
                        Button { showWebDAV = true } label: { Label("Download from a Server (WebDAV)", systemImage: "server.rack") }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .accessibilityLabel(theme.label(.importGames))
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: GameSystem.allExtensions.compactMap { UTType(filenameExtension: $0) } + [.data],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { library.importFiles(urls) }
            }
            .sheet(item: $editing) { game in GameDetailSheet(gameID: game.id) }
            .sheet(isPresented: $showWebDAV) { WebDAVBrowserView() }
            .confirmationDialog("Which console is \(library.needsSystemChoice.first ?? "this game") for?",
                                isPresented: Binding(get: { !library.needsSystemChoice.isEmpty },
                                                     set: { if !$0, !library.needsSystemChoice.isEmpty { library.needsSystemChoice.removeFirst() } }),
                                titleVisibility: .visible) {
                if let file = library.needsSystemChoice.first {
                    ForEach(SystemDetector.candidates(for: file)) { system in
                        Button(system.name) { library.assignSystem(system, to: file) }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let message = library.lastImportMessage {
                    Text(message)
                        .font(style.font(.subheadline, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                        .task {
                            try? await Task.sleep(for: .seconds(2.5))
                            library.lastImportMessage = nil
                        }
                }
            }
        }
    }

    // MARK: Sections

    private func continueCard(_ game: Game) -> some View {
        Button { router.play(game) } label: {
            HStack(spacing: 14) {
                GameArtwork(game: game, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(theme.label(.continuePlaying).uppercased())
                        .font(style.font(.caption, weight: .bold)).foregroundStyle(style.accent.color)
                    Text(game.title).font(style.font(.headline, weight: .bold)).foregroundStyle(style.primaryText.color)
                        .lineLimit(1)
                    Text("\(game.system.name) · \(game.formattedPlayTime)")
                        .font(style.font(.caption)).foregroundStyle(style.secondaryText.color)
                }
                Spacer()
                Image(systemName: "play.circle.fill").font(.system(size: 36)).foregroundStyle(style.accent.color)
            }
            .padding(14)
            .background(style.surface.color.opacity(0.92), in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(theme.label(.allGames), selected: filter == nil && !favoritesOnly) { filter = nil; favoritesOnly = false }
                chip(theme.label(.favorites), selected: favoritesOnly) { favoritesOnly.toggle() }
                // Only consoles you have games for.
                ForEach(GameSystem.available.filter { s in library.games.contains { $0.system == s } }) { system in
                    chip(system.shortName, selected: filter == system) { filter = filter == system ? nil : system }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(style.font(.subheadline, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(selected ? style.background.color : style.primaryText.color)
                .background(selected ? style.accent.color : style.surface.color.opacity(0.9), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var gamesView: some View {
        switch style.libraryLayout {
        case .grid:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                ForEach(filtered) { game in gridCell(game) }
            }
        case .list:
            LazyVStack(spacing: 10) {
                ForEach(filtered) { game in listRow(game) }
            }
        case .shelf:
            ForEach(GameSystem.allCases) { system in
                let games = filtered.filter { $0.system == system }
                if !games.isEmpty {
                    Text(system.name).font(style.font(.title3, weight: .bold)).foregroundStyle(style.primaryText.color)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) { ForEach(games) { game in gridCell(game).frame(width: 150) } }
                    }
                }
            }
        }
    }

    private func gridCell(_ game: Game) -> some View {
        Button { router.play(game) } label: {
            VStack(alignment: .leading, spacing: 8) {
                GameArtwork(game: game, size: nil)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(alignment: .topTrailing) {
                        if game.favorite {
                            Image(systemName: "star.fill").foregroundStyle(.yellow).padding(8)
                        }
                    }
                Text(game.title).font(style.font(.subheadline, weight: .semibold))
                    .foregroundStyle(style.primaryText.color).lineLimit(2)
                Text(game.system.shortName).font(style.font(.caption)).foregroundStyle(style.secondaryText.color)
            }
            .padding(10)
            .background(style.surface.color.opacity(0.92), in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu { gameMenu(game) }
    }

    private func listRow(_ game: Game) -> some View {
        Button { router.play(game) } label: {
            HStack(spacing: 12) {
                GameArtwork(game: game, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(game.title).font(style.font(.body, weight: .semibold)).foregroundStyle(style.primaryText.color)
                    Text("\(game.system.name) · \(game.formattedPlayTime)").font(style.font(.caption))
                        .foregroundStyle(style.secondaryText.color)
                }
                Spacer()
                if game.favorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
            }
            .padding(10)
            .background(style.surface.color.opacity(0.92), in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu { gameMenu(game) }
    }

    @ViewBuilder
    private func gameMenu(_ game: Game) -> some View {
        Button { router.play(game) } label: { Label("Play", systemImage: "play.fill") }
        Button { library.toggleFavorite(game) } label: {
            Label(game.favorite ? "Unfavorite" : "Favorite", systemImage: game.favorite ? "star.slash" : "star")
        }
        Button { editing = game } label: { Label("Edit Game", systemImage: "slider.horizontal.3") }
        Menu {
            ForEach(GameSystem.Maker.allCases, id: \.self) { maker in
                Section(maker.rawValue) {
                    ForEach(GameSystem.allCases.filter { $0.maker == maker }) { system in
                        Button {
                            library.changeSystem(of: game, to: system)
                        } label: {
                            if system == game.system { Label(system.name, systemImage: "checkmark") } else { Text(system.name) }
                        }
                    }
                }
            }
        } label: { Label("Change Console", systemImage: "arrow.triangle.swap") }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "gamecontroller.fill").font(.system(size: 54)).foregroundStyle(style.accent.color)
            Text(theme.label(.libraryEmpty)).font(style.font(.title2, weight: .bold)).foregroundStyle(style.primaryText.color)
            Text(theme.label(.libraryEmptyHint)).font(style.font(.body)).foregroundStyle(style.secondaryText.color)
                .multilineTextAlignment(.center)
            Button(theme.label(.importGames)) { showImporter = true }
                .buttonStyle(.borderedProminent)
            Text("Tip: you can also drop games into the Emu4ios › Games folder in the Files app.")
                .font(style.font(.footnote)).foregroundStyle(style.secondaryText.color).multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(style.surface.color.opacity(0.85), in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
    }

    private var comingSoon: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(theme.label(.comingSoon)).font(style.font(.headline, weight: .bold)).foregroundStyle(style.primaryText.color)
            Text(GameSystem.available.map(\.shortName).joined(separator: " · "))
                .font(style.font(.subheadline)).foregroundStyle(style.secondaryText.color)
        }
        .padding(.top, 8)
    }
}

/// Custom cover if set, otherwise a generated tile in the system's colors.
struct GameArtwork: View {
    @EnvironmentObject var library: GameLibrary
    @EnvironmentObject var themes: ThemeStore
    let game: Game
    let size: CGFloat?

    var body: some View {
        let radius = themes.active.style.cornerRadius * 0.7
        Group {
            if let image = library.coverImage(for: game) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(spacing: 4) {
                        Text(initials).font(.system(size: (size ?? 120) * 0.32, weight: .heavy, design: .rounded))
                        Text(game.system.shortName).font(.system(size: max((size ?? 120) * 0.12, 9), weight: .bold, design: .monospaced))
                            .opacity(0.8)
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            if library.findingArt.contains(game.id) {
                ProgressView().tint(.white).padding(8).background(.black.opacity(0.35), in: Circle())
            }
        }
    }

    private var initials: String {
        game.title.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private var gradient: [Color] {
        let hue = Double(abs(game.title.hashValueStable) % 360) / 360
        switch game.system {
        case .gb: return [Color(hue: 0.22, saturation: 0.5, brightness: 0.55), Color(hue: 0.25, saturation: 0.6, brightness: 0.3)]
        case .gbc: return [Color(hue: hue, saturation: 0.65, brightness: 0.85), Color(hue: (hue + 0.1).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.5)]
        case .gba: return [Color(hue: 0.72, saturation: 0.55, brightness: 0.7), Color(hue: hue, saturation: 0.6, brightness: 0.45)]
        case .ps1, .psp: return [Color(white: 0.55), Color(hue: hue, saturation: 0.35, brightness: 0.3)]
        default:
            // Each maker gets its own hue family.
            let base: Double
            switch game.system.maker {
            case .nintendo: base = 0.0
            case .sega: base = 0.6
            case .sony: base = 0.65
            case .nec: base = 0.08
            case .snk: base = 0.13
            case .atari: base = 0.03
            case .computer: base = 0.45
            }
            let h2 = (base + hue * 0.12).truncatingRemainder(dividingBy: 1)
            return [Color(hue: h2, saturation: 0.6, brightness: 0.75), Color(hue: (h2 + 0.06).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.38)]
        }
    }
}

extension String {
    /// Stable across launches (unlike `hashValue`), so generated covers don't change colors.
    var hashValueStable: Int {
        var hash = 5381
        for byte in utf8 { hash = (hash &* 33) &+ Int(byte) }
        return hash
    }
}

/// Per-game options: cover art, title, theme override, cheats, delete.
struct GameDetailSheet: View {
    let gameID: String
    @EnvironmentObject var library: GameLibrary
    @EnvironmentObject var themes: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var coverItem: PhotosPickerItem?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            if let game = library.game(id: gameID) {
                Form {
                    Section {
                        HStack {
                            Spacer()
                            GameArtwork(game: game, size: 140)
                            Spacer()
                        }
                        Button {
                            library.findArt(for: game, manual: true)
                        } label: {
                            if library.findingArt.contains(game.id) {
                                HStack { ProgressView(); Text("Looking up game…") }
                            } else {
                                Label("Find Cover Art & Name Automatically", systemImage: "sparkle.magnifyingglass")
                            }
                        }
                        .disabled(library.findingArt.contains(game.id))
                        PhotosPicker(selection: $coverItem, matching: .images) {
                            Label("Choose My Own Cover Art", systemImage: "photo")
                        }
                        if game.coverFileName != nil {
                            Button("Remove Cover Art", role: .destructive) { library.removeCover(for: game) }
                        }
                    }
                    if let message = library.lastImportMessage {
                        Section { Text(message).foregroundStyle(.secondary) }
                    }
                    Section("Title") {
                        TextField("Title", text: Binding(
                            get: { library.game(id: gameID)?.title ?? "" },
                            set: { var g = game; g.title = $0; library.update(g) }))
                    }
                    Section {
                        Picker("Theme for this game", selection: Binding(
                            get: { game.themeOverrideID ?? "" },
                            set: { var g = game; g.themeOverrideID = $0.isEmpty ? nil : $0; library.update(g) })) {
                            Text("Use my normal theme").tag("")
                            ForEach(themes.allThemes) { t in Text(t.name).tag(t.id) }
                        }
                    } footer: {
                        Text("Give a game its own look and controller layout.")
                    }
                    Section("Save Data") {
                        NavigationLink { GameSaveView(gameID: gameID) } label: {
                            Label("Send, Swap or Restore Saves", systemImage: "externaldrive")
                        }
                        if LayoutStore.shared.hasCustomLayout(gameID) {
                            Button("Reset This Game's Controller Layout") { LayoutStore.shared.remove(gameID) }
                        }
                    }
                    Section("Cheats") {
                        NavigationLink {
                            CheatsEditor(gameID: gameID, session: nil)
                        } label: {
                            LabeledContent("Cheat Codes", value: "\(game.cheats.filter(\.enabled).count) on")
                        }
                    }
                    Section("Stats") {
                        LabeledContent("Play time", value: game.formattedPlayTime)
                        LabeledContent("Sessions", value: "\(game.sessions)")
                        if let last = game.lastPlayed {
                            LabeledContent("Last played", value: last.formatted(date: .abbreviated, time: .shortened))
                        }
                        LabeledContent("File", value: game.fileName)
                    }
                    Section {
                        Button("Delete Game", role: .destructive) { confirmDelete = true }
                    }
                }
                .navigationTitle(game.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onChange(of: coverItem) { _, item in
                    Task {
                        if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                            library.setCover(image, for: game)
                        }
                    }
                }
                .confirmationDialog("Delete \(game.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete Game, Keep Saves", role: .destructive) { library.delete(game); dismiss() }
                    Button("Delete Game and All Saves", role: .destructive) { library.delete(game, keepSaves: false); dismiss() }
                }
            } else {
                Text("Game not found")
            }
        }
    }
}
