import SwiftUI
import Security

/// RetroAchievements: sign in, earn achievements in any supported game, hardcore mode.
/// Free for everyone — just needs a free retroachievements.org account.
@MainActor
final class Achievements: ObservableObject {
    static let shared = Achievements()

    struct Popup: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var detail: String
        var badgeURL: URL?
        var points: UInt32
        var kind: Kind
        enum Kind { case unlocked, progress, leaderboard, mastered, info }
    }

    struct Item: Identifiable {
        let id: UInt32
        let title: String
        let detail: String
        let badgeURL: URL?
        let points: UInt32
        let unlocked: Bool
        let progress: String
        let percent: Float
    }

    @Published private(set) var userName: String?
    @Published private(set) var score: UInt32 = 0
    @Published private(set) var loggingIn = false
    @Published var loginError: String?
    @Published private(set) var gameTitle: String?
    @Published private(set) var gameStatus: String?
    @Published private(set) var popups: [Popup] = []
    /// Live leaderboard value (e.g. a timer) shown while an attempt is running.
    @Published private(set) var tracker: String?
    @Published var hardcore: Bool {
        didSet {
            UserDefaults.standard.set(hardcore, forKey: "raHardcore")
            e4ra_set_hardcore(hardcore)
        }
    }
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "raEnabled") }
    }

    /// Set while a game runs; the session reacts to "reset" requests from hardcore mode.
    var onResetRequested: (() -> Void)?

    private var setUp = false
    private var userAgent = "Emu4ios/1.0"

    private init() {
        hardcore = UserDefaults.standard.bool(forKey: "raHardcore")
        enabled = UserDefaults.standard.object(forKey: "raEnabled") as? Bool ?? true
    }

    var isLoggedIn: Bool { userName != nil }
    /// Hardcore applies only while a game with achievements is loaded.
    var hardcoreActive: Bool { hardcore && isLoggedIn && gameTitle != nil }

    // MARK: Setup

    func start() {
        guard !setUp else { return }
        setUp = true
        e4ra_setup({ id, url, post, type in
            let request = (id, url.map { String(cString: $0) } ?? "", post.map { String(cString: $0) }, type.map { String(cString: $0) })
            Task { @MainActor in Achievements.shared.perform(request.0, url: request.1, post: request.2, contentType: request.3) }
        }, { type, id, title, detail, badge, points in
            let t = title.map { String(cString: $0) } ?? "", d = detail.map { String(cString: $0) } ?? ""
            let b = badge.map { String(cString: $0) } ?? ""
            Task { @MainActor in Achievements.shared.handleEvent(type, id: id, title: t, detail: d, badge: b, points: points) }
        }, { kind, result, message in
            let m = message.map { String(cString: $0) } ?? ""
            Task { @MainActor in Achievements.shared.finished(kind, result: result, message: m) }
        }, "Emu4ios")
        e4ra_set_hardcore(hardcore)
        var clause = [CChar](repeating: 0, count: 64)
        e4ra_user_agent(&clause, clause.count)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        userAgent = "Emu4ios/\(version) (iOS) \(String(cString: clause))"
        if let user = UserDefaults.standard.string(forKey: "raUser"), let token = Keychain.read("raToken") {
            loggingIn = true
            e4ra_login_token(user, token)
        }
    }

    // MARK: Account

    func login(user: String, password: String) {
        start()
        loginError = nil
        loggingIn = true
        e4ra_login_password(user, password)
    }

    func logout() {
        e4ra_logout()
        Keychain.delete("raToken")
        UserDefaults.standard.removeObject(forKey: "raUser")
        userName = nil
        score = 0
    }

    // MARK: Games

    /// Called by the play session once the emulator is running.
    func gameStarted(core: EmulatorCore, romURL: URL) {
        gameTitle = nil
        gameStatus = nil
        tracker = nil
        guard enabled, isLoggedIn else { return }
        let consoleID = e4ra_console_id(core.system.rawValue)
        guard consoleID != 0 else { return }
        gameStatus = "Checking for achievements…"
        core.loadAchievements(consoleID: consoleID, path: romURL.path)
    }

    func gameEnded() {
        e4ra_unload_game()
        gameTitle = nil
        gameStatus = nil
        tracker = nil
        popups.removeAll()
        onResetRequested = nil
    }

    func list() -> [Item] {
        let count = e4ra_achievement_count()
        var items: [Item] = []
        var raw = E4RAAchievement()
        for i in 0..<count where e4ra_achievement_at(i, &raw) {
            items.append(Item(id: raw.id, title: Self.string(&raw.title), detail: Self.string(&raw.description),
                              badgeURL: URL(string: Self.string(&raw.badgeURL)), points: raw.points, unlocked: raw.unlocked,
                              progress: Self.string(&raw.progress), percent: raw.progressPercent))
        }
        return items
    }

    func summary() -> (unlocked: UInt32, total: UInt32, points: UInt32, totalPoints: UInt32) {
        var a: UInt32 = 0, b: UInt32 = 0, c: UInt32 = 0, d: UInt32 = 0
        e4ra_summary(&a, &b, &c, &d)
        return (a, b, c, d)
    }

    func dismiss(_ popup: Popup) { popups.removeAll { $0.id == popup.id } }

    // MARK: Callbacks from rc_client

    private func perform(_ id: Int32, url: String, post: String?, contentType: String?) {
        guard let target = URL(string: url) else { e4ra_http_response(id, 0, nil, 0); return }
        var request = URLRequest(url: target, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let post {
            request.httpMethod = "POST"
            request.httpBody = Data(post.utf8)
            request.setValue(contentType ?? "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = Int32((response as? HTTPURLResponse)?.statusCode ?? 0)
            let body = data ?? Data()
            Task { @MainActor in
                // rc_client wants a C string; add a terminator.
                var bytes = [CChar](repeating: 0, count: body.count + 1)
                body.withUnsafeBytes { src in bytes.withUnsafeMutableBytes { dst in dst.copyMemory(from: src) } }
                e4ra_http_response(id, status, bytes, body.count)
            }
        }.resume()
    }

    private func finished(_ kind: Int32, result: Int32, message: String) {
        if kind == 0 {
            loggingIn = false
            if result == 0 {
                var name = [CChar](repeating: 0, count: 128), token = [CChar](repeating: 0, count: 128)
                var points: UInt32 = 0
                e4ra_user(&name, name.count, &token, token.count, &points)
                userName = String(cString: name)
                score = points
                UserDefaults.standard.set(userName, forKey: "raUser")
                Keychain.write("raToken", String(cString: token))
            } else {
                loginError = message.isEmpty ? "Couldn't sign in." : message
                if message.lowercased().contains("token") { logout() }
            }
        } else {
            if result == 0, e4ra_game_loaded() {
                var title = [CChar](repeating: 0, count: 256)
                e4ra_game_title(&title, title.count)
                gameTitle = String(cString: title)
                let s = summary()
                gameStatus = s.total == 0 ? "No achievements for this game yet"
                    : "\(s.unlocked) of \(s.total) achievements unlocked"
                var badge = [CChar](repeating: 0, count: 256)
                e4ra_game_badge_url(&badge, badge.count)
                if s.total > 0 {
                    show(Popup(title: gameTitle ?? "", detail: (hardcore ? "Hardcore · " : "") + (gameStatus ?? ""),
                               badgeURL: URL(string: String(cString: badge)), points: 0, kind: .info))
                }
            } else {
                gameStatus = result == -16 || message.contains("not found") || message.contains("Unknown")
                    ? "This version of the game isn't recognized by RetroAchievements" : message
            }
        }
    }

    private func handleEvent(_ type: Int32, id: UInt32, title: String, detail: String, badge: String, points: UInt32) {
        switch Int(type) {
        case Int(E4RAEventUnlocked):
            show(Popup(title: title, detail: detail, badgeURL: URL(string: badge), points: points, kind: .unlocked))
            PlayStats.shared.log(.achievement)
            score += points
            let s = summary()
            gameStatus = "\(s.unlocked) of \(s.total) achievements unlocked"
        case Int(E4RAEventProgressShow), Int(E4RAEventProgressUpdate):
            if let i = popups.firstIndex(where: { $0.kind == .progress }) {
                popups[i].detail = detail
            } else {
                show(Popup(title: title, detail: detail, badgeURL: URL(string: badge), points: 0, kind: .progress), duration: 2)
            }
        case Int(E4RAEventLeaderboardStarted):
            show(Popup(title: "Leaderboard started", detail: title, badgeURL: nil, points: 0, kind: .leaderboard), duration: 2.5)
        case Int(E4RAEventLeaderboardFailed):
            show(Popup(title: "Leaderboard failed", detail: title, badgeURL: nil, points: 0, kind: .leaderboard), duration: 2.5)
        case Int(E4RAEventLeaderboardSubmitted):
            show(Popup(title: "Leaderboard submitted", detail: "\(title) · \(detail)", badgeURL: nil, points: 0, kind: .leaderboard))
        case Int(E4RAEventTrackerShow), Int(E4RAEventTrackerUpdate):
            tracker = detail
        case Int(E4RAEventTrackerHide):
            tracker = nil
        case Int(E4RAEventGameCompleted):
            show(Popup(title: hardcore ? "Mastered!" : "Completed!", detail: title, badgeURL: URL(string: badge), points: 0, kind: .mastered), duration: 6)
        case Int(E4RAEventReset):
            onResetRequested?()
        case Int(E4RAEventDisconnected):
            show(Popup(title: "Offline", detail: "Unlocks will be sent when you're back online", badgeURL: nil, points: 0, kind: .info))
        case Int(E4RAEventServerError):
            show(Popup(title: title, detail: detail, badgeURL: nil, points: 0, kind: .info))
        default:
            break
        }
    }

    private func show(_ popup: Popup, duration: Double = 4) {
        popups.append(popup)
        if popup.kind == .unlocked || popup.kind == .mastered {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        let id = popup.id
        Task {
            try? await Task.sleep(for: .seconds(duration))
            popups.removeAll { $0.id == id }
        }
    }

    private static func string<T>(_ tuple: inout T) -> String {
        withUnsafeBytes(of: &tuple) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// Tiny Keychain wrapper for the RetroAchievements login token.
enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.fuxkingjosh.emu4ios", kSecAttrAccount as String: key]
    }

    static func write(_ key: String, _ value: String) {
        delete(key)
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) { SecItemDelete(query(key) as CFDictionary) }
}

// MARK: - Views

/// Achievement pop-ups shown over the game.
struct AchievementPopups: View {
    @ObservedObject var achievements = Achievements.shared

    var body: some View {
        VStack(spacing: 8) {
            ForEach(achievements.popups) { popup in
                HStack(spacing: 12) {
                    badge(popup)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(header(popup)).font(.caption2.weight(.heavy)).foregroundStyle(.yellow)
                        Text(popup.title).font(.subheadline.bold()).lineLimit(1)
                        if !popup.detail.isEmpty {
                            Text(popup.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    if popup.points > 0 {
                        Text("\(popup.points)").font(.caption.bold()).padding(6).background(.yellow.opacity(0.25), in: Capsule())
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.yellow.opacity(popup.kind == .unlocked ? 0.6 : 0), lineWidth: 1.5))
                .onTapGesture { achievements.dismiss(popup) }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let tracker = achievements.tracker {
                Label(tracker, systemImage: "timer").font(.caption.monospacedDigit().bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 420)
        .animation(.spring(duration: 0.35), value: achievements.popups)
        .allowsHitTesting(!achievements.popups.isEmpty)
    }

    private func header(_ p: Achievements.Popup) -> String {
        switch p.kind {
        case .unlocked: return "ACHIEVEMENT UNLOCKED"
        case .progress: return "PROGRESS"
        case .leaderboard: return "LEADERBOARD"
        case .mastered: return "GAME COMPLETE"
        case .info: return "RETROACHIEVEMENTS"
        }
    }

    @ViewBuilder
    private func badge(_ p: Achievements.Popup) -> some View {
        AsyncImage(url: p.badgeURL) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Image(systemName: "trophy.fill").foregroundStyle(.yellow)
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The game's achievements, from the pause menu.
struct AchievementListView: View {
    @ObservedObject var achievements = Achievements.shared
    @State private var items: [Achievements.Item] = []

    var body: some View {
        List {
            if let title = achievements.gameTitle {
                let s = achievements.summary()
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.headline)
                        ProgressView(value: Double(s.unlocked), total: Double(max(s.total, 1)))
                        Text("\(s.unlocked) of \(s.total) unlocked · \(s.points) of \(s.totalPoints) points")
                            .font(.caption).foregroundStyle(.secondary)
                        if achievements.hardcoreActive {
                            Label("Hardcore mode", systemImage: "flame.fill").font(.caption.bold()).foregroundStyle(.orange)
                        }
                    }
                }
                Section {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            AsyncImage(url: item.badgeURL) { $0.resizable().scaledToFit() } placeholder: { Color.gray.opacity(0.2) }
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .grayscale(item.unlocked ? 0 : 1)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.subheadline.bold())
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                if !item.unlocked && !item.progress.isEmpty {
                                    ProgressView(value: Double(item.percent), total: 100)
                                    Text(item.progress).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(item.points)").font(.caption.bold()).foregroundStyle(item.unlocked ? .yellow : .secondary)
                        }
                    }
                }
            } else {
                Section {
                    Text(achievements.gameStatus ?? (achievements.isLoggedIn ? "No achievements loaded for this game."
                                                     : "Sign in to RetroAchievements in Settings to earn achievements."))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Achievements")
        .onAppear { items = achievements.list() }
    }
}

/// Settings → RetroAchievements.
struct AchievementSettingsView: View {
    @ObservedObject var achievements = Achievements.shared
    @State private var user = ""
    @State private var password = ""

    var body: some View {
        Form {
            if let name = achievements.userName {
                Section {
                    LabeledContent("Signed in as", value: name)
                    LabeledContent("Points", value: "\(achievements.score)")
                    Button("Sign Out", role: .destructive) { achievements.logout() }
                }
            } else {
                Section {
                    TextField("Username", text: $user)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password).textContentType(.password)
                    Button {
                        achievements.login(user: user, password: password)
                        password = ""
                    } label: {
                        if achievements.loggingIn { ProgressView() } else { Text("Sign In") }
                    }
                    .disabled(user.isEmpty || password.isEmpty || achievements.loggingIn)
                    if let error = achievements.loginError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Use your free retroachievements.org account. Your password is only sent to RetroAchievements; Emu4ios keeps a sign-in token in your keychain.")
                }
            }
            Section {
                Toggle("Achievements", isOn: $achievements.enabled)
                Toggle("Hardcore Mode", isOn: $achievements.hardcore)
            } footer: {
                Text("Hardcore mode doubles the challenge and counts for the hardcore leaderboards, but turns off rewind, loading save states, cheats and slow motion while a game with achievements is running.")
            }
            Section {
                Link("Create a free account", destination: URL(string: "https://retroachievements.org/createaccount.php")!)
            }
        }
        .navigationTitle("RetroAchievements")
        .onAppear { achievements.start() }
    }
}
