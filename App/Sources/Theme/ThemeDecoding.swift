import Foundation

// Themes are saved and shared as JSON. These decoders fill in defaults for any field a theme
// doesn't have, so themes made with older (or newer) versions of the app always load.

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback()
    }
}

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
        filter = c.value(.filter, filter)
        intensity = c.value(.intensity, intensity)
        borderColor = c.value(.borderColor, borderColor)
        borderWidth = c.value(.borderWidth, borderWidth)
        cornerRadius = c.value(.cornerRadius, cornerRadius)
        glow = c.value(.glow, glow)
        integerScaling = c.value(.integerScaling, integerScaling)
    }
}

extension ControllerSkin {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ControllerSkin.standard(for: .gba)
        self.init(portrait: c.value(.portrait, fallback.portrait), landscape: c.value(.landscape, fallback.landscape))
        hapticsEnabled = c.value(.hapticsEnabled, hapticsEnabled)
        soundsEnabled = c.value(.soundsEnabled, soundsEnabled)
        hideWhenControllerConnected = c.value(.hideWhenControllerConnected, hideWhenControllerConnected)
    }
}

extension ControllerLayout {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(screen: c.value(.screen, NormRect(x: 0, y: 0.06, w: 1, h: 0.4)),
                  buttons: c.value(.buttons, []))
        deckColor = c.value(.deckColor, deckColor)
        decorations = c.value(.decorations, decorations)
    }
}

extension ButtonSpec {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(input: try c.decode(ControlInput.self, forKey: .input),
                  frame: try c.decode(NormRect.self, forKey: .frame))
        id = c.value(.id, id)
        shape = c.value(.shape, shape)
        fill = c.value(.fill, fill)
        pressedFill = c.value(.pressedFill, pressedFill)
        border = c.value(.border, border)
        borderWidth = c.value(.borderWidth, borderWidth)
        label = c.value(.label, label)
        labelColor = c.value(.labelColor, labelColor)
        labelSize = c.value(.labelSize, labelSize)
        opacity = c.value(.opacity, opacity)
        hidden = c.value(.hidden, hidden)
        haptic = c.value(.haptic, haptic)
        sound = c.value(.sound, sound)
        turbo = c.value(.turbo, turbo)
        dpadStyle = c.value(.dpadStyle, dpadStyle)
        dpadDiagonals = c.value(.dpadDiagonals, dpadDiagonals)
        imageData = c.value(.imageData, imageData)
        pressedImageData = c.value(.pressedImageData, pressedImageData)
    }
}

extension Decoration {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(imageData: try c.decode(Data.self, forKey: .imageData), frame: try c.decode(NormRect.self, forKey: .frame))
        id = c.value(.id, id)
        opacity = c.value(.opacity, opacity)
        aboveButtons = c.value(.aboveButtons, aboveButtons)
        cornerRadius = c.value(.cornerRadius, cornerRadius)
    }
}
