import SwiftUI

/// Browse themes other players have shared.
struct GalleryView: View {
    @EnvironmentObject var themes: ThemeStore
    @StateObject private var gallery = GalleryService.shared
    @State private var sort: GallerySort = .popular
    @State private var system: GameSystem?
    @State private var search = ""
    @State private var items: [GalleryTheme] = []
    @State private var next: Int?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var selected: GalleryTheme?

    var body: some View {
        let style = themes.active.style
        ScrollView {
            VStack(spacing: 14) {
                Picker("Sort", selection: $sort) {
                    ForEach(GallerySort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("All", selected: system == nil) { system = nil }
                        ForEach(GameSystem.allCases) { s in chip(s.shortName, selected: system == s) { system = s } }
                    }
                }
                if let errorMessage, items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(style.accent.color)
                        Text(errorMessage).multilineTextAlignment(.center).foregroundStyle(style.secondaryText.color)
                        Button("Try Again") { Task { await reload() } }.buttonStyle(.bordered)
                    }
                    .padding(.top, 40)
                } else if items.isEmpty && !loading {
                    Text("No themes yet — be the first to upload one!")
                        .foregroundStyle(style.secondaryText.color).padding(.top, 40)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 16) {
                    ForEach(items) { item in
                        Button { selected = item } label: { GalleryCard(item: item, style: style) }
                            .buttonStyle(.plain)
                            .onAppear { if item.id == items.last?.id { Task { await loadMore() } } }
                    }
                }
                if loading { ProgressView().padding() }
            }
            .padding()
        }
        .searchable(text: $search, prompt: "Search themes")
        .refreshable { await reload() }
        .task { if items.isEmpty { await reload() } }
        .onChange(of: sort) { _, _ in Task { await reload() } }
        .onChange(of: system) { _, _ in Task { await reload() } }
        .onSubmit(of: .search) { Task { await reload() } }
        .onChange(of: gallery.blockedAuthors) { _, blocked in
            items.removeAll { blocked.contains($0.author.lowercased()) }
        }
        .sheet(item: $selected) { item in
            GalleryDetailView(item: item) { updated in
                if let i = items.firstIndex(where: { $0.id == updated.id }) { items[i] = updated }
            } onRemoved: {
                items.removeAll { $0.id == item.id }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let style = themes.active.style
        return Button(action: action) {
            Text(title)
                .font(style.font(.subheadline, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(selected ? style.background.color : style.primaryText.color)
                .background(selected ? style.accent.color : style.surface.color.opacity(0.9), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func reload() async {
        items = []
        next = 0
        await loadMore()
    }

    private func loadMore() async {
        guard let offset = next, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await gallery.list(sort: sort, system: system, search: search, offset: offset)
            items += page.themes.filter { new in !items.contains { $0.id == new.id } }
            next = page.next
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            next = nil
        }
    }
}

struct GalleryCard: View {
    let item: GalleryTheme
    let style: AppStyle
    @ObservedObject private var gallery = GalleryService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: gallery.previewURL(for: item.id)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 16).fill(style.surface.color)
                        .overlay(ProgressView())
                        .aspectRatio(216.0 / 468.0, contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(item.name).font(style.font(.subheadline, weight: .bold)).foregroundStyle(style.primaryText.color).lineLimit(1)
            HStack(spacing: 10) {
                if !item.author.isEmpty {
                    Text(item.author).lineLimit(1)
                }
                Spacer(minLength: 0)
                Label("\(item.likes)", systemImage: gallery.likedIDs.contains(item.id) ? "heart.fill" : "heart")
                Label("\(item.downloads)", systemImage: "arrow.down.circle")
            }
            .font(style.font(.caption))
            .foregroundStyle(style.secondaryText.color)
            .labelStyle(.titleAndIcon)
        }
        .padding(10)
        .background(style.surface.color.opacity(0.9), in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
    }
}

struct GalleryDetailView: View {
    @State var item: GalleryTheme
    let onUpdate: (GalleryTheme) -> Void
    let onRemoved: () -> Void

    @EnvironmentObject var themes: ThemeStore
    @ObservedObject private var gallery = GalleryService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var message: String?
    @State private var showReport = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    AsyncImage(url: gallery.previewURL(for: item.id)) { image in
                        image.resizable().scaledToFit()
                    } placeholder: { ProgressView().frame(height: 300) }
                    .frame(maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    VStack(spacing: 4) {
                        Text(item.name).font(.title2.bold())
                        if !item.author.isEmpty { Text("by \(item.author)").foregroundStyle(.secondary) }
                        Text("\(item.likes) likes · \(item.downloads) downloads · \(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    Button { install(use: true) } label: {
                        Label("Get & Use Theme", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(working)

                    HStack {
                        Button { install(use: false) } label: { Label("Just Get It", systemImage: "tray.and.arrow.down") }
                        Spacer()
                        Button { like() } label: {
                            Label(gallery.likedIDs.contains(item.id) ? "Liked" : "Like",
                                  systemImage: gallery.likedIDs.contains(item.id) ? "heart.fill" : "heart")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(working)

                    if working { ProgressView() }
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                }
                .padding()
            }
            .navigationTitle("Gallery Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if gallery.uploadedIDs.contains(item.id) {
                            Button("Delete My Upload", role: .destructive) { deleteUpload() }
                        } else {
                            Button { showReport = true } label: { Label("Report Theme", systemImage: "flag") }
                            if !item.author.isEmpty {
                                Button(role: .destructive) {
                                    gallery.block(author: item.author)
                                    onRemoved()
                                    dismiss()
                                } label: { Label("Block \(item.author)", systemImage: "hand.raised") }
                            }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .confirmationDialog("Why are you reporting this theme?", isPresented: $showReport, titleVisibility: .visible) {
                ForEach(["Offensive or hateful", "Sexual content", "Violent or scary", "Spam or broken", "Stolen artwork"], id: \.self) { reason in
                    Button(reason) { report(reason) }
                }
            }
        }
    }

    private func install(use: Bool) {
        working = true
        Task {
            defer { working = false }
            do {
                var theme = try await gallery.download(item.id)
                theme.isBuiltIn = false
                let saved = themes.importTheme(theme)
                if use { themes.activeThemeID = saved.id }
                item.downloads += 1
                onUpdate(item)
                message = use ? "Theme added and turned on ✓" : "Added to your themes ✓"
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func like() {
        Task {
            if let result = try? await gallery.toggleLike(item.id) {
                item.likes = result.likes
                onUpdate(item)
            }
        }
    }

    private func report(_ reason: String) {
        Task {
            do {
                try await gallery.report(item.id, reason: reason)
                message = "Thanks — we'll take a look. Themes with several reports are hidden automatically."
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func deleteUpload() {
        Task {
            do {
                try await gallery.delete(item.id)
                onRemoved()
                dismiss()
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

/// Upload one of your themes, after agreeing to the community rules.
struct UploadThemeSheet: View {
    let theme: Theme
    @ObservedObject private var gallery = GalleryService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var author: String
    @State private var agreed = GalleryService.shared.acceptedRules
    @State private var working = false
    @State private var result: String?

    init(theme: Theme) {
        self.theme = theme
        _author = State(initialValue: theme.author)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ThemePreviewCard(theme: theme).frame(height: 260)
                        Spacer()
                    }
                }
                Section("Shown in the gallery") {
                    LabeledContent("Theme", value: theme.name)
                    TextField("Your name (optional)", text: $author)
                }
                Section {
                    Toggle("I agree to the community rules", isOn: $agreed)
                } footer: {
                    Text("No hateful, sexual, violent or bullying content, and only use pictures you're allowed to share. Themes that break the rules are removed, and repeat uploaders can be blocked. Everyone can see what you upload.")
                }
                Section {
                    Button {
                        upload()
                    } label: {
                        HStack {
                            Text("Upload to Gallery")
                            if working { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(!agreed || working || result != nil)
                    if let result { Text(result).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Share to Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func upload() {
        gallery.acceptedRules = true
        working = true
        var copy = theme
        copy.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { working = false }
            do {
                _ = try await gallery.upload(copy)
                result = "Uploaded! 🎉 Find it under Gallery → New."
            } catch {
                result = error.localizedDescription
            }
        }
    }
}
