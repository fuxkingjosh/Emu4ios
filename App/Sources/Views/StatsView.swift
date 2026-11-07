import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject var library: GameLibrary
    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var router: AppRouter

    private var style: AppStyle { themes.active.style }
    private var ranked: [Game] { library.games.filter { $0.playTimeSeconds > 0 }.sorted { $0.playTimeSeconds > $1.playTimeSeconds } }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemeBackground(style: themes.active.background)
                ScrollView {
                    VStack(spacing: 16) {
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
