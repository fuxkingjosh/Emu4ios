import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var gestures: GestureSettings
    @AppStorage("autoResume") private var autoResume = true
    @AppStorage("autoCoverArt") private var autoCoverArt = true
    @AppStorage("liveActivityEnabled") private var liveActivity = true
    @AppStorage("rewindEnabled") private var rewindEnabled = true
    @AppStorage("respectSilentSwitch") private var respectSilentSwitch = true
    @AppStorage("clipsEnabled") private var clipsEnabled = true
    @AppStorage("clipLength") private var clipLength = 30.0
    @AppStorage("cloudSyncEnabled") private var cloudSyncEnabled = true
    @State private var cloudAvailable = CloudSync.shared.isAvailable
    @State private var showControllerMode = false
    @AppStorage("tvMode") private var tvMode = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { SavesView() } label: { Label("Saves & Backups", systemImage: "externaldrive") }
                    Toggle("Find Cover Art Automatically", isOn: $autoCoverArt)
                } header: {
                    Text("Library")
                } footer: {
                    Text("Identifies your games and downloads their box art and official names from the free libretro game database. Needs an internet connection the first time.")
                }

                Section("Playing") {
                    Toggle("Resume Where You Left Off", isOn: $autoResume)
                    Toggle("Rewind", isOn: $rewindEnabled)
                    Toggle("Mute With Silent Switch", isOn: $respectSilentSwitch)
                    Toggle("Show on Lock Screen & Dynamic Island", isOn: $liveActivity)
                    Toggle("Play on TV When Connected", isOn: $tvMode)
                }

                Section {
                    ForEach(ScreenGesture.allCases) { gesture in
                        Picker(gesture.displayName, selection: Binding(
                            get: { gestures.action(for: gesture) },
                            set: { gestures.mapping[gesture] = $0 })) {
                            ForEach(GestureAction.allCases) { Text($0.displayName).tag($0) }
                        }
                    }
                    Button("Reset Gestures") { gestures.mapping = GestureSettings.defaults }
                } header: {
                    Text("Screen Gestures")
                } footer: {
                    Text("Gestures work on the game screen while you play.")
                }

                Section {
                    Toggle("Gameplay Clips", isOn: $clipsEnabled)
                    if clipsEnabled {
                        Picker("Clip Length", selection: $clipLength) {
                            Text("15 seconds").tag(15.0)
                            Text("30 seconds").tag(30.0)
                            Text("60 seconds").tag(60.0)
                        }
                    }
                } header: {
                    Text("Clips")
                } footer: {
                    Text("Records the game screen and sound in the background so you can save the last moments to Photos from the menu, a gesture, or a Clip button on your controller.")
                }

                Section {
                    Toggle("iCloud Sync", isOn: $cloudSyncEnabled)
                    if cloudSyncEnabled {
                        if cloudAvailable {
                            Button("Sync Now") { CloudSync.shared.syncNow() }
                        } else {
                            Text("iCloud isn't available. Make sure you're signed in to iCloud and iCloud Drive is on.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Syncs saves, save states and themes between your devices.")
                }

                Section {
                    AppIconPicker()
                    NavigationLink {
                        IconStudioView()
                    } label: {
                        Label("Design Your Own Icon", systemImage: "paintpalette")
                    }
                } header: {
                    Text("App Icon")
                }

                Section {
                    NavigationLink { AchievementSettingsView() } label: {
                        Label("RetroAchievements", systemImage: "trophy")
                    }
                } header: {
                    Text("Achievements")
                } footer: {
                    Text("Earn achievements in thousands of classic games with a free RetroAchievements account.")
                }

                Section {
                    NavigationLink { ConsoleSettingsView() } label: {
                        Label("Consoles & BIOS", systemImage: "gamecontroller")
                    }
                } header: {
                    Text("Consoles")
                } footer: {
                    Text("\(GameSystem.available.count) consoles. Tune resolution and other options, and check BIOS files.")
                }

                Section {
                    Button { showControllerMode = true } label: {
                        Label("Be a Controller for a Friend", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    }
                } header: {
                    Text("Multiplayer")
                } footer: {
                    Text("Use this iPhone as player 2, 3 or 4 for a game running on a phone nearby — no internet needed.")
                }

                Section("Controllers & Keyboards") {
                    Text("Xbox, PlayStation and MFi controllers connect automatically — up to four, one per player. Spare triggers: left = rewind, right = fast forward. Keyboard: arrows, X = A, Z = B, C/V = Y/X, A/S = L/R, Q/W = L2/R2, I/J/K/L = N64 C buttons, Enter = Start, Shift = Select, Tab = fast forward, O/P = quick save/load, Esc = menu. In DOS, Commodore 64 and Amiga games every key types into the game.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                    NavigationLink("Legal & Licenses") { LegalView() }
                }
            }
            .navigationTitle(themes.active.label(.settingsTitle))
            .fullScreenCover(isPresented: $showControllerMode) { ControllerModeView() }
            .onAppear { cloudAvailable = CloudSync.shared.isAvailable }
        }
    }
}

struct AppIconPicker: View {
    @State private var current = UIApplication.shared.alternateIconName

