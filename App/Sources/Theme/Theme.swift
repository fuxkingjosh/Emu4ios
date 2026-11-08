import SwiftUI

// A theme controls everything the user sees: app colors, fonts, every text label,
// the background, the game screen look, and the on-screen controller for each system.
// It is plain Codable data, so it can be saved, shared as a file/link/QR, and imported.

struct Theme: Codable, Identifiable, Hashable {
    static let schemaVersion = 1

    var id: String = UUID().uuidString
    var name: String
    var author: String = ""
    var schema: Int = Theme.schemaVersion
    var createdAt: Date = .now
    var isBuiltIn: Bool = false

    var style: AppStyle = AppStyle()
    var background: BackgroundStyle = BackgroundStyle()
    var screen: ScreenStyle = ScreenStyle()
    /// Controller skin per system ("gb", "gbc", "gba"). Missing systems fall back to `defaultController`.
    var controllers: [String: ControllerSkin] = [:]
    var defaultController: ControllerSkin = .standard(for: .gba)

    func controller(for system: GameSystem) -> ControllerSkin {
        controllers[system.rawValue] ?? defaultController.adapted(to: system)
    }

    func label(_ key: LabelKey) -> String {
        if let custom = style.labels[key.rawValue], !custom.isEmpty { return custom }
        return key.defaultText
    }

    /// A copy the user can edit (built-ins are read-only).
    func duplicated(named newName: String? = nil) -> Theme {
        var copy = self
        copy.id = UUID().uuidString
        copy.name = newName ?? "\(name) Copy"
        copy.isBuiltIn = false
        copy.createdAt = .now
        return copy
    }
}

// MARK: - Colors

/// Color stored as "#RRGGBBAA" so themes stay human-readable when shared.
struct ThemeColor: Codable, Hashable {
    var hex: String

    init(hex: String) { self.hex = ThemeColor.normalize(hex) }
    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        func c(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        hex = String(format: "#%02X%02X%02X%02X", c(r), c(g), c(b), c(a))
    }
    init(_ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Double(r), Double(g), Double(b), Double(a))
    }

    init(from decoder: Decoder) throws {
        hex = ThemeColor.normalize(try decoder.singleValueContainer().decode(String.self))
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }

    var components: (r: Double, g: Double, b: Double, a: Double) {
        let s = hex.dropFirst()
        let v = UInt64(s, radix: 16) ?? 0xFFFFFFFF
        return (Double((v >> 24) & 0xFF) / 255, Double((v >> 16) & 0xFF) / 255,
                Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
    var color: Color {
        let c = components
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }
    var uiColor: UIColor {
        let c = components
        return UIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
    var simd: SIMD4<Float> {
        let c = components
        return SIMD4(Float(c.r), Float(c.g), Float(c.b), Float(c.a))
    }

    private static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        if s.count == 6 { s += "FF" }
        guard s.count == 8, UInt64(s, radix: 16) != nil else { return "#FFFFFFFF" }
        return "#" + s
    }

    func darkened(_ amount: Double) -> ThemeColor {
        let c = components
        return ThemeColor(c.r * (1 - amount), c.g * (1 - amount), c.b * (1 - amount), c.a)
    }

    static let white = ThemeColor(hex: "#FFFFFF")
    static let black = ThemeColor(hex: "#000000")
    static let clear = ThemeColor(hex: "#00000000")
}

// MARK: - App style

enum ThemeFontDesign: String, Codable, CaseIterable, Identifiable {
    case standard, rounded, monospaced, serif
    var id: String { rawValue }
    var design: Font.Design {
        switch self {
        case .standard: return .default
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        case .serif: return .serif
        }
    }
}

enum LibraryLayout: String, Codable, CaseIterable, Identifiable {
    case grid, list, shelf
    var id: String { rawValue }
}

struct AppStyle: Codable, Hashable {
    var accent = ThemeColor(hex: "#7C5CFF")
    var background = ThemeColor(hex: "#0E0E14")
    var surface = ThemeColor(hex: "#1B1B26")
    var primaryText = ThemeColor(hex: "#FFFFFF")
    var secondaryText = ThemeColor(hex: "#A3A3B5")
    var fontDesign: ThemeFontDesign = .rounded
    /// Optional installed font family name (e.g. "Menlo", "Chalkboard SE"). Overrides `fontDesign`.
    var fontName: String?
    var fontScale: Double = 1.0
    var cornerRadius: Double = 16
    var libraryLayout: LibraryLayout = .grid
    var darkMode: Bool = true
    /// Custom text for any label in the app, keyed by `LabelKey.rawValue`.
    var labels: [String: String] = [:]

    func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        let base = UIFont.preferredFont(forTextStyle: style.uiStyle).pointSize * fontScale
        if let fontName, !fontName.isEmpty, !UIFont.fontNames(forFamilyName: fontName).isEmpty {
            return .custom(fontName, size: base).weight(weight)
        }
        return .system(size: base, weight: weight, design: fontDesign.design)
    }
}

private extension Font.TextStyle {
    var uiStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }
}

// MARK: - Background

