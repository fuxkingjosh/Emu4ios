import SwiftUI

/// Ready-made cheats from the free libretro cheat database (about 22,000 games).
/// A list of which games have cheats ships with the app; the codes are downloaded when you open one.
enum CheatLibrary {
    struct Entry: Identifiable, Hashable {
        let name: String
        let code: String
        var id: String { name + code }
    }

    private static let databaseCommit = "c4e17d41ec1bb744fb064f7cefeb61b878fc5d64"

    private static let index: [String: [String]] = {
        guard let url = Bundle.main.url(forResource: "cheat-index", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return index
    }()

    private static func folders(for system: GameSystem) -> [String] {
        switch system {
        case .nes: return ["Nintendo - Nintendo Entertainment System", "Nintendo - Family Computer Disk System"]
        case .doom: return ["PrBoom"]
        default: return [system.thumbnailDatabase]
        }
    }

    /// "Pokemon - Emerald Version (USA, Europe) (Code Breaker)" → "pokemonemeraldversion"
    static func normalize(_ name: String) -> String {
        var s = name.lowercased()
        while let r = s.range(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, options: .regularExpression) { s.removeSubrange(r) }
        s = s.replacingOccurrences(of: "&", with: "and")
        return String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// Cheat files that look like they belong to this game, best match first.
    static func files(for game: Game) -> [(folder: String, file: String)] {
        let wanted = Set([game.title, game.databaseName ?? "", (game.fileName as NSString).deletingPathExtension]
            .map(normalize).filter { !$0.isEmpty })
        let exact = game.databaseName.map { $0.lowercased() }
        var results: [(String, String)] = []
        for folder in folders(for: game.system) {
            for file in index[folder] ?? [] where wanted.contains(normalize(file)) {
                results.append((folder, file))
            }
        }
        // Prefer the exact dump, then USA releases.
        return results.sorted { a, b in
            func rank(_ name: String) -> Int {
                if let exact, name.lowercased().hasPrefix(exact) { return 0 }
                if name.contains("USA") { return 1 }
                if name.contains("Europe") || name.contains("World") { return 2 }
                return 3
            }
            return rank(a.1) == rank(b.1) ? a.1 < b.1 : rank(a.1) < rank(b.1)
        }
    }

    static func download(folder: String, file: String) async throws -> [Entry] {
        let path = "cht/\(folder)/\(file).cht"
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return [] }
        let sources = ["https://raw.githubusercontent.com/libretro/libretro-database/\(databaseCommit)/\(encoded)",
                       "https://cdn.jsdelivr.net/gh/libretro/libretro-database@\(databaseCommit)/\(encoded)"]
        var lastError: Error = URLError(.badServerResponse)
        for source in sources {
            guard let url = URL(string: source) else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                return parse(String(decoding: data, as: UTF8.self))
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Reads the libretro .cht format (cheatN_desc / cheatN_code).
    static func parse(_ text: String) -> [Entry] {
        var descs: [Int: String] = [:], codes: [Int: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 { value = String(value.dropFirst().dropLast()) }
            guard key.hasPrefix("cheat"), let us = key.firstIndex(of: "_"),
                  let n = Int(key[key.index(key.startIndex, offsetBy: 5)..<us]) else { continue }
            let field = key[key.index(after: us)...]
            if field == "desc" { descs[n] = value }
            if field == "code" { codes[n] = value }
        }
        return codes.keys.sorted().compactMap { n in
            guard let code = codes[n], !code.isEmpty else { return nil }
            return Entry(name: descs[n] ?? "Cheat \(n + 1)", code: code)
        }
    }

    /// Converts a database code to the line format each emulator expects.
    static func format(_ code: String, for system: GameSystem) -> String {
        let parts = code.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard system == .gba else { return parts.joined(separator: "\n") }
        // GBA codes come as address/value halves: pair them up into lines.
        var lines: [String] = []
        var i = 0
        while i < parts.count {
            let isHex = parts[i].count == 8 && parts[i].allSatisfy(\.isHexDigit)
            if isHex, i + 1 < parts.count, parts[i + 1].allSatisfy(\.isHexDigit), [4, 8].contains(parts[i + 1].count) {
                lines.append(parts[i] + " " + parts[i + 1])
                i += 2
            } else {
                lines.append(parts[i])
                i += 1
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// Browse and add cheats from the database.
struct CheatLibraryView: View {
    let game: Game
    let onAdd: (String, String) -> Void
    @State private var files: [(folder: String, file: String)] = []
    @State private var selected: String?
    @State private var entries: [CheatLibrary.Entry] = []
    @State private var loading = false
    @State private var error: String?
    @State private var added: Set<String> = []
    @State private var search = ""

    var body: some View {
        List {
            if files.isEmpty {
                Text("No cheats in the database for this game. You can still type codes in yourself.")
                    .foregroundStyle(.secondary)
            } else if files.count > 1 {
                Section("Version") {
                    Picker("Cheat file", selection: Binding(get: { selected ?? files[0].file }, set: { load($0) })) {
                        ForEach(files, id: \.file) { Text($0.file).tag($0.file) }
                    }
                    .pickerStyle(.menu)
                }
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            ForEach(filtered) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                        Text(entry.code.replacingOccurrences(of: "+", with: " ")).font(.caption.monospaced())
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button {
                        onAdd(entry.name, CheatLibrary.format(entry.code, for: game.system))
                        added.insert(entry.id)
                    } label: {
                        Image(systemName: added.contains(entry.id) ? "checkmark.circle.fill" : "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(added.contains(entry.id))
                }
            }
        }
        .searchable(text: $search, prompt: "Search cheats")
        .navigationTitle("Cheat Library")
        .onAppear {
            guard files.isEmpty else { return }
            files = CheatLibrary.files(for: game)
            if let first = files.first { load(first.file) }
        }
    }

    private var filtered: [CheatLibrary.Entry] {
        search.isEmpty ? entries : entries.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private func load(_ file: String) {
        guard let match = files.first(where: { $0.file == file }) else { return }
        selected = file
        loading = true
        error = nil
        Task {
            do {
                entries = try await CheatLibrary.download(folder: match.folder, file: match.file)
            } catch {
                self.error = "Couldn't download cheats. Check your connection."
                entries = []
            }
            loading = false
        }
    }
}
