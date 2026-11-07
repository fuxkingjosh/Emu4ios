import SwiftUI

/// Draws a theme's background — solid, gradient, photo, or one of the animated styles.
struct ThemeBackground: View {
    let style: BackgroundStyle
    var paused = false

    var body: some View {
        ZStack {
            switch style.kind {
            case .solid:
                (style.colors.first ?? .black).color
            case .gradient:
                LinearGradient(colors: style.colors.map(\.color), startPoint: .topLeading, endPoint: .bottomTrailing)
            case .image:
                if let data = style.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .overlay(Color.black.opacity(style.imageDim))
                } else {
                    (style.colors.first ?? .black).color
                }
            default:
                TimelineView(.animation(paused: paused)) { context in
                    Canvas { ctx, size in
                        let t = context.date.timeIntervalSinceReferenceDate * style.speed
                        AnimatedBackgroundPainter.paint(style, time: t, in: &ctx, size: size)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

private extension Array where Element == ThemeColor {
    func at(_ i: Int, _ fallback: ThemeColor) -> ThemeColor { indices.contains(i) ? self[i] : fallback }
}

enum AnimatedBackgroundPainter {
    /// Deterministic pseudo-random so particles keep their identity between frames.
    private static func rand(_ seed: Int, _ salt: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: seed &* 2_654_435_761 &+ salt &* 40_503)
        x ^= x >> 13; x = x &* 0x5bd1e995; x ^= x >> 15
        return Double(x % 10_000) / 10_000
    }

    static func paint(_ style: BackgroundStyle, time t: Double, in ctx: inout GraphicsContext, size: CGSize) {
        let c0 = style.colors.at(0, .white), c1 = style.colors.at(1, c0), base = style.colors.at(2, .black)
        let rect = CGRect(origin: .zero, size: size)
        let count = Int(20 + style.density * 120)

        switch style.kind {
        case .particles:
            ctx.fill(Path(rect), with: .color(base.color))
            for i in 0..<count {
                let speed = 0.02 + rand(i, 1) * 0.05
                let x = rand(i, 2) * size.width + sin(t * 0.5 + Double(i)) * 12
                let y = size.height - (rand(i, 3) * size.height + t * speed * size.height).truncatingRemainder(dividingBy: size.height + 20)
                let s = 3 + rand(i, 4) * 7
                let color = (i % 2 == 0 ? c0 : c1).color.opacity(0.25 + rand(i, 5) * 0.5)
                ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(color))
            }
        case .waves:
            ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [base.color, c1.color.opacity(0.4)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            for layer in 0..<4 {
                var p = Path()
                let amp = 18 + Double(layer) * 10
                let yBase = size.height * (0.55 + Double(layer) * 0.1)
                p.move(to: CGPoint(x: 0, y: size.height))
                stride(from: 0.0, through: size.width, by: 6).forEach { x in
                    let y = yBase + sin(x / 70 + t * (0.6 + Double(layer) * 0.2) + Double(layer)) * amp
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                p.addLine(to: CGPoint(x: size.width, y: size.height))
                p.closeSubpath()
                ctx.fill(p, with: .color((layer % 2 == 0 ? c0 : c1).color.opacity(0.18 + Double(layer) * 0.05)))
            }
        case .synthGrid:
            ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [base.color, c0.color.opacity(0.35), base.color]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let horizon = size.height * 0.45
            // Sun
            let sun = CGRect(x: size.width / 2 - 80, y: horizon - 130, width: 160, height: 160)
            ctx.fill(Path(ellipseIn: sun), with: .linearGradient(Gradient(colors: [c1.color, c0.color]),
                                                                 startPoint: CGPoint(x: 0, y: sun.minY), endPoint: CGPoint(x: 0, y: sun.maxY)))
            ctx.fill(Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)), with: .color(base.color))
            var grid = Path()
            let lines = 14
            for i in 0...lines {
                let progress = (Double(i) / Double(lines) + (t * 0.25).truncatingRemainder(dividingBy: 1.0 / Double(lines)) * Double(lines) / Double(lines))
                let y = horizon + pow(progress, 2.2) * (size.height - horizon)
                grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            for i in -10...10 {
                let xBottom = size.width / 2 + Double(i) * size.width / 6
                grid.move(to: CGPoint(x: size.width / 2 + Double(i) * 12, y: horizon))
                grid.addLine(to: CGPoint(x: xBottom, y: size.height))
            }
            ctx.stroke(grid, with: .color(c0.color.opacity(0.75)), lineWidth: 1.2)
        case .starfield:
            ctx.fill(Path(rect), with: .color(base.color))
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0..<count {
                let angle = rand(i, 1) * .pi * 2
                let z = (rand(i, 2) + t * 0.15).truncatingRemainder(dividingBy: 1)
                let r = pow(z, 2) * max(size.width, size.height)
                let p = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
                let s = 1 + z * 3
                ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: s, height: s)),
                         with: .color((i % 3 == 0 ? c1 : c0).color.opacity(z)))
            }
        case .bubbles:
            ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [base.color, c1.color.opacity(0.5)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            for i in 0..<max(8, count / 4) {
                let r = 20 + rand(i, 1) * 60
                let x = rand(i, 2) * size.width + sin(t * 0.4 + Double(i)) * 20
                let travel = size.height + r * 2
                let y = size.height + r - (rand(i, 3) * travel + t * (20 + rand(i, 4) * 30)).truncatingRemainder(dividingBy: travel)
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color((i % 2 == 0 ? c0 : c1).color.opacity(0.35)))
            }
        default:
            ctx.fill(Path(rect), with: .color(base.color))
        }
    }
}

/// Small live preview of a theme: background, a fake screen, and the controller.
struct ThemePreviewCard: View {
    let theme: Theme
    var system: GameSystem = .gba

    var body: some View {
        GeometryReader { geo in
            let skin = theme.controller(for: system)
            let layout = skin.portrait
            ZStack(alignment: .topLeading) {
                ThemeBackground(style: theme.background, paused: false)
                let screenRect = layout.screen.rect(in: geo.size)
                RoundedRectangle(cornerRadius: theme.screen.cornerRadius * 0.5)
                    .fill(LinearGradient(colors: [theme.style.accent.color.opacity(0.6), theme.style.surface.color],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: theme.screen.cornerRadius * 0.5)
                        .strokeBorder(theme.screen.borderColor.color, lineWidth: theme.screen.borderWidth * 0.5))
                    .overlay(Text(system.shortName).font(.caption.bold()).foregroundStyle(.white.opacity(0.7)))
                    .frame(width: screenRect.width * 0.86, height: screenRect.height * 0.86)
                    .position(x: screenRect.midX, y: screenRect.midY)
                Canvas { ctx, size in
                    ctx.withCGContext { cg in
                        UIGraphicsPushContext(cg)
                        for spec in layout.buttons where !spec.hidden {
                            ButtonRenderer.draw(spec, in: spec.frame.rect(in: size), pressedMask: nil, context: cg)
                        }
                        UIGraphicsPopContext()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .aspectRatio(9.0 / 19.5, contentMode: .fit)
    }
}
