import ActivityKit
import Foundation

@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private var activity: Activity<PlayActivityAttributes>?
    private var start = Date()
    private var pausedAt: Date?
    private var pausedTotal: Double = 0

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "liveActivityEnabled") }
    }

    private func state(paused: Bool) -> PlayActivityAttributes.ContentState {
        let stats = PlayStats.shared
        let elapsedPause = pausedTotal + (pausedAt.map { Date().timeIntervalSince($0) } ?? 0)
        return .init(sessionStart: start.addingTimeInterval(elapsedPause), paused: paused, pausedSeconds: elapsedPause,
                     todayMinutes: stats.todayMinutes, goalMinutes: stats.goalMinutes)
    }

    func begin(game: Game, accentHex: String) {
        end()
        guard isEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        start = Date()
        pausedAt = nil
        pausedTotal = 0
        let attributes = PlayActivityAttributes(title: game.title, systemName: game.system.name,
                                                systemShort: game.system.shortName, accentHex: accentHex)
        activity = try? Activity.request(attributes: attributes,
                                         content: .init(state: state(paused: false), staleDate: nil))
    }

    func setPaused(_ paused: Bool) {
        guard let activity else { return }
        if paused, pausedAt == nil { pausedAt = Date() }
        if !paused, let p = pausedAt { pausedTotal += Date().timeIntervalSince(p); pausedAt = nil }
        let content = ActivityContent(state: state(paused: paused), staleDate: nil)
        Task { await activity.update(content) }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        let content = ActivityContent(state: state(paused: true), staleDate: nil)
        Task { await activity.end(content, dismissalPolicy: .immediate) }
    }
}
