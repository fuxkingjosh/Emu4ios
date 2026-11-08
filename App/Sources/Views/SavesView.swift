import SwiftUI
import UniformTypeIdentifiers

/// Settings › Saves & Backups
struct SavesView: View {
    @EnvironmentObject var library: GameLibrary
    @State private var backupURL: URL?
    @State private var showRestorePicker = false
    @State private var message: String?
    @State private var working = false

    var body: some View {
        List {
            Section {
                Button {
                    working = true
                    Task.detached {
                        let result = Result { try SaveTools.makeFullBackup() }
                        await MainActor.run {
                            working = false
                            switch result {
                            case .success(let url): backupURL = url
                            case .failure: message = "Couldn't make the backup."
                            }
                        }
                    }
                } label: {
                    HStack {
                        Label("Back Up Everything", systemImage: "archivebox")
                        if working { Spacer(); ProgressView() }
                    }
                }
                if let backupURL {
                    ShareLink(item: backupURL) { Label("Save or Send Backup File", systemImage: "square.and.arrow.up") }
                }
                Button { showRestorePicker = true } label: { Label("Restore From Backup", systemImage: "arrow.counterclockwise") }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } footer: {
                Text("A backup holds every save, save state and theme. Keep it in Files or iCloud Drive, or send it to your new phone.")
            }

            Section("Games") {
                ForEach(library.games.sorted { $0.title < $1.title }) { game in
                    NavigationLink {
                        GameSaveView(gameID: game.id)
                    } label: {
                        HStack {
                            GameArtwork(game: game, size: 40)
                            VStack(alignment: .leading) {
                                Text(game.title).lineLimit(1)
                                Text(summary(game)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Saves & Backups")
        .fileImporter(isPresented: $showRestorePicker, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            do {
                try SaveTools.restoreFullBackup(from: url)
                message = "Restored ✓"
            } catch {
                message = "That file isn't an Emu4ios backup."
            }
        }
    }

    private func summary(_ game: Game) -> String {
        let save = SaveTools.hasSave(game)
            ? "Save: \(ByteCountFormatter.string(fromByteCount: Int64(SaveTools.saveSize(game)), countStyle: .file))" : "No save yet"
        let states = SaveTools.stateCount(game)
        return states > 0 ? "\(save) · \(states) save states" : save
    }
}

/// One game's save: send to a friend, import theirs, restore older copies.
struct GameSaveView: View {
    let gameID: String
    @EnvironmentObject var library: GameLibrary
    @State private var showImporter = false
    @State private var confirmDelete = false
    @State private var message: String?
    @State private var refresh = 0

    var body: some View {
        if let game = library.game(id: gameID) {
            List {
                Section {
                    if SaveTools.hasSave(game), let url = try? SaveTools.exportCopy(for: game) {
                        ShareLink(item: url) { Label("Send My Save", systemImage: "square.and.arrow.up") }
                    } else {
                        Text("No save yet — save in the game first.").foregroundStyle(.secondary)
                    }
                    Button { showImporter = true } label: { Label("Use a Save File…", systemImage: "square.and.arrow.down") }
                    if SaveTools.hasSave(game) {
                        Button("Delete Save", role: .destructive) { confirmDelete = true }
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                } footer: {
                    Text("Swap saves with friends: send yours, or open theirs here. Your current save is always backed up first.")
                }
                let backups = SaveTools.backups(for: game)
                if !backups.isEmpty {
                    Section("Older Copies") {
                        ForEach(backups, id: \.self) { url in
                            Button {
                                do { try SaveTools.restore(url, into: game); message = "Restored that copy ✓"; refresh += 1 }
                                catch { message = "Couldn't restore that copy." }
                            } label: {
                                Label(url.deletingPathExtension().lastPathComponent
                                        .replacingOccurrences(of: SaveTools.saveURL(for: game).deletingPathExtension().lastPathComponent + " ", with: ""),
                                      systemImage: "clock.arrow.circlepath")
                            }
                        }
                    }
                }
            }
            .id(refresh)
            .navigationTitle(game.title)
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
                guard case .success(let url) = result else { return }
                do { try SaveTools.importSave(from: url, into: game); message = "Save imported ✓"; refresh += 1 }
                catch { message = "Couldn't use that file as a save." }
            }
            .confirmationDialog("Delete this save? A backup copy is kept.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Save", role: .destructive) {
                    try? SaveTools.deleteSave(game)
                    refresh += 1
                }
            }
        }
    }
}
