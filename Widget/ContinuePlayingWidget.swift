import WidgetKit
import SwiftUI

struct ContinueEntry: TimelineEntry {
    let date: Date
    let game: WidgetShared.LastPlayed?
}

struct ContinueProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContinueEntry {
        ContinueEntry(date: .now, game: .init(gameID: "", title: "Your Game", systemName: "Game Boy Advance",
                                             playTimeSeconds: 3_600, lastPlayed: .now, thumbnail: nil, accentHex: "#7C5CFF"))
    }

    func getSnapshot(in context: Context, completion: @escaping (ContinueEntry) -> Void) {
        completion(ContinueEntry(date: .now, game: WidgetShared.load() ?? placeholder(in: context).game))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContinueEntry>) -> Void) {
        completion(Timeline(entries: [ContinueEntry(date: .now, game: WidgetShared.load())], policy: .never))
    }
}

struct ContinuePlayingView: View {
    let entry: ContinueEntry
    @Environment(\.widgetFamily) private var family

    private var accent: Color {
        guard let hex = entry.game?.accentHex.dropFirst(), let v = UInt64(hex.prefix(6), radix: 16) else { return .purple }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    var body: some View {
        if let game = entry.game {
            content(game)
                .widgetURL(game.gameID.isEmpty ? nil : WidgetShared.playURL(gameID: game.gameID))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "gamecontroller.fill").font(.title).foregroundStyle(accent)
                Text("Play a game to see it here").font(.caption).multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func content(_ game: WidgetShared.LastPlayed) -> some View {
        let thumb = game.thumbnail.flatMap(UIImage.init(data:))
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 6) {
                screenshot(thumb).frame(maxHeight: 70)
                Text(game.title).font(.caption.bold()).lineLimit(2)
                Label("Continue", systemImage: "play.fill").font(.caption2.bold()).foregroundStyle(accent)
            }
        } else {
            HStack(spacing: 12) {
                screenshot(thumb)
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONTINUE PLAYING").font(.caption2.bold()).foregroundStyle(accent)
                    Text(game.title).font(.headline).lineLimit(2)
                    Text(game.systemName).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Label("Resume", systemImage: "play.circle.fill").font(.subheadline.bold()).foregroundStyle(accent)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func screenshot(_ image: UIImage?) -> some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.3))
                    .overlay(Image(systemName: "gamecontroller.fill").foregroundStyle(accent))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ContinuePlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.widgetKind, provider: ContinueProvider()) { entry in
            ContinuePlayingView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Continue Playing")
        .description("Jump straight back into your last game.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct Emu4iosWidgetBundle: WidgetBundle {
    var body: some Widget {
        ContinuePlayingWidget()
        PlayLiveActivity()
    }
}
