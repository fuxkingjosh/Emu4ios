import ActivityKit
import UIKit

/// The "now playing" Live Activity is switched off: iOS can close a paused app without telling it, which
/// left a playing timer stuck in the Dynamic Island. This controller now only clears any leftovers.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private var activity: Activity<PlayActivityAttributes>?
    private var current: (game: Game, accentHex: String)?
    private var start = Date()
    private var pausedAt: Date?
    private var pausedTotal: Double = 0
    private var observers: [NSObjectProtocol] = []

    var isEnabled: Bool { false }

    private init() {
        // Anything left over from an earlier run (for example after a crash) goes away at launch.
        Self.endAll()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in LiveActivityController.shared.appLeft() }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in LiveActivityController.shared.appReturned() }
        })
        observers.append(center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            Self.endAllBlocking()
        })
    }

    /// Call once at launch so leftovers are cleaned up even before a game starts.
    func setUp() {}

    private func state(paused: Bool) -> PlayActivityAttributes.ContentState {
        let stats = PlayStats.shared
        let elapsedPause = pausedTotal + (pausedAt.map { Date().timeIntervalSince($0) } ?? 0)
        return .init(sessionStart: start.addingTimeInterval(elapsedPause), paused: paused, pausedSeconds: elapsedPause,
                     todayMinutes: stats.todayMinutes, goalMinutes: stats.goalMinutes)
    }

    func begin(game: Game, accentHex: String) {
        end()
        current = (game, accentHex)
        start = Date()
        pausedAt = nil
        pausedTotal = 0
        show()
    }

    private func show() {
        guard activity == nil, let current, isEnabled, ActivityAuthorizationInfo().areActivitiesEnabled,
              UIApplication.shared.applicationState != .background else { return }
        let attributes = PlayActivityAttributes(title: current.game.title, systemName: current.game.system.name,
                                                systemShort: current.game.system.shortName, accentHex: current.accentHex)
        // Stale after a while in case iOS ever keeps it around.
        let content = ActivityContent(state: state(paused: pausedAt != nil), staleDate: Date().addingTimeInterval(30 * 60))
        activity = try? Activity.request(attributes: attributes, content: content)
    }

    func setPaused(_ paused: Bool) {
        if paused, pausedAt == nil { pausedAt = Date() }
        if !paused, let p = pausedAt { pausedTotal += Date().timeIntervalSince(p); pausedAt = nil }
        guard let activity else { return }
        let content = ActivityContent(state: state(paused: paused), staleDate: Date().addingTimeInterval(30 * 60))
        Task { await activity.update(content) }
    }

    /// The game closed.
    func end() {
        current = nil
        removeActivity()
    }

    private func removeActivity() {
        guard let activity else { return }
        self.activity = nil
        let content = ActivityContent(state: state(paused: true), staleDate: nil)
        Task { await activity.end(content, dismissalPolicy: .immediate) }
    }

    private func appLeft() {
        // iOS can close a backgrounded app without telling it, so the activity goes now rather than linger.
        removeActivity()
        Self.endAll()
    }

    private func appReturned() {
        if current != nil { show() }
    }

    private static func endAll() {
        for activity in Activity<PlayActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// The app is about to quit: wait (briefly) until the activities are really gone.
    nonisolated private static func endAllBlocking() {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            for activity in Activity<PlayActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }
}
