import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var gestures: GestureSettings
    @AppStorage("autoResume") private var autoResume = true
    @AppStorage("rewindEnabled") private var rewindEnabled = true
    @AppStorage("respectSilentSwitch") private var respectSilentSwitch = true
    @AppStorage("clipsEnabled") private var clipsEnabled = false
    @AppStorage("clipLength") private var clipLength = 30.0
    @AppStorage("cloudSyncEnabled") private var cloudSyncEnabled = true
    @State private var cloudAvailable = CloudSync.shared.isAvailable

    var body: some View {
        NavigationStack {
            Form {
                Section("Playing") {
                    Toggle("Resume Where You Left Off", isOn: $autoResume)
                    Toggle("Rewind", isOn: $rewindEnabled)
                    Toggle("Mute With Silent Switch", isOn: $respectSilentSwitch)
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
                    Text("Keeps the last moments of gameplay ready so you can save a clip to Photos from the menu, a gesture, or a controller button.")
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

                Section("App Icon") {
                    AppIconPicker()
                }

                Section {
                    LabeledContent("RetroAchievements", value: themes.active.label(.comingSoon))
                    LabeledContent("Wi-Fi Link Cable", value: themes.active.label(.comingSoon))
                    LabeledContent("Online Theme Gallery", value: themes.active.label(.comingSoon))
                    LabeledContent("More Systems", value: themes.active.label(.comingSoon))
                } header: {
                    Text("On the Way")
                }

                Section("Controllers & Keyboards") {
                    Text("Xbox, PlayStation and MFi controllers connect automatically. Triggers: left = rewind, right = fast forward. Keyboard: arrows, X = A, Z = B, A/S = L/R, Enter = Start, Shift = Select, Tab = fast forward, O/P = quick save/load, Esc = menu.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    NavigationLink("Legal & Licenses") { LegalView() }
                }
            }
            .navigationTitle(themes.active.label(.settingsTitle))
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
                Text("Emu4ios is not affiliated with, endorsed by, or sponsored by Nintendo. All trademarks belong to their respective owners.")
                Divider()
                Text("Open Source").font(.title3.bold())
                Text("Game Boy, Game Boy Color and Game Boy Advance emulation is powered by mGBA by Vicki Pfau and contributors, licensed under the Mozilla Public License 2.0. The mGBA source code is available at github.com/mgba-emu/mgba.")
                Text("Emu4ios's own source code is available at github.com/fuxkingjosh/Emu4ios.")
            }
            .padding()
        }
        .navigationTitle("Legal")
    }
}
