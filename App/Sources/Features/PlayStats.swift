import SwiftUI

/// Things that count toward daily challenges and badges.
enum PlayEvent: String, Codable {
    case saveState, screenshot, clip, themeEdited, themeUploaded, cheatAdded, fastForward, rewind
}

struct DayRecord: Codable {
    var seconds: Double = 0
    var games: Set<String> = []
    var systems: Set<String> = []
    var events: [String: Int] = [:]
}

struct DailyChallenge {
    let id: String
    let title: String
    let icon: String
    let isDone: (DayRecord, Int) -> Bool  // (today, goal minutes)
}

struct Badge: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
}

/// Daily goal, streaks, a daily challenge and badges — all stored on the device.
@MainActor
final class PlayStats: ObservableObject {
    static let shared = PlayStats()

    @Published private(set) var days: [String: DayRecord] = [:]
    @Published private(set) var earned: [String: Date] = [:]
    @Published var goalMinutes: Int {
        didSet { UserDefaults.standard.set(goalMinutes, forKey: "dailyGoalMinutes") }
    }
    /// Shown once as a celebration banner.
    @Published var newlyEarned: Badge?

    private let fileURL = AppPaths.libraryFile.deletingLastPathComponent().appendingPathComponent("playstats.json")
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private struct Stored: Codable { var days: [String: DayRecord]; var earned: [String: Date] }

