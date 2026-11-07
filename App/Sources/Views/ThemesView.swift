import SwiftUI
import UniformTypeIdentifiers

struct ThemesView: View {
    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var library: GameLibrary
    @State private var editing: Theme?
    @State private var sharing: Theme?
    @State private var showFileImporter = false
    @State private var showPasteLink = false
    @State private var pastedLink = ""

    var body: some View {
        let style = themes.active.style
        NavigationStack {
            ZStack {
                ThemeBackground(style: themes.active.background)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 18) {
                        ForEach(themes.allThemes) { theme in
                            themeCell(theme, style: style)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(themes.active.label(.themesTitle))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { editing = themes.duplicate(themes.active) } label: {
                            Label("New Theme from Current", systemImage: "plus")
                        }
                        Button { showFileImporter = true } label: { Label("Import Theme File", systemImage: "doc") }
                        Button { showPasteLink = true } label: { Label("Paste Theme Link", systemImage: "link") }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.e4theme, .json]) { result in
                guard case .success(let url) = result else { return }
                router.handle(url, library: library, themes: themes)
            }
            .alert("Paste Theme Link", isPresented: $showPasteLink) {
                TextField("emu4ios://theme?d=…", text: $pastedLink)
                Button("Import") {
                    if let url = URL(string: pastedLink.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        router.handle(url, library: library, themes: themes)
                    }
                    pastedLink = ""
                }
                Button("Cancel", role: .cancel) { pastedLink = "" }
            }
            .sheet(item: $editing) { theme in ThemeEditorView(themeID: theme.id) }
            .sheet(item: $sharing) { theme in ShareThemeSheet(theme: theme) }
        }
    }

    private func themeCell(_ theme: Theme, style: AppStyle) -> some View {
        let isActive = theme.id == themes.activeThemeID
        return VStack(alignment: .leading, spacing: 8) {
            ThemePreviewCard(theme: theme)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(isActive ? style.accent.color : .clear, lineWidth: 3)
                )
                .onTapGesture { themes.activeThemeID = theme.id }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name).font(style.font(.subheadline, weight: .bold)).foregroundStyle(style.primaryText.color)
                    Text(isActive ? "In use" : (theme.isBuiltIn ? "Built-in" : theme.author.isEmpty ? "Yours" : "by \(theme.author)"))
                        .font(style.font(.caption)).foregroundStyle(isActive ? style.accent.color : style.secondaryText.color)
                }
                Spacer()
                Menu {
                    Button { themes.activeThemeID = theme.id } label: { Label("Use Everywhere", systemImage: "checkmark.circle") }
                    Menu("Use Only For…") {
                        ForEach(GameSystem.allCases) { system in
                            Button {
                                themes.systemThemeIDs[system.rawValue] = theme.id
                            } label: {
                                if themes.systemThemeIDs[system.rawValue] == theme.id {
                                    Label(system.name, systemImage: "checkmark")
                                } else {
                                    Text(system.name)
                                }
                            }
                        }
                        Button("Clear System Themes") { themes.systemThemeIDs = [:] }
                    }
                    Button {
                        editing = theme.isBuiltIn ? themes.duplicate(theme) : theme
                    } label: { Label(theme.isBuiltIn ? "Customize a Copy" : "Edit", systemImage: "paintbrush") }
                    Button { sharing = theme } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    Button { themes.duplicate(theme) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    if !theme.isBuiltIn {
                        Button(role: .destructive) { themes.delete(theme) } label: { Label("Delete", systemImage: "trash") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill").font(.title2).foregroundStyle(style.secondaryText.color)
                }
            }
        }
        .padding(10)
        .background(style.surface.color.opacity(0.9), in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
    }
}

struct ShareThemeSheet: View {
    let theme: Theme
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            let link = try? ThemeSharing.link(for: theme)
            ScrollView {
                VStack(spacing: 22) {
                    if let link, let qr = ThemeSharing.qrImage(for: link) {
                        Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                            .frame(maxWidth: 260)
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 18))
                        Text("Friends can scan this with their Camera app to get your theme.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    } else if link != nil {
                        Text("This theme is too detailed for a QR code. Share the link or file instead.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    } else {
                        Text("This theme has a photo background, so it can only be shared as a file.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }

                    if let link {
                        ShareLink(item: link, subject: Text(theme.name), message: Text("Try my Emu4ios theme “\(theme.name)”")) {
                            Label("Share Link", systemImage: "link").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        Button {
                            UIPasteboard.general.url = link
                            copied = true
                        } label: {
                            Label(copied ? "Copied!" : "Copy Link", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).controlSize(.large)
                    }
                    ShareLink(item: ThemeFile(theme: theme), preview: SharePreview(theme.name)) {
                        Label("Share as File", systemImage: "doc.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                }
                .padding()
            }
            .navigationTitle("Share “\(theme.name)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
