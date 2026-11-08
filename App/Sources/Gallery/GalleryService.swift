import SwiftUI

struct GalleryTheme: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let author: String
    let systems: String
    let size: Int
    var likes: Int
    var downloads: Int
    let created_at: Double

    var createdDate: Date { Date(timeIntervalSince1970: created_at / 1000) }
}

enum GallerySort: String, CaseIterable, Identifiable {
    case popular, new
    var id: String { rawValue }
    var title: String { self == .popular ? "Popular" : "New" }
}

enum GalleryError: LocalizedError {
    case notReady, server(String), tooBig
    var errorDescription: String? {
        switch self {
        case .notReady: return "The theme gallery isn't online yet. Check back soon!"
        case .server(let message): return message
        case .tooBig: return "This theme is over 1.8 MB. Use smaller pictures or GIFs and try again."
        }
    }
}

/// Talks to the Emu4ios theme gallery (a Cloudflare Worker).
@MainActor
final class GalleryService: ObservableObject {
    static let shared = GalleryService()

    @Published private(set) var likedIDs: Set<String>
    @Published private(set) var blockedAuthors: Set<String>
    @Published private(set) var uploadedIDs: Set<String>

    /// The Worker writes its address here when it's deployed, so the app never hard-codes it.
    private static let endpointFile = URL(string: "https://raw.githubusercontent.com/fuxkingjosh/Emu4ios/main/gallery/endpoint.txt")!
    private var baseURL: URL?

    let deviceID: String = {
        if let id = UserDefaults.standard.string(forKey: "galleryDeviceID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "galleryDeviceID")
        return id
    }()

    private init() {
        let d = UserDefaults.standard
        likedIDs = Set(d.stringArray(forKey: "galleryLiked") ?? [])
        blockedAuthors = Set(d.stringArray(forKey: "galleryBlocked") ?? [])
        uploadedIDs = Set(d.stringArray(forKey: "galleryUploaded") ?? [])
        if let cached = d.string(forKey: "galleryEndpoint") { baseURL = URL(string: cached) }
    }

    var acceptedRules: Bool {
        get { UserDefaults.standard.bool(forKey: "galleryRulesAccepted") }
        set { UserDefaults.standard.set(newValue, forKey: "galleryRulesAccepted") }
    }

    // MARK: Endpoint

    private func base() async throws -> URL {
        if let fresh = try? await fetchEndpoint() { return fresh }
        if let baseURL { return baseURL }
        throw GalleryError.notReady
    }

    private var lastEndpointCheck: Date = .distantPast

    private func fetchEndpoint() async throws -> URL {
        if let baseURL, Date().timeIntervalSince(lastEndpointCheck) < 600 { return baseURL }
        var request = URLRequest(url: Self.endpointFile)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text), url.scheme == "https" else { throw GalleryError.notReady }
        baseURL = url
        lastEndpointCheck = .now
        UserDefaults.standard.set(text, forKey: "galleryEndpoint")
        return url
    }

    func previewURL(for id: String) -> URL? {
        baseURL?.appendingPathComponent("v1/themes/\(id)/preview")
    }

    // MARK: Requests

    private func send(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: [String: Any]? = nil) async throws -> Data {
        var components = URLComponents(url: try await base().appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 30
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw GalleryError.server(message ?? "The gallery had a problem (\(status)). Try again later.")
        }
        return data
    }

    struct Page: Decodable { let themes: [GalleryTheme]; let next: Int? }

    func list(sort: GallerySort, system: GameSystem?, search: String, offset: Int) async throws -> Page {
        var query = [URLQueryItem(name: "sort", value: sort.rawValue), URLQueryItem(name: "offset", value: "\(offset)")]
        if let system { query.append(URLQueryItem(name: "system", value: system.rawValue)) }
        if !search.isEmpty { query.append(URLQueryItem(name: "q", value: search)) }
        let page = try JSONDecoder().decode(Page.self, from: try await send("v1/themes", query: query))
        return Page(themes: page.themes.filter { !blockedAuthors.contains($0.author.lowercased()) }, next: page.next)
    }

    func download(_ id: String) async throws -> Theme {
        try ThemeSharing.decode(try await send("v1/themes/\(id)"))
    }

    @discardableResult
    func toggleLike(_ id: String) async throws -> (liked: Bool, likes: Int) {
        struct R: Decodable { let liked: Bool; let likes: Int }
        let r = try JSONDecoder().decode(R.self, from: try await send("v1/themes/\(id)/like", method: "POST", body: ["device": deviceID]))
        if r.liked { likedIDs.insert(id) } else { likedIDs.remove(id) }
        UserDefaults.standard.set(Array(likedIDs), forKey: "galleryLiked")
        return (r.liked, r.likes)
    }

    func report(_ id: String, reason: String) async throws {
        _ = try await send("v1/themes/\(id)/report", method: "POST", body: ["device": deviceID, "reason": reason])
    }

    func block(author: String) {
        blockedAuthors.insert(author.lowercased())
        UserDefaults.standard.set(Array(blockedAuthors), forKey: "galleryBlocked")
    }

    func unblockAll() {
        blockedAuthors.removeAll()
        UserDefaults.standard.set([String](), forKey: "galleryBlocked")
    }

    func delete(_ id: String) async throws {
        _ = try await send("v1/themes/\(id)", method: "DELETE", body: ["device": deviceID])
        uploadedIDs.remove(id)
        UserDefaults.standard.set(Array(uploadedIDs), forKey: "galleryUploaded")
    }

    func myUploads() async throws -> [GalleryTheme] {
        struct R: Decodable { let themes: [GalleryTheme] }
        return try JSONDecoder().decode(R.self, from: try await send("v1/themes/mine", query: [URLQueryItem(name: "device", value: deviceID)])).themes
    }

    /// Uploads a theme with a picture of it. Returns the new gallery ID.
    func upload(_ theme: Theme) async throws -> String {
        var shareable = theme
        shareable.isBuiltIn = false
        let json = try ThemeSharing.encode(shareable)
        guard json.count < 1_800_000 else { throw GalleryError.tooBig }
        guard let object = try JSONSerialization.jsonObject(with: json) as? [String: Any] else { throw GalleryError.server("Couldn't prepare the theme") }
        var body: [String: Any] = ["theme": object, "device": deviceID, "systems": Array(theme.controllers.keys)]
        if let preview = Self.renderPreview(theme) { body["preview"] = preview.base64EncodedString() }
        struct R: Decodable { let id: String }
        let r = try JSONDecoder().decode(R.self, from: try await send("v1/themes", method: "POST", body: body))
        uploadedIDs.insert(r.id)
        UserDefaults.standard.set(Array(uploadedIDs), forKey: "galleryUploaded")
        return r.id
    }

    static func renderPreview(_ theme: Theme) -> Data? {
        let renderer = ImageRenderer(content: ThemePreviewCard(theme: theme).frame(width: 216, height: 468))
        renderer.scale = 1
        return renderer.uiImage?.pngData()
    }
}
