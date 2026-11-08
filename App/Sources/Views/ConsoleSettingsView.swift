import SwiftUI

/// Every console Emu4ios plays, with its emulator settings and BIOS status.
struct ConsoleSettingsView: View {
    @EnvironmentObject var library: GameLibrary

    var body: some View {
        List {
            Section {
                Text("Put BIOS and firmware files in Files → Emu4ios → BIOS. Most consoles don't need any.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(GameSystem.Maker.allCases, id: \.self) { maker in
                Section(maker.rawValue) {
                    ForEach(GameSystem.allCases.filter { $0.maker == maker }) { system in
                        NavigationLink { ConsoleDetailView(system: system) } label: { row(system) }
                    }
                }
            }
        }
        .navigationTitle("Consoles")
    }

    private func row(_ system: GameSystem) -> some View {
        let count = library.games.filter { $0.system == system }.count
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(system.name)
                Text(count == 1 ? "1 game" : "\(count) games").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !system.isAvailable {
                Text("Not in this build").font(.caption).foregroundStyle(.orange)
            } else if !ConsoleDetailView.missingBIOS(system).isEmpty {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
        }
    }
}

struct ConsoleDetailView: View {
    let system: GameSystem
    @State private var refresh = 0

    static func missingBIOS(_ system: GameSystem) -> [String] {
        system.requiredBIOS.filter {
            !FileManager.default.fileExists(atPath: EmulatorCores.biosFolder.appendingPathComponent($0).path)
        }
    }

    var body: some View {
        List {
            Section("About") {
                LabeledContent("Emulator", value: system.coreFramework ?? "mGBA")
                LabeledContent("File types", value: fileTypes)
                LabeledContent("Status", value: system.isAvailable ? "Ready" : "Not in this build")
            }
            if !system.requiredBIOS.isEmpty {
                Section {
                    ForEach(system.requiredBIOS, id: \.self) { file in
                        let present = !Self.missingBIOS(system).contains(file)
                        Label(file, systemImage: present ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(present ? .green : .red)
                    }
                } header: {
                    Text("BIOS")
                } footer: {
                    Text("Copy your own BIOS file into Files → Emu4ios → BIOS (exact file name). Emu4ios can't provide it.")
                }
            }
            let settings = CoreOptionOverrides.settings.filter { $0.system == system }
            if !settings.isEmpty {
                Section {
                    ForEach(settings) { setting in
                        Picker(selection: Binding(
                            get: { _ = refresh; return CoreOptionOverrides.value(for: setting) },
                            set: { CoreOptionOverrides.set($0, for: setting); refresh += 1 })) {
                            ForEach(setting.choices) { Text($0.title).tag($0.value) }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(setting.title)
                                Text(setting.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Settings")
                } footer: {
                    Text("Changes apply the next time you start a game.")
                }
            }
            if let tips = tips {
                Section("Tips") { Text(tips).font(.footnote) }
            }
        }
        .navigationTitle(system.shortName)
    }

    private var fileTypes: String {
        var types = system.fileExtensions
        if system.isDiscBased { types += ["cue", "chd", "iso"] }
        if [.genesis, .atari2600].contains(system) { types.append("bin") }
        return types.map { "." + $0 }.joined(separator: " ")
    }

    private var tips: String? {
        switch system {
        case .nds: return "Tap the bottom screen to use the touch screen. The built-in firmware works for nearly every game."
        case .n64: return "Drag the stick on the left. The yellow C buttons work like the right stick."
        case .psp: return "Some PSP games are heavy; lower the resolution if a game runs slowly."
        case .dos: return "Import a .zip of the game folder. Tap the ⌨︎ button for the keyboard; drag on the screen to move the mouse, tap to click, tap with two fingers to right-click."
        case .amiga: return "Without a Kickstart ROM, Emu4ios uses the free AROS replacement. Drag on the screen to move the mouse."
        case .c64: return "Tap ⌨︎ to type. Most games load automatically."
        case .doom: return "Works with DOOM, DOOM II, Final DOOM and the free Freedoom WADs."
        case .lynx: return "The Lynx needs lynxboot.img in the BIOS folder."
        case .pcecd: return "PC Engine CD games need syscard3.pce in the BIOS folder."
        case .vb: return "The right D-pad is on the right; A and B sit underneath it."
        default: return nil
        }
    }
}
