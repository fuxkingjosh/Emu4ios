import ActivityKit
import Foundation

/// Live Activity shown on the Lock Screen and Dynamic Island while you play.
struct PlayActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Adjusted so `Text(timerInterval:)` shows the time played this session.
        var sessionStart: Date
        var paused: Bool
        var pausedSeconds: Double
        var todayMinutes: Int
        var goalMinutes: Int
    }

    var title: String
    var systemName: String
    var systemShort: String
    var accentHex: String
}
