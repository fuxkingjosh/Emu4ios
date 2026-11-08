import UIKit

/// Imports controller skins made for Delta (.deltaskin) and turns them into an Emu4ios theme,
/// so the thousands of skins people have already made work here too.
enum DeltaSkinImporter {
    enum ImportError: LocalizedError {
        case notASkin, unsupportedConsole(String), noLayout
        var errorDescription: String? {
            switch self {
            case .notASkin: return "That file isn't a Delta skin."
            case .unsupportedConsole(let id): return "This skin is for a console Emu4ios doesn't know (\(id))."
            case .noLayout: return "This skin has no iPhone layout."
            }
        }
    }

    private static let consoles: [String: [GameSystem]] = [
        "com.rileytestut.delta.game.gba": [.gba],
        "com.rileytestut.delta.game.gbc": [.gb, .gbc],
        "com.rileytestut.delta.game.nes": [.nes],
        "com.rileytestut.delta.game.snes": [.snes],
        "com.rileytestut.delta.game.n64": [.n64],
        "com.rileytestut.delta.game.ds": [.nds],
        "com.rileytestut.delta.game.genesis": [.genesis, .segacd],
        "com.rileytestut.delta.game.ms": [.sms],
        "com.rileytestut.delta.game.gg": [.gamegear],
        "com.rileytestut.delta.game.ps1": [.ps1],
        "com.rileytestut.delta.game.psx": [.ps1],
    ]

    /// Reads a .deltaskin and returns a new theme based on `base` with the skin's controller.
    static func makeTheme(from url: URL, base: Theme) throws -> Theme {
        let zip = try ZipArchive(url: url)
        func file(_ name: String) -> Data? {
            guard let entry = zip.entries.first(where: { $0.name == name || $0.name.hasSuffix("/" + name) }) else { return nil }
            return try? zip.extract(entry)
        }
        guard let infoData = file("info.json"),
              let info = try JSONSerialization.jsonObject(with: infoData) as? [String: Any] else { throw ImportError.notASkin }
        let gameType = info["gameTypeIdentifier"] as? String ?? ""
        guard let systems = consoles[gameType] else { throw ImportError.unsupportedConsole(gameType) }
        let reps = (info["representations"] as? [String: Any])?["iphone"] as? [String: Any]
        guard let device = (reps?["edgeToEdge"] ?? reps?["standard"]) as? [String: Any] else { throw ImportError.noLayout }

        var skin = ControllerSkin.standard(for: systems[0])
        var foundAny = false
        if let p = device["portrait"] as? [String: Any], let layout = convert(p, system: systems[0], landscape: false, file: file) {
            skin.portrait = layout
            foundAny = true
        }
        if let l = device["landscape"] as? [String: Any], let layout = convert(l, system: systems[0], landscape: true, file: file) {
            skin.landscape = layout
            foundAny = true
        }
        guard foundAny else { throw ImportError.noLayout }

        var theme = base.duplicated()
        theme.name = (info["name"] as? String) ?? url.deletingPathExtension().lastPathComponent
        theme.author = "Delta skin"
        for system in systems { theme.controllers[system.rawValue] = skin }
        return theme
    }

    // MARK: Conversion

