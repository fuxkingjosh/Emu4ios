import ActivityKit
import SwiftUI
import WidgetKit

private func color(_ hex: String) -> Color {
    let v = UInt64(hex.dropFirst().prefix(6), radix: 16) ?? 0x7C5CFF
    return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

struct PlayLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlayActivityAttributes.self) { context in
            // Lock Screen
            let accent = color(context.attributes.accentHex)
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.25))
                    Text(context.attributes.systemShort).font(.caption.bold()).foregroundStyle(accent)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                    HStack(spacing: 6) {
                        Image(systemName: context.state.paused ? "pause.fill" : "gamecontroller.fill")
                        if context.state.paused {
                            Text("Paused")
                        } else {
                            Text(timerInterval: context.state.sessionStart...Date.distantFuture, countsDown: false)
                                .monospacedDigit()
                        }
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                GoalRing(today: context.state.todayMinutes, goal: context.state.goalMinutes, accent: accent)
                    .frame(width: 44, height: 44)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
            .activitySystemActionForegroundColor(accent)
        } dynamicIsland: { context in
            let accent = color(context.attributes.accentHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.systemShort, systemImage: "gamecontroller.fill")
                        .font(.caption.bold()).foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.paused {
                        Text("Paused").font(.caption)
                    } else {
                        Text(timerInterval: context.state.sessionStart...Date.distantFuture, countsDown: false)
                            .monospacedDigit().font(.caption).frame(width: 60)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.title).font(.headline).lineLimit(1)
                        Spacer()
                        Text("Today \(context.state.todayMinutes)/\(context.state.goalMinutes) min")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "gamecontroller.fill").foregroundStyle(accent)
            } compactTrailing: {
                if context.state.paused {
                    Image(systemName: "pause.fill")
                } else {
                    Text(timerInterval: context.state.sessionStart...Date.distantFuture, countsDown: false)
                        .monospacedDigit().frame(width: 44)
                }
            } minimal: {
                Image(systemName: "gamecontroller.fill").foregroundStyle(accent)
            }
            .keylineTint(accent)
        }
    }
}

struct GoalRing: View {
    let today: Int
    let goal: Int
    let accent: Color

    var body: some View {
        ZStack {
            Circle().stroke(accent.opacity(0.25), lineWidth: 5)
            Circle().trim(from: 0, to: min(1, Double(today) / Double(max(goal, 1))))
                .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(today)").font(.caption2.bold())
        }
    }
}