    private struct IconOption: Identifiable {
        let name: String?
        let title: String
        let preview: String
        var id: String { title }
    }

    private let icons: [IconOption] = [
        IconOption(name: nil, title: "Classic", preview: "IconPreview-Default"),
        IconOption(name: "AppIcon-Neon", title: "Neon", preview: "IconPreview-Neon"),
        IconOption(name: "AppIcon-Retro", title: "Pea Soup", preview: "IconPreview-Retro"),
        IconOption(name: "AppIcon-Candy", title: "Candy", preview: "IconPreview-Candy"),
        IconOption(name: "AppIcon-Midnight", title: "Midnight", preview: "IconPreview-Midnight"),
        IconOption(name: "AppIcon-Gold", title: "Gold", preview: "IconPreview-Gold"),
        IconOption(name: "AppIcon-Ocean", title: "Ocean", preview: "IconPreview-Ocean"),
        IconOption(name: "AppIcon-Lava", title: "Lava", preview: "IconPreview-Lava"),
        IconOption(name: "AppIcon-Mint", title: "Mint", preview: "IconPreview-Mint"),
        IconOption(name: "AppIcon-BigFour", title: "Big 4", preview: "IconPreview-BigFour"),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(icons) { icon in
                    Button {
                        UIApplication.shared.setAlternateIconName(icon.name) { error in
                            if error == nil { current = icon.name }
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(icon.preview)
                                .resizable()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(current == icon.name ? Color.accentColor : .clear, lineWidth: 3))
                            Text(icon.title).font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct LegalView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Emu4ios does not include any games. Only play games you own and have the right to use.")
                    .font(.headline)
                Text("Emu4ios is not affiliated with, endorsed by, or sponsored by Nintendo, Sony Interactive Entertainment, Sega, Atari, NEC, SNK, Bandai, Commodore or id Software. All trademarks belong to their respective owners.")
                Divider()
                Text("Open Source").font(.title3.bold())
                Text("Game Boy, Game Boy Color and Game Boy Advance emulation is powered by mGBA by Vicki Pfau and contributors, licensed under the Mozilla Public License 2.0. The mGBA source code is available at github.com/mgba-emu/mgba.")
                credit("Game Boy, Game Boy Color, Game Boy Advance — mGBA", "MPL-2.0", "github.com/mgba-emu/mgba")
                credit("PlayStation", "GPL-2.0-or-later", "github.com/libretro/pcsx_rearmed")
                credit("NES, Famicom Disk System", "GPL-3.0", "github.com/libretro/mesen")
                credit("SNES", "GPL-3.0", "github.com/libretro/bsnes")
                credit("Genesis / Mega Drive, Sega CD", "AGPL-3.0", "github.com/Clownacy/clownmdemu-libretro")
                credit("Master System, Game Gear, SG-1000", "GPL-3.0", "github.com/drhelius/Gearsystem")
                credit("Nintendo 64", "GPL-2.0-or-later", "github.com/libretro/mupen64plus-libretro-nx")
                credit("PC Engine / TurboGrafx-16, CD", "GPL-2.0-or-later", "github.com/libretro/beetle-pce-fast-libretro")
                credit("SuperGrafx", "GPL-3.0", "github.com/drhelius/Geargrafx")
                credit("Neo Geo Pocket (Color)", "GPL-2.0-or-later", "github.com/libretro/beetle-ngp-libretro")
                credit("WonderSwan (Color)", "GPL-2.0-or-later", "github.com/libretro/beetle-wswan-libretro")
                credit("Virtual Boy", "GPL-2.0-or-later", "github.com/libretro/beetle-vb-libretro")
                credit("Atari Lynx", "GPL-2.0-or-later", "github.com/libretro/beetle-lynx-libretro")
                credit("Atari 2600", "GPL-2.0-or-later", "github.com/libretro/stella2014-libretro")
                credit("Atari 5200", "GPL-2.0-or-later", "github.com/libretro/a5200")
                credit("Atari 7800", "GPL-2.0-or-later", "github.com/libretro/prosystem-libretro")
                credit("Atari Jaguar", "GPL-3.0", "github.com/libretro/virtualjaguar-libretro")
                credit("Pokémon Mini", "GPL-3.0", "github.com/libretro/PokeMini")
                credit("Commodore 64", "GPL-2.0-or-later", "github.com/libretro/vice-libretro")
                credit("Amiga", "GPL-2.0-or-later", "github.com/libretro/libretro-uae")
                credit("MS-DOS", "GPL-2.0-or-later", "github.com/libretro/dosbox-pure")
                credit("DOOM", "GPL-2.0-or-later", "github.com/libretro/libretro-prboom")
                credit("Nintendo DS", "GPL-3.0", "github.com/JesseTG/melonds-ds")
                credit("PSP", "GPL-2.0-or-later", "github.com/hrydgard/ppsspp")
                Text("Emu4ios is free software under the GNU General Public License v3. Its full source code is available at github.com/fuxkingjosh/Emu4ios.")
            }
            .padding()
        }
        .navigationTitle("Legal")
    }

    private func credit(_ what: String, _ license: String, _ source: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(what).font(.subheadline.bold())
            Text("\(license) · \(source)").font(.caption).foregroundStyle(.secondary)
        }
    }
}
