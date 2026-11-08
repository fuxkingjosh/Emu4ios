import SwiftUI
import PhotosUI
import Photos

/// A custom app icon design. The pixel "4" is always part of it.
struct IconDesign: Codable, Equatable {
    enum Style: String, Codable, CaseIterable, Identifiable {
        case handheld, bigFour, badge
        var id: String { rawValue }
        var title: String {
            switch self {
            case .handheld: return "Handheld"
            case .bigFour: return "Big 4"
            case .badge: return "Badge"
            }
        }
    }

    var style: Style = .handheld
    var top = ThemeColor(hex: "#7C5CFF")
    var bottom = ThemeColor(hex: "#28145A")
    var body = ThemeColor(hex: "#ECECF4")
    var screen = ThemeColor(hex: "#9BBC0F")
    var four = ThemeColor(hex: "#1B3A0A")
    var dpad = ThemeColor(hex: "#282834")
    var buttonA = ThemeColor(hex: "#E6286E")
    var buttonB = ThemeColor(hex: "#E6286E")
    /// Optional photo behind everything.
    var photo: Data?
    var photoDim: Double = 0.2

    static func load() -> IconDesign {
        guard let data = UserDefaults.standard.data(forKey: "iconDesign"),
              let d = try? JSONDecoder().decode(IconDesign.self, from: data) else { return IconDesign() }
        return d
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "iconDesign") }
    }
}

/// Draws an icon design at any size (designed on a 1024 grid).
struct IconArtwork: View {
    let design: IconDesign

