import SwiftUI
import PhotosUI

/// Edits every part of a theme. Changes save live, so the rest of the app updates as you go.
struct ThemeEditorView: View {
    let themeID: String
    @EnvironmentObject var themes: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Theme?
    @State private var backgroundItem: PhotosPickerItem?
    @State private var layoutSystem: GameSystem?
    @State private var previewSystem: GameSystem = .gba

    var body: some View {
        NavigationStack {
            Group {
                if draft != nil {
                    form
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Edit Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { commit(); dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Use") { commit(); if let d = draft { themes.activeThemeID = d.id } }
                }
            }
            .onAppear { if draft == nil { draft = themes.theme(id: themeID) } }
            .onChange(of: draft) { _, _ in commit() }
            .fullScreenCover(item: $layoutSystem) { system in
                if let d = draft { LayoutEditorView(theme: d, system: system) }
            }
            .onChange(of: layoutSystem) { _, value in
                if value == nil { draft = themes.theme(id: themeID) } // pick up layout edits
            }
        }
    }

    private func commit() {
        guard let d = draft, !d.isBuiltIn else { return }
        themes.save(d)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Theme, T>) -> Binding<T> {
        Binding(get: { draft![keyPath: keyPath] }, set: { draft![keyPath: keyPath] = $0 })
    }

    private func colorBinding(_ keyPath: WritableKeyPath<Theme, ThemeColor>) -> Binding<Color> {
        Binding(get: { draft![keyPath: keyPath].color }, set: { draft![keyPath: keyPath] = ThemeColor($0) })
    }

    private var form: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    ThemePreviewCard(theme: draft!, system: previewSystem).frame(height: 300)
                    Spacer()
                }
                Picker("Preview", selection: $previewSystem) {
                    ForEach(GameSystem.allCases) { Text($0.shortName).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Name") {
                TextField("Theme name", text: binding(\.name))
                TextField("Your name (shown when shared)", text: binding(\.author))
            }

            Section {
                ForEach(GameSystem.allCases) { system in
                    Button {
                        if draft!.controllers[system.rawValue] == nil {
                            draft!.controllers[system.rawValue] = draft!.controller(for: system)
                            commit()
                        }
                        layoutSystem = system
                    } label: {
                        Label("\(system.name) Controller", systemImage: "gamecontroller")
                    }
                }
            } header: {
                Text("Controller Layouts")
            } footer: {
                Text("Move, resize and restyle every button, separately for portrait and landscape.")
            }

            appSection
            backgroundSection
            screenSection
            labelsSection
        }
    }

    private var appSection: some View {
        Section("App Look") {
            ColorPicker("Accent", selection: colorBinding(\.style.accent))
            ColorPicker("Background", selection: colorBinding(\.style.background))
            ColorPicker("Cards", selection: colorBinding(\.style.surface))
            ColorPicker("Text", selection: colorBinding(\.style.primaryText))
            ColorPicker("Secondary Text", selection: colorBinding(\.style.secondaryText))
            Toggle("Dark Mode", isOn: binding(\.style.darkMode))
            Picker("Font Style", selection: binding(\.style.fontDesign)) {
                ForEach(ThemeFontDesign.allCases) { Text($0.rawValue.capitalized).tag($0) }
            }
            Picker("Font", selection: Binding(get: { draft!.style.fontName ?? "" },
                                              set: { draft!.style.fontName = $0.isEmpty ? nil : $0 })) {
                Text("System").tag("")
                ForEach(FontCatalog.families, id: \.self) { family in
                    Text(family).font(.custom(family, size: 16)).tag(family)
                }
            }
            VStack(alignment: .leading) {
                Text("Text Size \(Int(draft!.style.fontScale * 100))%")
                Slider(value: binding(\.style.fontScale), in: 0.8...1.4, step: 0.05)
            }
            VStack(alignment: .leading) {
                Text("Corner Roundness \(Int(draft!.style.cornerRadius))")
                Slider(value: binding(\.style.cornerRadius), in: 0...32, step: 1)
            }
            Picker("Library Layout", selection: binding(\.style.libraryLayout)) {
                ForEach(LibraryLayout.allCases) { Text($0.rawValue.capitalized).tag($0) }
            }
        }
    }

    private var backgroundSection: some View {
        Section("Background") {
            Picker("Style", selection: binding(\.background.kind)) {
                ForEach(BackgroundKind.allCases) { Text($0.displayName).tag($0) }
            }
            ForEach(Array(draft!.background.colors.indices), id: \.self) { i in
                ColorPicker("Color \(i + 1)", selection: Binding(
                    get: { draft!.background.colors[i].color },
                    set: { draft!.background.colors[i] = ThemeColor($0) }))
            }
            HStack {
                Button("Add Color") { draft!.background.colors.append(ThemeColor(hex: "#444466")) }
                    .disabled(draft!.background.colors.count >= 5)
                Spacer()
                Button("Remove", role: .destructive) { _ = draft!.background.colors.popLast() }
                    .disabled(draft!.background.colors.count <= 1)
            }
            .buttonStyle(.borderless)
            if draft!.background.kind.isAnimated {
                VStack(alignment: .leading) {
                    Text("Speed")
                    Slider(value: binding(\.background.speed), in: 0.1...3)
                }
                VStack(alignment: .leading) {
                    Text("Amount")
                    Slider(value: binding(\.background.density), in: 0...1)
                }
            }
            if draft!.background.kind == .image {
                PhotosPicker(selection: $backgroundItem, matching: .any(of: [.images, .livePhotos])) { Label("Choose Photo or GIF", systemImage: "photo") }
                VStack(alignment: .leading) {
                    Text("Darken")
                    Slider(value: binding(\.background.imageDim), in: 0...0.8)
                }
            }
            Toggle("Show Behind Game", isOn: binding(\.background.showInGame))
        }
        .onChange(of: backgroundItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self), UIImage(data: data) != nil else { return }
                draft?.background.imageData = AnimatedImage.isAnimated(data)
                    ? data
                    : (UIImage(data: data)?.resizedForTheme().jpegData(compressionQuality: 0.75) ?? data)
                draft?.background.kind = .image
            }
        }
    }

    private var screenSection: some View {
        Section("Game Screen") {
            Picker("Filter", selection: binding(\.screen.filter)) {
                ForEach(ScreenFilter.allCases) { Text($0.displayName).tag($0) }
            }
            VStack(alignment: .leading) {
                Text("Filter Strength")
                Slider(value: binding(\.screen.intensity), in: 0...1)
            }
            ColorPicker("Border", selection: colorBinding(\.screen.borderColor))
            VStack(alignment: .leading) {
                Text("Border Width \(Int(draft!.screen.borderWidth))")
                Slider(value: binding(\.screen.borderWidth), in: 0...20, step: 1)
            }
            VStack(alignment: .leading) {
                Text("Rounded Corners \(Int(draft!.screen.cornerRadius))")
                Slider(value: binding(\.screen.cornerRadius), in: 0...30, step: 1)
            }
            VStack(alignment: .leading) {
                Text("Glow")
                Slider(value: binding(\.screen.glow), in: 0...1)
            }
            Toggle("Pixel-Perfect Scaling", isOn: binding(\.screen.integerScaling))
        }
    }

    private var labelsSection: some View {
        Section {
            ForEach(LabelKey.allCases) { key in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(key.whereShown) · \(key.defaultText)").font(.caption).foregroundStyle(.secondary)
                    TextField(key.defaultText, text: Binding(
                        get: { draft!.style.labels[key.rawValue] ?? "" },
                        set: { draft!.style.labels[key.rawValue] = $0.isEmpty ? nil : $0 }))
                }
            }
            Button("Reset All Text", role: .destructive) { draft!.style.labels = [:] }
        } header: {
            Text("Text & Labels")
        } footer: {
            Text("Rename anything in the app. Leave a box empty to keep the default.")
        }
    }
}

enum FontCatalog {
    /// A curated list of fonts that ship with iOS and look good in a game app.
    static let families: [String] = [
        "Avenir Next", "Chalkboard SE", "Courier New", "Futura", "Georgia", "Gill Sans", "Marker Felt",
        "Menlo", "Noteworthy", "Optima", "Papyrus", "Rockwell", "Snell Roundhand", "Trebuchet MS", "Verdana",
        "American Typewriter", "Baskerville", "Copperplate", "Didot", "Party LET",
    ].filter { !UIFont.fontNames(forFamilyName: $0).isEmpty }
}

extension UIImage {
    /// Keeps photo backgrounds small enough to share.
    func resizedForTheme(maxSide: CGFloat = 1_200) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return self }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}

