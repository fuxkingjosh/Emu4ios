import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject var library: GameLibrary
    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var router: AppRouter
    @ObservedObject private var stats = PlayStats.shared

    private var style: AppStyle { themes.active.style }
    private var ranked: [Game] { library.games.filter { $0.playTimeSeconds > 0 }.sorted { $0.playTimeSeconds > $1.playTimeSeconds } }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemeBackground(style: themes.active.background)
                ScrollView {
                    VStack(spacing: 16) {
                        dailyCard
                        challengeCard
                        weekCard
                        badgesCard
                        HStack(spacing: 12) {
                            statTile("Total Play Time", value: format(library.totalPlayTime), icon: "clock.fill")
                            statTile("Games", value: "\(library.games.count)", icon: "square.stack.fill")
                        }
                        HStack(spacing: 12) {
                            statTile("Sessions", value: "\(library.games.reduce(0) { $0 + $1.sessions })", icon: "play.circle.fill")
                            statTile("Favorite System", value: favoriteSystem, icon: "star.fill")
                        }

                        if ranked.isEmpty {
                            Text("Play something and your stats will show up here.")
                                .font(style.font(.body)).foregroundStyle(style.secondaryText.color)
                                .padding(.top, 30)
                        } else {
                            card {
                                Text("Most Played").font(style.font(.headline, weight: .bold)).foregroundStyle(style.primaryText.color)
                                Chart(ranked.prefix(6)) { game in
                                    BarMark(x: .value("Hours", game.playTimeSeconds / 3600),
                                            y: .value("Game", game.title))
                                        .foregroundStyle(style.accent.color.gradient)
                                        .cornerRadius(6)
                                }
                                .chartXAxisLabel("Hours")
                                .frame(height: CGFloat(min(ranked.count, 6)) * 44 + 30)
                            }
                            card {
                                Text("All Games").font(style.font(.headline, weight: .bold)).foregroundStyle(style.primaryText.color)
                                ForEach(ranked) { game in
                                    Button { router.play(game) } label: {
                                        HStack {
                                            GameArtwork(game: game, size: 40)
                                            VStack(alignment: .leading) {
                                                Text(game.title).font(style.font(.subheadline, weight: .semibold))
                                                    .foregroundStyle(style.primaryText.color).lineLimit(1)
                                                Text("\(game.sessions) sessions · last \(game.lastPlayed?.formatted(.relative(presentation: .named)) ?? "never")")
                                                    .font(style.font(.caption)).foregroundStyle(style.secondaryText.color)
                                            }
                                            Spacer()
                                            Text(game.formattedPlayTime).font(style.font(.subheadline, weight: .bold))
                                                .foregroundStyle(style.accent.color)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(themes.active.label(.statsTitle))
        }
    }

    // MARK: Daily

    private var dailyCard: some View {
        card {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(style.accent.color.opacity(0.2), lineWidth: 12)
                    Circle().trim(from: 0, to: stats.goalProgress)
                        .stroke(style.accent.color.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring, value: stats.goalProgress)
                    VStack(spacing: 0) {
                        Text("\(stats.todayMinutes)").font(style.font(.title, weight: .heavy)).foregroundStyle(style.primaryText.color)
                        Text("of \(stats.goalMinutes) min").font(style.font(.caption2)).foregroundStyle(style.secondaryText.color)
                    }
                }
                .frame(width: 104, height: 104)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today's Goal").font(style.font(.headline, weight: .bold)).foregroundStyle(style.primaryText.color)
                    Label("\(stats.goalStreak)-day streak", systemImage: "flame.fill")
                        .font(style.font(.subheadline, weight: .semibold))
                        .foregroundStyle(stats.goalStreak > 0 ? .orange : style.secondaryText.color)
                    Text("Best: \(stats.bestStreak) days").font(style.font(.caption)).foregroundStyle(style.secondaryText.color)
                    Stepper("Goal \(stats.goalMinutes) min", value: $stats.goalMinutes, in: 5...180, step: 5)
                        .font(style.font(.caption)).foregroundStyle(style.primaryText.color)
                }
            }
        }
    }

    private var challengeCard: some View {
        let challenge = stats.todaysChallenge
        let done = stats.challengeDone
        return card {
            HStack(spacing: 14) {
                Image(systemName: done ? "checkmark.seal.fill" : challenge.icon)
                    .font(.title2)
                    .foregroundStyle(done ? .green : style.accent.color)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("DAILY CHALLENGE").font(style.font(.caption2, weight: .bold)).foregroundStyle(style.accent.color)
                    Text(challenge.title).font(style.font(.headline, weight: .semibold)).foregroundStyle(style.primaryText.color)
                    Text(done ? "Done! New challenge tomorrow." : "\(stats.challengesCompleted) challenges completed so far")
                        .font(style.font(.caption)).foregroundStyle(style.secondaryText.color)
                }
                Spacer()
            }
        }
    }

    private var weekCard: some View {
        card {
            Text("This Week").font(style.font(.headline, weight: .bold)).foregroundStyle(style.primaryText.color)
            Chart(Array(stats.lastWeek.enumerated()), id: \.offset) { item in
                BarMark(x: .value("Day", item.element.label), y: .value("Minutes", item.element.minutes))
                    .foregroundStyle(item.element.minutes >= Double(stats.goalMinutes) ? style.accent.color : style.accent.color.opacity(0.45))
                    .cornerRadius(5)
                RuleMark(y: .value("Goal", stats.goalMinutes))
                    .foregroundStyle(style.secondaryText.color.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .chartYAxisLabel("Minutes")
            .frame(height: 150)
        }
    }

    private var badgesCard: some View {
        card {
            HStack {
                Text("Badges").font(style.font(.headline, weight: .bold)).foregroundStyle(style.primaryText.color)
                Spacer()
                Text("\(stats.earned.count)/\(PlayStats.badges.count)").font(style.font(.caption)).foregroundStyle(style.secondaryText.color)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 12) {
                ForEach(PlayStats.badges) { badge in
                    let got = stats.earned[badge.id] != nil
                    VStack(spacing: 6) {
                        Image(systemName: badge.icon)
                            .font(.title2)
                            .frame(width: 48, height: 48)
                            .foregroundStyle(got ? style.background.color : style.secondaryText.color.opacity(0.5))
                            .background(got ? style.accent.color : style.secondaryText.color.opacity(0.12), in: Circle())
                        Text(badge.title).font(style.font(.caption2, weight: .bold)).foregroundStyle(style.primaryText.color)
                            .multilineTextAlignment(.center).lineLimit(2)
                        Text(badge.detail).font(style.font(.caption2)).foregroundStyle(style.secondaryText.color)
                            .multilineTextAlignment(.center).lineLimit(2)
                    }
                    .opacity(got ? 1 : 0.7)
                }
            }
        }
    }

    private var favoriteSystem: String {
        let totals = Dictionary(grouping: library.games, by: \.system).mapValues { $0.reduce(0) { $0 + $1.playTimeSeconds } }
        guard let best = totals.max(by: { $0.value < $1.value }), best.value > 0 else { return "—" }
        return best.key.shortName
    }

    private func format(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600, m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func statTile(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(style.accent.color)
            Text(value).font(style.font(.title2, weight: .heavy)).foregroundStyle(style.primaryText.color)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(title).font(style.font(.caption)).foregroundStyle(style.secondaryText.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(style.surface.color.opacity(0.92), in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(14)
            .background(style.surface.color.opacity(0.92), in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
    }
}