    var body: some View {
        Canvas { ctx, size in
            let k = size.width / 1024
            func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
                CGRect(x: x * k, y: y * k, width: w * k, height: h * k)
            }
            let full = CGRect(origin: .zero, size: size)
            ctx.fill(Path(full), with: .linearGradient(Gradient(colors: [design.top.color, design.bottom.color]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            if let data = design.photo, let image = UIImage(data: data) {
                let img = ctx.resolve(Image(uiImage: image))
                let scale = max(size.width / image.size.width, size.height / image.size.height)
                let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                ctx.draw(img, in: CGRect(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2,
                                         width: drawSize.width, height: drawSize.height))
                ctx.fill(Path(full), with: .color(.black.opacity(design.photoDim)))
            }

            func drawFour(origin: CGPoint, pixel: Double, color: Color) {
                let glyph = ["1001", "1001", "1111", "0001", "0001", "0001"]
                for (row, line) in glyph.enumerated() {
                    for (col, ch) in line.enumerated() where ch == "1" {
                        ctx.fill(Path(r(origin.x + Double(col) * pixel, origin.y + Double(row) * pixel, pixel - 3, pixel - 3)),
                                 with: .color(color))
                    }
                }
            }

            switch design.style {
            case .handheld:
                ctx.fill(Path(roundedRect: r(262, 150, 500, 724), cornerRadius: 80 * k), with: .color(design.body.color))
                ctx.fill(Path(roundedRect: r(312, 205, 400, 315), cornerRadius: 36 * k), with: .color(design.body.darkened(0.18).color))
                ctx.fill(Path(roundedRect: r(352, 240, 320, 245), cornerRadius: 18 * k), with: .color(design.screen.color))
                drawFour(origin: CGPoint(x: 470, y: 290), pixel: 22, color: design.four.color)
                ctx.fill(Path(roundedRect: r(369, 595, 52, 170), cornerRadius: 12 * k), with: .color(design.dpad.color))
                ctx.fill(Path(roundedRect: r(310, 654, 170, 52), cornerRadius: 12 * k), with: .color(design.dpad.color))
                ctx.fill(Path(ellipseIn: r(590, 590, 90, 90)), with: .color(design.buttonA.color))
                ctx.fill(Path(ellipseIn: r(530, 680, 90, 90)), with: .color(design.buttonB.color))
            case .bigFour:
                ctx.fill(Path(roundedRect: r(192, 192, 640, 640), cornerRadius: 90 * k), with: .color(design.screen.color))
                drawFour(origin: CGPoint(x: 352, y: 272), pixel: 80, color: design.four.color)
            case .badge:
                ctx.fill(Path(ellipseIn: r(162, 162, 700, 700)), with: .color(design.body.color))
                ctx.fill(Path(ellipseIn: r(222, 222, 580, 580)), with: .color(design.screen.color))
                drawFour(origin: CGPoint(x: 392, y: 332), pixel: 60, color: design.four.color)
                ctx.fill(Path(ellipseIn: r(700, 640, 110, 110)), with: .color(design.buttonA.color))
                ctx.fill(Path(ellipseIn: r(214, 640, 110, 110)), with: .color(design.buttonB.color))
            }
        }
    }

    @MainActor
    func render(size: CGFloat = 1024) -> UIImage? {
        let renderer = ImageRenderer(content: IconArtwork(design: design).frame(width: size, height: size))
        renderer.scale = 1
        return renderer.uiImage
    }
}

struct IconStudioView: View {
    @State private var design = IconDesign.load()
    @State private var photoItem: PhotosPickerItem?
    @State private var message: String?
    @State private var showGuide = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    IconArtwork(design: design)
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                        .shadow(radius: 10, y: 4)
                    Spacer()
                }
                .padding(.vertical, 8)
                Picker("Style", selection: $design.style) {
                    ForEach(IconDesign.Style.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Colors") {
                ColorPicker("Background Top", selection: color(\.top))
                ColorPicker("Background Bottom", selection: color(\.bottom))
                ColorPicker("Body", selection: color(\.body))
                ColorPicker("Screen", selection: color(\.screen))
                ColorPicker("The 4", selection: color(\.four))
                ColorPicker("D-Pad", selection: color(\.dpad))
                ColorPicker("A Button", selection: color(\.buttonA))
                ColorPicker("B Button", selection: color(\.buttonB))
                Button("Surprise Me") { randomize() }
            }

            Section("Background Photo") {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(design.photo == nil ? "Add a Photo" : "Change Photo", systemImage: "photo")
                }
                if design.photo != nil {
                    VStack(alignment: .leading) {
                        Text("Darken")
                        Slider(value: $design.photoDim, in: 0...0.8)
                    }
                    Button("Remove Photo", role: .destructive) { design.photo = nil }
                }
            }

            Section {
                Button { saveToPhotos() } label: { Label("Save Icon to Photos", systemImage: "square.and.arrow.down") }
                Button { showGuide = true } label: { Label("Put It on My Home Screen", systemImage: "apps.iphone") }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } footer: {
                Text("iPhone only lets apps switch between icons that are built in. To use your own design, save it, then make a Home Screen shortcut with it — tap the button above for the steps.")
            }
        }
        .navigationTitle("Icon Studio")
        .onChange(of: design) { _, d in d.save() }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    design.photo = img.resizedForTheme(maxSide: 1024).jpegData(compressionQuality: 0.85)
                }
            }
        }
        .sheet(isPresented: $showGuide) { HomeScreenIconGuide(saveAction: saveToPhotos) }
    }

    private func color(_ keyPath: WritableKeyPath<IconDesign, ThemeColor>) -> Binding<Color> {
        Binding(get: { design[keyPath: keyPath].color }, set: { design[keyPath: keyPath] = ThemeColor($0) })
    }

    private func randomize() {
        func rnd(_ s: ClosedRange<Double> = 0.5...0.9, _ b: ClosedRange<Double> = 0.5...0.95) -> ThemeColor {
            ThemeColor(Color(hue: .random(in: 0...1), saturation: .random(in: s), brightness: .random(in: b)))
        }
        design.top = rnd(); design.bottom = rnd(0.5...0.9, 0.15...0.4)
        design.body = rnd(0...0.25, 0.85...1); design.screen = rnd(0.4...0.8, 0.6...0.9)
        design.four = rnd(0.5...0.9, 0.1...0.3); design.dpad = rnd(0...0.3, 0.1...0.3)
        design.buttonA = rnd(); design.buttonB = design.buttonA
    }

    private func saveToPhotos() {
        guard let image = IconArtwork(design: design).render() else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in message = "Allow Photos access in Settings to save the icon." }
                return
            }
            PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAsset(from: image) },
                                                   completionHandler: { ok, _ in
                Task { @MainActor in message = ok ? "Saved to Photos ✓" : "Couldn't save the icon." }
            })
        }
    }
}

struct HomeScreenIconGuide: View {
    let saveAction: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let steps = [
        ("square.and.arrow.down", "Save your icon", "Tap the button below to save your design to Photos."),
        ("square.on.square", "Open Shortcuts", "Open the Shortcuts app and tap + to make a new shortcut."),
        ("app.badge", "Add “Open App”", "Search for the Open App action, add it, and choose Emu4ios."),
        ("info.circle", "Add to Home Screen", "Tap the share button at the top, then Add to Home Screen."),
        ("photo", "Pick your icon", "Tap the small icon, choose Select Photo, and pick the icon you saved. Name it Emu4ios and tap Add."),
        ("eye.slash", "Hide the old one (optional)", "Long-press the original Emu4ios icon → Remove App → Remove from Home Screen. The app stays installed."),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(index + 1)").font(.headline).frame(width: 28, height: 28)
                            .background(Color.accentColor.opacity(0.2), in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Label(step.1, systemImage: step.0).font(.headline)
                            Text(step.2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button("Save Icon to Photos") { saveAction() }
                    Button("Open Shortcuts") {
                        if let url = URL(string: "shortcuts://create-shortcut") { UIApplication.shared.open(url) }
                    }
                }
            }
            .navigationTitle("Custom Home Screen Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