    private static func convert(_ rep: [String: Any], system: GameSystem, landscape: Bool,
                                file: (String) -> Data?) -> ControllerLayout? {
        guard let mapping = rep["mappingSize"] as? [String: Any],
              let mw = number(mapping["width"]), let mh = number(mapping["height"]), mw > 0, mh > 0 else { return nil }
        func norm(_ frame: Any?) -> NormRect? {
            guard let f = frame as? [String: Any], let x = number(f["x"]), let y = number(f["y"]),
                  let w = number(f["width"]), let h = number(f["height"]) else { return nil }
            return NormRect(x: x / mw, y: y / mh, w: w / mw, h: h / mh)
        }

        // The skin artwork becomes a picture behind invisible buttons.
        var decorations: [Decoration] = []
        if let assets = rep["assets"] as? [String: Any] {
            let name = (assets["resizable"] ?? assets["large"] ?? assets["medium"] ?? assets["small"]) as? String
            if let name, let data = file(name), let png = image(from: data, isPDF: name.lowercased().hasSuffix(".pdf"),
                                                                 size: CGSize(width: mw, height: mh)) {
                decorations.append(Decoration(imageData: png, frame: NormRect(x: 0, y: 0, w: 1, h: 1)))
            }
        }

        var buttons: [ButtonSpec] = []
        for item in rep["items"] as? [[String: Any]] ?? [] {
            guard var frame = norm(item["frame"]) else { continue }
            // Delta's extended edges grow the touch area beyond the drawn button.
            let edges = (item["extendedEdges"] ?? rep["extendedEdges"]) as? [String: Any]
            let grow = { (k: String) in number(edges?[k]) ?? 0 }
            frame = NormRect(x: frame.x - grow("left") / mw, y: frame.y - grow("top") / mh,
                             w: frame.w + (grow("left") + grow("right")) / mw, h: frame.h + (grow("top") + grow("bottom")) / mh)
            for input in inputs(item["inputs"], system: system) {
                var spec = ButtonSpec(input: input, frame: frame)
                spec.fill = ThemeColor(hex: "#00000000")
                spec.pressedFill = ThemeColor(hex: "#FFFFFF26")
                spec.border = ThemeColor(hex: "#00000000")
                spec.borderWidth = 0
                spec.label = ""
                spec.shape = input.isDirectional ? .roundedRect : .circle
                if input.isDirectional || input.isStick { spec.dpadStyle = .fourButtons; spec.opacity = 0.01 }
                buttons.append(spec)
            }
        }

        let screens = rep["screens"] as? [[String: Any]] ?? []
        let screenFrame = norm(screens.first?["outputFrame"]) ?? norm(rep["gameScreenFrame"])
        var layout = ControllerLayout(screen: screenFrame ?? ControllerSkin.standard(for: system).layout(landscape: landscape).screen,
                                      buttons: buttons)
        layout.decorations = decorations
        return layout
    }

    /// Delta input names → Emu4ios controls (one item can be a whole D-pad or stick).
    private static func inputs(_ raw: Any?, system: GameSystem) -> [ControlInput] {
        if let dict = raw as? [String: String] {
            let values = Set(dict.values)
            if values.contains("analogStickUp") { return [.leftStick] }
            if values.contains("up") || values.contains("left") { return [.dpad] }
            if values.contains("touchScreenX") { return [] } // the DS screen itself is the touch screen here
            return []
        }
        guard let list = raw as? [String] else { return [] }
        return list.compactMap { name -> ControlInput? in
            switch name {
            case "a": return system == .n64 ? .b : (system == .genesis || system == .segacd ? .y : .a)
            case "b": return system == .n64 ? .y : .b
            case "c": return .a
            case "x": return system == .genesis || system == .segacd ? .l : .x
            case "y": return system == .genesis || system == .segacd ? .x : .y
            case "z": return system == .n64 ? .l2 : .r
            case "l": return .l
            case "r": return .r
            case "start": return .start
            case "select", "mode": return .select
            case "menu": return .menu
            case "fastForward", "toggleFastForward": return .fastForward
            case "quickSave": return .quickSave
            case "quickLoad": return .quickLoad
            case "screenshot": return .screenshot
            case "cUp": return .cUp
            case "cDown": return .cDown
            case "cLeft": return .cLeft
            case "cRight": return .cRight
            case "up", "down", "left", "right": return .dpad
            default: return nil
            }
        }
    }

    private static func number(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    /// PDFs (Delta's resizable art) are drawn at 3× the layout size.
    private static func image(from data: Data, isPDF: Bool, size: CGSize) -> Data? {
        guard isPDF else { return UIImage(data: data)?.pngData() }
        guard let provider = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(provider),
              let page = doc.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: size.width / box.width, y: -size.height / box.height)
            cg.translateBy(x: -box.minX, y: -box.minY)
            cg.drawPDFPage(page)
        }
        return image.pngData()
    }
}
