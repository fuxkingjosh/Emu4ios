import SwiftUI

/// Download games from a WebDAV server (NAS boxes, Nextcloud, many routers).
/// SMB shares and cloud drives work through "Import Games" → Files instead.
struct WebDAVClient {
    struct Item: Identifiable, Hashable {
        let url: URL
        let name: String
        let isFolder: Bool
        let size: Int64
        var id: URL { url }
    }

    var baseURL: URL
    var user: String
    var password: String

    private var authHeader: String? {
        guard !user.isEmpty else { return nil }
        return "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
    }

    func list(_ folder: URL) async throws -> [Item] {
        var request = URLRequest(url: folder, timeoutInterval: 30)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        if let authHeader { request.setValue(authHeader, forHTTPHeaderField: "Authorization") }
        request.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/></d:prop></d:propfind>
        """.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 207 || status == 200 else {
            throw URLError(status == 401 ? .userAuthenticationRequired : .badServerResponse)
        }
        let parser = PropfindParser(base: folder)
        return parser.parse(data).filter { $0.url.standardized.path != folder.standardized.path }
            .sorted { ($0.isFolder ? 0 : 1, $0.name.lowercased()) < ($1.isFolder ? 0 : 1, $1.name.lowercased()) }
    }

    func download(_ item: Item, to destination: URL) async throws {
        var request = URLRequest(url: item.url, timeoutInterval: 600)
        if let authHeader { request.setValue(authHeader, forHTTPHeaderField: "Authorization") }
        let (temp, response) = try await URLSession.shared.download(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
    }
}

/// Reads a WebDAV multistatus response.
private final class PropfindParser: NSObject, XMLParserDelegate {
    private let base: URL
    private var items: [WebDAVClient.Item] = []
    private var href = "", length = "", isCollection = false
    private var text = ""

    init(base: URL) { self.base = base }

    func parse(_ data: Data) -> [WebDAVClient.Item] {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        if name == "response" { href = ""; length = ""; isCollection = false }
        if name == "collection" { isCollection = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "href": href = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "getcontentlength": length = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "response":
            guard let url = URL(string: href, relativeTo: base)?.absoluteURL else { return }
            let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
            guard !name.isEmpty else { return }
            items.append(.init(url: url, name: name, isFolder: isCollection, size: Int64(length) ?? 0))
        default: break
        }
    }
}

struct WebDAVBrowserView: View {
    @EnvironmentObject var library: GameLibrary
    @Environment(\.dismiss) private var dismiss
    @AppStorage("webdavURL") private var address = ""
    @AppStorage("webdavUser") private var user = ""
    @State private var password = ""
    @State private var path: [URL] = []
    @State private var items: [WebDAVClient.Item] = []
    @State private var loading = false
    @State private var downloading: Set<URL> = []
    @State private var error: String?

    private var client: WebDAVClient? {
        var text = address.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty, !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text) else { return nil }
        return WebDAVClient(baseURL: url, user: user, password: password)
    }

    var body: some View {
        NavigationStack {
            List {
                if path.isEmpty {
                    Section {
                        TextField("Server address (https://…)", text: $address)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Username", text: $user).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Password", text: $password)
                        Button("Connect") { open(nil) }.disabled(client == nil || loading)
                    } footer: {
                        Text("Works with WebDAV servers such as Nextcloud, Synology and QNAP. For SMB shares, use Import Games → Files → Connect to Server.")
                    }
                } else {
                    Section {
                        Button(action: goBack) {
                            Label("Back", systemImage: "chevron.left")
                        }
                    }
                    Section(path.last?.lastPathComponent.removingPercentEncoding ?? "") {
                        ForEach(items) { item in row(item) }
                    }
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("WebDAV Server")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear { password = Keychain.read("webdavPassword") ?? "" }
        }
    }

    @ViewBuilder
    private func row(_ item: WebDAVClient.Item) -> some View {
        if item.isFolder {
            Button { open(item.url) } label: { Label(item.name, systemImage: "folder") }
        } else {
            let ext = (item.name as NSString).pathExtension.lowercased()
            let playable = GameSystem.allExtensions.contains(ext) || GameSystem.companionExtensions.contains(ext)
            HStack {
                Label(item.name, systemImage: playable ? "gamecontroller" : "doc")
                Spacer()
                if downloading.contains(item.url) {
                    ProgressView()
                } else if playable {
                    Button { download(item) } label: { Image(systemName: "arrow.down.circle") }.buttonStyle(.borderless)
                }
            }
            .foregroundStyle(playable ? .primary : .secondary)
        }
    }

    private func goBack() {
        path.removeLast()
        if let previous = path.popLast() { open(previous) } else { items = [] }
    }

    private func open(_ url: URL?) {
        guard let client else { return }
        let target = url ?? client.baseURL
        Keychain.write("webdavPassword", password)
        loading = true
        error = nil
        Task {
            do {
                items = try await client.list(target)
                path.append(target)
            } catch {
                self.error = (error as? URLError)?.code == .userAuthenticationRequired
                    ? "Wrong username or password." : "Couldn't open that folder: \(error.localizedDescription)"
            }
            loading = false
        }
    }

    private func download(_ item: WebDAVClient.Item) {
        guard let client else { return }
        downloading.insert(item.url)
        Task {
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(item.name)
            do {
                try await client.download(item, to: temp)
                // Disc games: bring the track files listed in a .cue along with it.
                var files = [temp]
                if (item.name as NSString).pathExtension.lowercased() == "cue" {
                    for track in GameLibrary.cueReferencedFiles(in: [temp]) {
                        if let match = items.first(where: { $0.name == track }) {
                            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(track)
                            try await client.download(match, to: dest)
                            files.append(dest)
                        }
                    }
                }
                library.importFiles(files)
                files.forEach { try? FileManager.default.removeItem(at: $0) }
            } catch {
                self.error = "Download failed: \(error.localizedDescription)"
            }
            downloading.remove(item.url)
        }
    }
}
