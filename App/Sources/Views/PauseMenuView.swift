import SwiftUI

struct PauseMenuView: View {
    @ObservedObject var session: EmulatorSession
    let theme: Theme
    @Binding var controllerHidden: Bool
    let onEditLayout: () -> Void
    let onQuit: () -> Void

    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var library: GameLibrary
    @State private var confirmRestart = false

    private var style: AppStyle { theme.style }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { session.closeMenu() } label: {
                        Label(theme.label(.resume), systemImage: "play.fill").font(style.font(.headline, weight: .bold))
                    }
                }

                Section(theme.label(.saveState)) {
                    SaveSlotsGrid(session: session, mode: .save)
                }

                Section(theme.label(.loadState)) {
                    if session.saveStates.isEmpty {
                        Text("No save states yet").foregroundStyle(.secondary)
                    } else {
                        SaveSlotsGrid(session: session, mode: .load)
                    }
                }

                Section(theme.label(.speed)) {
                    Picker(theme.label(.speed), selection: Binding(
                        get: { session.isFastForwarding ? session.speedPreset : 1 },
                        set: { session.setSpeed($0) })) {
                        ForEach([0.5, 1, 1.5, 2, 3, 4, 8], id: \.self) { value in
                            Text("\(value.formatted())×").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(theme.label(.screenFilter)) {
                    Picker(theme.label(.screenFilter), selection: Binding(
                        get: { theme.screen.filter },
                        set: { newValue in
                            var editable = themes.editableTheme(theme, library: library)
                            editable.screen.filter = newValue
                            themes.save(editable)
                        })) {
                        ForEach(ScreenFilter.allCases) { Text($0.displayName).tag($0) }
                    }
                }

                Section {
                    NavigationLink {
                        CheatsEditor(gameID: session.game.id, session: session)
                    } label: {
                        Label(theme.label(.cheats), systemImage: "wand.and.stars")
                    }
                    Button {
                        session.isMenuOpen = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { onEditLayout() }
                    } label: {
                        Label(theme.label(.editController), systemImage: "slider.horizontal.below.rectangle")
                    }
                    Toggle(isOn: $controllerHidden) {
                        Label("Hide Touch Controls", systemImage: "eye.slash")
                    }
                    Button { session.takeScreenshot() } label: { Label("Screenshot", systemImage: "camera") }
                    Button { session.saveClip() } label: { Label("Save Last \(Int(ClipRecorder.shared.clipLength))s Clip", systemImage: "film") }
                }

                Section {
                    Button { confirmRestart = true } label: { Label(theme.label(.restart), systemImage: "arrow.counterclockwise") }
                    Button(role: .destructive) {
                        session.isMenuOpen = false
                        onQuit()
                    } label: {
                        Label(theme.label(.quit), systemImage: "xmark.circle")
                    }
                }
            }
            .navigationTitle(session.game.title)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Restart the game? Unsaved progress will be lost.", isPresented: $confirmRestart, titleVisibility: .visible) {
                Button(theme.label(.restart), role: .destructive) { session.restart() }
            }
        }
        .tint(style.accent.color)
    }
}

struct SaveSlotsGrid: View {
    enum Mode { case save, load }
    @ObservedObject var session: EmulatorSession
    let mode: Mode

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(slots, id: \.self) { slot in
                    let info = session.saveStates.first { $0.slot == slot }
                    Button {
                        switch mode {
                        case .save:
                            session.writeState(slot: slot)
                        case .load:
                            if let info, session.loadState(info) { session.closeMenu() }
                        }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.15))
                                if let info, let image = UIImage(contentsOfFile: info.screenshotURL.path) {
                                    Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    Image(systemName: mode == .save ? "plus" : "tray").foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 120, height: 80)
                            Text(title(slot)).font(.caption.bold())
                            Text(info?.date.formatted(date: .abbreviated, time: .shortened) ?? "Empty")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(mode == .load && info == nil)
                    .contextMenu {
                        if let info {
                            Button("Delete", role: .destructive) { session.deleteState(info) }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var slots: [Int] {
        switch mode {
        case .save: return Array(1...9)
        case .load:
            let used = Set(session.saveStates.map(\.slot))
            return [EmulatorSession.autoSlot, EmulatorSession.quickSlot].filter(used.contains) + (1...9).filter(used.contains)
        }
    }

    private func title(_ slot: Int) -> String {
        switch slot {
        case EmulatorSession.autoSlot: return "Auto Save"
        case EmulatorSession.quickSlot: return "Quick Save"
        default: return "Slot \(slot)"
        }
    }
}

struct CheatsEditor: View {
    let gameID: String
    let session: EmulatorSession?
    @EnvironmentObject var library: GameLibrary
    @State private var name = ""
    @State private var code = ""
    @State private var error: String?

    private var game: Game? { library.game(id: gameID) }

    var body: some View {
        Form {
            Section {
                TextField("Name (e.g. Infinite Health)", text: $name)
                TextField("Code", text: $code, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .lineLimit(2...6)
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                Button("Add Cheat") { add() }.disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("New Cheat")
            } footer: {
                Text("Supports GameShark, Action Replay, CodeBreaker and Game Genie codes. Put each line of a multi-line code on its own line.")
            }

            if let game, !game.cheats.isEmpty {
                Section("Cheats") {
                    ForEach(game.cheats) { cheat in
                        Toggle(isOn: Binding(
                            get: { cheat.enabled },
                            set: { on in mutate { g in
                                if let i = g.cheats.firstIndex(where: { $0.id == cheat.id }) { g.cheats[i].enabled = on }
                            } })) {
                            VStack(alignment: .leading) {
                                Text(cheat.name)
                                Text(cheat.code).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .onDelete { offsets in mutate { $0.cheats.remove(atOffsets: offsets) } }
                }
            }
        }
        .navigationTitle("Cheats")
    }

    private func add() {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if let session, !session.validateCheat(trimmed) {
            error = "That code wasn't recognized for this game."
            session.applyCheats(game?.cheats ?? [])
            return
        }
        error = nil
        let label = name.isEmpty ? "Cheat \((game?.cheats.count ?? 0) + 1)" : name
        mutate { $0.cheats.append(Cheat(name: label, code: trimmed)) }
        name = ""
        code = ""
    }

    private func mutate(_ change: (inout Game) -> Void) {
        guard var g = game else { return }
        change(&g)
        library.update(g)
        session?.applyCheats(g.cheats)
    }
}