enum BackgroundKind: String, Codable, CaseIterable, Identifiable {
    case solid, gradient, particles, waves, synthGrid, starfield, bubbles, image
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .solid: return "Solid"
        case .gradient: return "Gradient"
        case .particles: return "Floating Pixels"
        case .waves: return "Waves"
        case .synthGrid: return "Synth Grid"
        case .starfield: return "Starfield"
        case .bubbles: return "Bubbles"
        case .image: return "Photo / GIF"
        }
    }
    var isAnimated: Bool { ![.solid, .gradient, .image].contains(self) }
}

struct BackgroundStyle: Codable, Hashable {
    var kind: BackgroundKind = .gradient
    var colors: [ThemeColor] = [ThemeColor(hex: "#14102A"), ThemeColor(hex: "#0B0B12")]
    var speed: Double = 1.0
    var density: Double = 0.5
    /// JPEG data for `.image` backgrounds (kept small so themes stay shareable).
    var imageData: Data?
    var imageDim: Double = 0.3
    /// Show the background behind the game too, not just in menus.
    var showInGame: Bool = true
}

// MARK: - Game screen

enum ScreenFilter: String, Codable, CaseIterable, Identifiable {
    // New filters must be added at the end (the shader picks them by position).
    case none, smooth, crt, lcdGrid, dmgGreen, pocket, colorCorrect, scanlines, sharpSmooth, dotMatrix, vhs, handheldLCD
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none: return "Sharp Pixels"
        case .smooth: return "Smooth"
        case .crt: return "CRT TV"
        case .lcdGrid: return "LCD Grid"
        case .dmgGreen: return "Original Game Boy Green"
        case .pocket: return "Game Boy Pocket"
        case .colorCorrect: return "Handheld Color Correction"
        case .scanlines: return "Scanlines"
        case .sharpSmooth: return "Sharp but Smooth"
        case .dotMatrix: return "Dot Matrix"
        case .vhs: return "VHS Tape"
        case .handheldLCD: return "Handheld LCD (subpixels)"
        }
    }
    var shaderIndex: Int32 { Int32(ScreenFilter.allCases.firstIndex(of: self) ?? 0) }
}

enum BezelStyle: String, Codable, CaseIterable, Identifiable {
    case none, handheld, brick, crtTV, arcade, glass
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none: return "No Frame"
        case .handheld: return "Handheld Shell"
        case .brick: return "Classic Brick"
        case .crtTV: return "CRT TV"
        case .arcade: return "Arcade Cabinet"
        case .glass: return "Frosted Glass"
        }
    }
    /// Frame thickness around the screen, as a fraction of the screen's width (left/right/top) and bottom.
    var thickness: (side: Double, top: Double, bottom: Double) {
        switch self {
        case .none: return (0, 0, 0)
        case .handheld: return (0.09, 0.09, 0.09)
        case .brick: return (0.10, 0.10, 0.17)
        case .crtTV: return (0.08, 0.08, 0.10)
        case .arcade: return (0.05, 0.05, 0.05)
        case .glass: return (0.045, 0.045, 0.045)
        }
    }
}

struct ScreenStyle: Codable, Hashable {
    var bezel: BezelStyle = .none
    var bezelColor = ThemeColor(hex: "#2B2B35")
    var filter: ScreenFilter = .none
    var intensity: Double = 0.6
    var borderColor = ThemeColor(hex: "#00000000")
    var borderWidth: Double = 0
    var cornerRadius: Double = 6
    var glow: Double = 0
    var integerScaling: Bool = false
}

// MARK: - Tolerant decoding (fills in defaults for missing fields)

extension Theme {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name))
        id = c.value(.id, id)
        author = c.value(.author, author)
        schema = c.value(.schema, schema)
        createdAt = c.value(.createdAt, createdAt)
        isBuiltIn = c.value(.isBuiltIn, isBuiltIn)
        style = c.value(.style, style)
        background = c.value(.background, background)
        screen = c.value(.screen, screen)
        controllers = c.value(.controllers, controllers)
        defaultController = c.value(.defaultController, defaultController)
    }
}

extension AppStyle {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        accent = c.value(.accent, accent)
        background = c.value(.background, background)
        surface = c.value(.surface, surface)
        primaryText = c.value(.primaryText, primaryText)
        secondaryText = c.value(.secondaryText, secondaryText)
        fontDesign = c.value(.fontDesign, fontDesign)
        fontName = c.value(.fontName, fontName)
        fontScale = c.value(.fontScale, fontScale)
        cornerRadius = c.value(.cornerRadius, cornerRadius)
        libraryLayout = c.value(.libraryLayout, libraryLayout)
        darkMode = c.value(.darkMode, darkMode)
        labels = c.value(.labels, labels)
    }
}

extension BackgroundStyle {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        kind = c.value(.kind, kind)
        colors = c.value(.colors, colors)
        speed = c.value(.speed, speed)
        density = c.value(.density, density)
        imageData = c.value(.imageData, imageData)
        imageDim = c.value(.imageDim, imageDim)
        showInGame = c.value(.showInGame, showInGame)
    }
}

extension ScreenStyle {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        bezel = c.value(.bezel, bezel)
        bezelColor = c.value(.bezelColor, bezelColor)
        filter = c.value(.filter, filter)
        intensity = c.value(.intensity, intensity)
        borderColor = c.value(.borderColor, borderColor)
        borderWidth = c.value(.borderWidth, borderWidth)
        cornerRadius = c.value(.cornerRadius, cornerRadius)
        glow = c.value(.glow, glow)
        integerScaling = c.value(.integerScaling, integerScaling)
    }
}
