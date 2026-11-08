import Foundation

enum BuiltInThemes {
    static let all: [Theme] = [midnight, neon, dmg, candy, minimal]
    static var defaultTheme: Theme { midnight }

    private static func skins(_ style: (inout ButtonSpec) -> Void) -> ([String: ControllerSkin], ControllerSkin) {
        var dict: [String: ControllerSkin] = [:]
        for system in GameSystem.allCases {
            dict[system.rawValue] = ControllerSkin.standard(for: system).restyled(style)
        }
        return (dict, ControllerSkin.standard(for: .gba).restyled(style))
    }

    static let midnight: Theme = {
        var t = Theme(name: "Midnight", author: "Emu4ios", isBuiltIn: true)
        t.id = "builtin.midnight"
        (t.controllers, t.defaultController) = skins { _ in }
        return t
    }()

    static let neon: Theme = {
        var t = Theme(name: "Neon Arcade", author: "Emu4ios", isBuiltIn: true)
        t.id = "builtin.neon"
        t.style.accent = ThemeColor(hex: "#FF2BD6")
        t.style.background = ThemeColor(hex: "#07020F")
        t.style.surface = ThemeColor(hex: "#160A2A")
        t.style.secondaryText = ThemeColor(hex: "#B98CFF")
        t.style.fontDesign = .monospaced
        t.background = BackgroundStyle(kind: .synthGrid,
                                       colors: [ThemeColor(hex: "#FF2BD6"), ThemeColor(hex: "#00E5FF"), ThemeColor(hex: "#07020F")],
                                       speed: 1, density: 0.5)
        t.screen = ScreenStyle(filter: .crt, intensity: 0.5, borderColor: ThemeColor(hex: "#00E5FF"),
                               borderWidth: 2, cornerRadius: 10, glow: 0.8)
        (t.controllers, t.defaultController) = skins { b in
            b.fill = ThemeColor(hex: "#FF2BD622")
            b.pressedFill = ThemeColor(hex: "#FF2BD688")
            b.border = ThemeColor(hex: "#00E5FF")
            b.borderWidth = 2
            b.labelColor = ThemeColor(hex: "#00E5FF")
            b.haptic = .rigid
            b.sound = .tick
        }
        return t
    }()

    static let dmg: Theme = {
        var t = Theme(name: "Pea Soup", author: "Emu4ios", isBuiltIn: true)
        t.id = "builtin.dmg"
        t.style.accent = ThemeColor(hex: "#8B1E5A")
        t.style.background = ThemeColor(hex: "#C4C0B4")
        t.style.surface = ThemeColor(hex: "#D8D4C8")
        t.style.primaryText = ThemeColor(hex: "#1E1E2A")
        t.style.secondaryText = ThemeColor(hex: "#4F4F63")
        t.style.darkMode = false
        t.style.fontDesign = .monospaced
        t.background = BackgroundStyle(kind: .solid, colors: [ThemeColor(hex: "#C4C0B4")])
        t.screen = ScreenStyle(bezel: .brick, bezelColor: ThemeColor(hex: "#5A5A6E"), filter: .dmgGreen, intensity: 0.8,
                               borderColor: ThemeColor(hex: "#00000000"), borderWidth: 0, cornerRadius: 3, glow: 0)
        (t.controllers, t.defaultController) = skins { b in
            switch b.input {
            case .a, .b:
                b.fill = ThemeColor(hex: "#8B1E5A"); b.pressedFill = ThemeColor(hex: "#5E0F3B")
                b.labelColor = ThemeColor(hex: "#F0E8EC")
            case .dpad:
                b.fill = ThemeColor(hex: "#2A2A33"); b.pressedFill = ThemeColor(hex: "#111116")
            default:
                b.fill = ThemeColor(hex: "#8E8E9C"); b.pressedFill = ThemeColor(hex: "#5F5F6B")
                b.labelColor = ThemeColor(hex: "#2A2A33")
            }
            b.border = ThemeColor.clear
            b.borderWidth = 0
            b.haptic = .medium
            b.sound = .click
        }
        return t
    }()

    static let candy: Theme = {
        var t = Theme(name: "Candy Pop", author: "Emu4ios", isBuiltIn: true)
        t.id = "builtin.candy"
        t.style.accent = ThemeColor(hex: "#FF6FAE")
        t.style.background = ThemeColor(hex: "#FFF1F7")
        t.style.surface = ThemeColor(hex: "#FFFFFF")
        t.style.primaryText = ThemeColor(hex: "#3B1D33")
        t.style.secondaryText = ThemeColor(hex: "#9A6A88")
        t.style.darkMode = false
        t.style.cornerRadius = 24
        t.background = BackgroundStyle(kind: .bubbles,
                                       colors: [ThemeColor(hex: "#FFD1E8"), ThemeColor(hex: "#C9F1FF"), ThemeColor(hex: "#FFF1F7")],
                                       speed: 0.6, density: 0.6)
        t.screen = ScreenStyle(filter: .smooth, intensity: 0.5, borderColor: ThemeColor(hex: "#FF6FAE"),
                               borderWidth: 4, cornerRadius: 18, glow: 0.3)
        (t.controllers, t.defaultController) = skins { b in
            b.fill = ThemeColor(hex: "#FF6FAECC"); b.pressedFill = ThemeColor(hex: "#E04A8C")
            b.border = ThemeColor(hex: "#FFFFFF"); b.borderWidth = 3
            b.labelColor = ThemeColor(hex: "#FFFFFF")
            if b.input == .b { b.fill = ThemeColor(hex: "#6FC8FFCC"); b.pressedFill = ThemeColor(hex: "#3BA3E0") }
            b.haptic = .soft
            b.sound = .bubble
        }
        return t
    }()

    static let minimal: Theme = {
        var t = Theme(name: "Ghost", author: "Emu4ios", isBuiltIn: true)
        t.id = "builtin.ghost"
        t.style.accent = ThemeColor(hex: "#FFFFFF")
        t.style.background = ThemeColor(hex: "#000000")
        t.style.surface = ThemeColor(hex: "#111111")
        t.style.fontDesign = .standard
        t.background = BackgroundStyle(kind: .solid, colors: [ThemeColor(hex: "#000000")])
        (t.controllers, t.defaultController) = skins { b in
            b.fill = ThemeColor(hex: "#FFFFFF0D"); b.pressedFill = ThemeColor(hex: "#FFFFFF33")
            b.border = ThemeColor(hex: "#FFFFFF22"); b.borderWidth = 1
            b.labelColor = ThemeColor(hex: "#FFFFFF55")
            b.haptic = .light
        }
        return t
    }()
}