    private init() {
        goalMinutes = UserDefaults.standard.object(forKey: "dailyGoalMinutes") as? Int ?? 20
        if let data = try? Data(contentsOf: fileURL), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            days = stored.days
            earned = stored.earned
        }
    }

    private func key(_ date: Date) -> String { formatter.string(from: date) }
    var today: DayRecord { days[key(.now)] ?? DayRecord() }
    var todayMinutes: Int { Int(today.seconds / 60) }
    var goalProgress: Double { min(1, today.seconds / 60 / Double(max(goalMinutes, 1))) }

    // MARK: Recording

    func recordPlay(game: Game, seconds: Double) {
        guard seconds > 1 else { return }
        var d = today
        d.seconds += seconds
        d.games.insert(game.id)
        d.systems.insert(game.system.rawValue)
        days[key(.now)] = d
        save()
        checkBadges()
    }

    func log(_ event: PlayEvent) {
        var d = today
        d.events[event.rawValue, default: 0] += 1
        days[key(.now)] = d
        save()
        checkBadges()
    }

    // MARK: Streaks

    /// Days in a row the daily goal was met (today counts once it's met; otherwise the streak runs to yesterday).
    var goalStreak: Int { streak { $0.seconds / 60 >= Double(goalMinutes) } }
    var playStreak: Int { streak { $0.seconds >= 60 } }
    var bestStreak: Int {
        let sorted = days.keys.sorted()
        var best = 0, run = 0
        var previous: Date?
        for k in sorted {
            guard let date = formatter.date(from: k), let d = days[k], d.seconds / 60 >= Double(goalMinutes) else { run = 0; previous = nil; continue }
            if let previous, Calendar.current.dateComponents([.day], from: previous, to: date).day == 1 { run += 1 } else { run = 1 }
            previous = date
            best = max(best, run)
        }
        return best
    }

    private func streak(_ qualifies: (DayRecord) -> Bool) -> Int {
        var count = 0
        var date = Date.now
        if !qualifies(today) { date = Calendar.current.date(byAdding: .day, value: -1, to: date)! }
        while let d = days[key(date)], qualifies(d) {
            count += 1
            date = Calendar.current.date(byAdding: .day, value: -1, to: date)!
        }
        return count
    }

    /// Minutes played on each of the last 7 days (oldest first).
    var lastWeek: [(label: String, minutes: Double)] {
        (0..<7).reversed().map { offset in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: .now)!
            let label = offset == 0 ? "Today" : date.formatted(.dateTime.weekday(.abbreviated))
            return (label, (days[key(date)]?.seconds ?? 0) / 60)
        }
    }

    // MARK: Daily challenge

    static let challenges: [DailyChallenge] = [
        DailyChallenge(id: "goal", title: "Hit your daily goal", icon: "target") { d, goal in d.seconds / 60 >= Double(goal) },
        DailyChallenge(id: "two-games", title: "Play 2 different games", icon: "square.on.square") { d, _ in d.games.count >= 2 },
        DailyChallenge(id: "states", title: "Make 3 save states", icon: "tray.and.arrow.down") { d, _ in (d.events["saveState"] ?? 0) >= 3 },
        DailyChallenge(id: "screenshot", title: "Take a screenshot", icon: "camera") { d, _ in (d.events["screenshot"] ?? 0) >= 1 },
        DailyChallenge(id: "clip", title: "Save a gameplay clip", icon: "film") { d, _ in (d.events["clip"] ?? 0) >= 1 },
        DailyChallenge(id: "theme", title: "Customize a theme or controller", icon: "paintbrush") { d, _ in (d.events["themeEdited"] ?? 0) >= 1 },
        DailyChallenge(id: "long", title: "Play 45 minutes", icon: "hourglass") { d, _ in d.seconds >= 45 * 60 },
        DailyChallenge(id: "systems", title: "Play games on 2 systems", icon: "gamecontroller") { d, _ in d.systems.count >= 2 },
    ]

    var todaysChallenge: DailyChallenge {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
        return Self.challenges[day % Self.challenges.count]
    }

    var challengeDone: Bool { todaysChallenge.isDone(today, goalMinutes) }

    var challengesCompleted: Int {
        days.reduce(0) { total, entry in
            guard let date = formatter.date(from: entry.key) else { return total }
            let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
            return total + (Self.challenges[day % Self.challenges.count].isDone(entry.value, goalMinutes) ? 1 : 0)
        }
    }

    // MARK: Badges

    static let badges: [Badge] = [
        Badge(id: "first", title: "Press Start", detail: "Play your first game", icon: "play.circle.fill"),
        Badge(id: "hour", title: "Warmed Up", detail: "Play for 1 hour total", icon: "flame.fill"),
        Badge(id: "ten-hours", title: "Dedicated", detail: "Play for 10 hours total", icon: "trophy.fill"),
        Badge(id: "streak3", title: "On a Roll", detail: "Hit your goal 3 days in a row", icon: "calendar"),
        Badge(id: "streak7", title: "Week Warrior", detail: "Hit your goal 7 days in a row", icon: "calendar.badge.checkmark"),
        Badge(id: "streak30", title: "Unstoppable", detail: "Hit your goal 30 days in a row", icon: "bolt.fill"),
        Badge(id: "collector", title: "Collector", detail: "Play 5 different games", icon: "square.stack.3d.up.fill"),
        Badge(id: "systems", title: "Time Traveler", detail: "Play games on 3 different systems", icon: "clock.arrow.2.circlepath"),
        Badge(id: "ps1", title: "Disc Jockey", detail: "Play a PlayStation game", icon: "opticaldisc.fill"),
        Badge(id: "museum", title: "Museum Curator", detail: "Play games on 10 different systems", icon: "building.columns.fill"),
        Badge(id: "polygons", title: "Polygon Pusher", detail: "Play a Nintendo 64 or PSP game", icon: "cube.transparent.fill"),
        Badge(id: "designer", title: "Designer", detail: "Customize a theme or controller", icon: "paintpalette.fill"),
        Badge(id: "sharer", title: "Trendsetter", detail: "Upload a theme to the gallery", icon: "icloud.and.arrow.up.fill"),
        Badge(id: "director", title: "Director", detail: "Save a gameplay clip", icon: "film.fill"),
        Badge(id: "challenger", title: "Challenger", detail: "Complete 5 daily challenges", icon: "star.circle.fill"),
    ]

    private func checkBadges() {
        let totalSeconds = days.values.reduce(0) { $0 + $1.seconds }
        let allGames = days.values.reduce(into: Set<String>()) { $0.formUnion($1.games) }
        let allSystems = days.values.reduce(into: Set<String>()) { $0.formUnion($1.systems) }
        func count(_ e: PlayEvent) -> Int { days.values.reduce(0) { $0 + ($1.events[e.rawValue] ?? 0) } }
        let streak = goalStreak
        let checks: [String: Bool] = [
            "first": totalSeconds > 0,
            "hour": totalSeconds >= 3_600,
            "ten-hours": totalSeconds >= 36_000,
            "streak3": streak >= 3,
            "streak7": streak >= 7,
            "streak30": streak >= 30,
            "collector": allGames.count >= 5,
            "systems": allSystems.count >= 3,
            "ps1": allSystems.contains(GameSystem.ps1.rawValue),
            "museum": allSystems.count >= 10,
            "polygons": allSystems.contains(GameSystem.n64.rawValue) || allSystems.contains(GameSystem.psp.rawValue),
            "designer": count(.themeEdited) > 0,
            "sharer": count(.themeUploaded) > 0,
            "director": count(.clip) > 0,
            "challenger": challengesCompleted >= 5,
        ]
        for (id, done) in checks where done && earned[id] == nil {
            earned[id] = .now
            newlyEarned = Self.badges.first { $0.id == id }
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Stored(days: days, earned: earned)) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
