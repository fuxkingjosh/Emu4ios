import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Drag buttons to move them, drag the corner handle to resize, tap to restyle.
struct LayoutEditorView: View {
    let system: GameSystem
    private let themeID: String

    @EnvironmentObject var themes: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var skin: ControllerSkin
    @State private var background: BackgroundStyle
    @State private var screenStyle: ScreenStyle
    @State private var landscape = false
    @State private var selectedID: String?
    @State private var showInspector = false
    @State private var showControllerSettings = false
    @State private var dragOrigin: NormRect?
    @State private var snap = true
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var pickedPhoto: PhotosPickerItem?

    private static let screenID = "__screen__"

    init(theme: Theme, system: GameSystem) {
        self.system = system
        themeID = theme.id
        _skin = State(initialValue: theme.controller(for: system))
        _background = State(initialValue: theme.background)
        _screenStyle = State(initialValue: theme.screen)
    }

    private var layout: ControllerLayout {
        get { skin.layout(landscape: landscape) }
    }

    private func updateLayout(_ change: (inout ControllerLayout) -> Void) {
        if landscape { change(&skin.landscape) } else { change(&skin.portrait) }
    }

    private var selectedIndex: Int? { layout.buttons.firstIndex { $0.id == selectedID } }
    private var selectedDecorationIndex: Int? { layout.decorations.firstIndex { $0.id == selectedID } }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let canvas = canvasSize(in: geo.size)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    editorCanvas(size: canvas)
                        .frame(width: canvas.width, height: canvas.height)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.15)))
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 8)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("\(system.shortName) Controller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhoto, matching: .images)
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: AnimatedImage.pickableTypes) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) { addDecoration(data) }
            }
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { addDecoration(data) }
                    pickedPhoto = nil
                }
            }
            .sheet(isPresented: $showInspector) {
                if let d = selectedDecorationIndex {
                    DecorationInspector(decoration: Binding(
                        get: { layout.decorations.indices.contains(d) ? layout.decorations[d] : Decoration(imageData: Data(), frame: NormRect(x: 0, y: 0, w: 0.1, h: 0.1)) },
                        set: { value in updateLayout { if $0.decorations.indices.contains(d) { $0.decorations[d] = value } } }),
                        delete: { deleteSelected() },
                        moveLayer: { forward in moveDecoration(forward: forward) })
                    .presentationDetents([.medium])
                } else if let i = selectedIndex {
                    ButtonInspector(spec: Binding(
                        get: { layout.buttons.indices.contains(i) ? layout.buttons[i] : layout.buttons[0] },
                        set: { value in updateLayout { if $0.buttons.indices.contains(i) { $0.buttons[i] = value } } }),
                        applyToAll: { style in applyStyleToAll(from: style) },
                        delete: { deleteSelected() })
                    .presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: $showControllerSettings) {
                ControllerSettingsSheet(skin: $skin, landscape: landscape, onReset: resetLayout)
                    .presentationDetents([.medium])
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Canvas

    /// The preview keeps the real phone's proportions so the layout matches what you'll get in game.
    private func canvasSize(in available: CGSize) -> CGSize {
        let screen = UIScreen.main.bounds.size
        let long = max(screen.width, screen.height), short = min(screen.width, screen.height)
        let aspect = landscape ? long / short : short / long
        let height = min(available.height - 20, (available.width - 8) / aspect)
        return CGSize(width: height * aspect, height: height)
    }

    private func editorCanvas(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ThemeBackground(style: background, paused: true)
            if layout.deckColor.components.a > 0 {
                layout.deckColor.color
            }
            screenPlaceholder(size: size)
            ForEach(layout.decorations.filter { !$0.aboveButtons }) { deco in
                decorationHandle(deco, size: size)
            }
            ForEach(layout.buttons) { spec in
                buttonHandle(spec, size: size)
            }
            ForEach(layout.decorations.filter(\.aboveButtons)) { deco in
                decorationHandle(deco, size: size)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedID = nil }
    }

    private func screenPlaceholder(size: CGSize) -> some View {
        let rect = layout.screen.rect(in: size)
        let selected = selectedID == Self.screenID
        return ZStack {
            RoundedRectangle(cornerRadius: screenStyle.cornerRadius)
                .fill(Color.white.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: screenStyle.cornerRadius)
                    .strokeBorder(selected ? Color.yellow : Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            VStack(spacing: 4) {
                Image(systemName: "rectangle.inset.filled").font(.title2)
                Text("Game Screen").font(.caption.bold())
            }
            .foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: rect.width, height: rect.height)
        .overlay(alignment: .bottomTrailing) { if selected { resizeHandle(id: Self.screenID, size: size) } }
        .offset(x: rect.minX, y: rect.minY)
        .gesture(moveGesture(id: Self.screenID, size: size))
        .onTapGesture { selectedID = Self.screenID }
    }

    private func buttonHandle(_ spec: ButtonSpec, size: CGSize) -> some View {
        let rect = spec.frame.rect(in: size)
        let selected = selectedID == spec.id
        return Canvas { ctx, canvasSize in
            ctx.withCGContext { cg in
                UIGraphicsPushContext(cg)
                ButtonRenderer.draw(spec, in: CGRect(origin: .zero, size: canvasSize), pressedMask: selected ? 0 : nil, context: cg,
                                    scale: size.width / (landscape ? max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
                                                                   : min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)))
                UIGraphicsPopContext()
            }
        }
        .opacity(spec.hidden ? 0.25 : 1)
        .frame(width: rect.width, height: rect.height)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(selected ? Color.yellow : Color.clear, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
        )
        .overlay(alignment: .bottomTrailing) { if selected { resizeHandle(id: spec.id, size: size) } }
        .contentShape(Rectangle())
        .offset(x: rect.minX, y: rect.minY)
        .gesture(moveGesture(id: spec.id, size: size))
        .onTapGesture(count: 2) { selectedID = spec.id; showInspector = true }
        .onTapGesture { selectedID = spec.id }
    }

    private func decorationHandle(_ deco: Decoration, size: CGSize) -> some View {
        let rect = deco.frame.rect(in: size)
        let selected = selectedID == deco.id
        return AnimatedImageView(data: deco.imageData)
            .frame(width: rect.width, height: rect.height)
            .clipShape(RoundedRectangle(cornerRadius: deco.cornerRadius))
            .opacity(deco.opacity)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(selected ? Color.cyan : Color.clear, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            )
            .overlay(alignment: .bottomTrailing) { if selected { resizeHandle(id: deco.id, size: size) } }
            .contentShape(Rectangle())
            .offset(x: rect.minX, y: rect.minY)
            .gesture(moveGesture(id: deco.id, size: size))
            .onTapGesture(count: 2) { selectedID = deco.id; showInspector = true }
            .onTapGesture { selectedID = deco.id }
    }

    private func resizeHandle(id: String, size: CGSize) -> some View {
        Circle()
            .fill(Color.yellow)
            .frame(width: 22, height: 22)
            .overlay(Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.black))
            .offset(x: 11, y: 11)
            .gesture(resizeGesture(id: id, size: size))
    }

    // MARK: Gestures

    private func frame(for id: String) -> NormRect? {
        if id == Self.screenID { return layout.screen }
        return layout.buttons.first { $0.id == id }?.frame ?? layout.decorations.first { $0.id == id }?.frame
    }

    private func setFrame(_ rect: NormRect, for id: String) {
        updateLayout { l in
            if id == Self.screenID { l.screen = rect }
            else if let i = l.buttons.firstIndex(where: { $0.id == id }) { l.buttons[i].frame = rect }
            else if let i = l.decorations.firstIndex(where: { $0.id == id }) { l.decorations[i].frame = rect }
        }
    }

    private func snapped(_ v: Double) -> Double { snap ? (v / 0.005).rounded() * 0.005 : v }

    private func moveGesture(id: String, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragOrigin == nil { dragOrigin = frame(for: id); selectedID = id }
                guard let origin = dragOrigin else { return }
                var r = origin
                r.x = snapped(min(max(origin.x + value.translation.width / size.width, -0.05), 1.05 - origin.w))
                r.y = snapped(min(max(origin.y + value.translation.height / size.height, -0.05), 1.05 - origin.h))
                setFrame(r, for: id)
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private func resizeGesture(id: String, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragOrigin == nil { dragOrigin = frame(for: id) }
                guard let origin = dragOrigin else { return }
                var r = origin
                r.w = snapped(max(0.04, origin.w + value.translation.width / size.width))
                r.h = snapped(max(0.02, origin.h + value.translation.height / size.height))
                // Pictures keep their shape.
                if let deco = layout.decorations.first(where: { $0.id == id }),
                   let img = AnimatedImage.image(from: deco.imageData), img.size.width > 0 {
                    let aspect = img.size.height / img.size.width
                    r.h = r.w * size.width * aspect / size.height
                }
                // Keep round buttons round unless the user has made them wide on purpose.
                if let spec = layout.buttons.first(where: { $0.id == id }), spec.shape == .circle || spec.input == .dpad {
                    let side = max(r.w * size.width, r.h * size.height)
                    r.w = side / size.width
                    r.h = side / size.height
                }
                setFrame(r, for: id)
            }
            .onEnded { _ in dragOrigin = nil }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() }.bold() }
        ToolbarItemGroup(placement: .bottomBar) {
            Picker("Orientation", selection: $landscape) {
                Image(systemName: "iphone").tag(false)
                Image(systemName: "iphone.landscape").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 110)
            Spacer()
            Menu {
                Section("Pictures & GIFs") {
                    Button { showPhotoPicker = true } label: { Label("From Photos", systemImage: "photo.on.rectangle") }
                    Button { showFilePicker = true } label: { Label("From Files (GIF, PNG…)", systemImage: "folder") }
                }
                ForEach(ControlInput.allCases.filter { $0.isAction }) { input in
                    Button(input.displayName) { addButton(input) }
                }
                Section("Game Buttons") {
                    ForEach(system.inputs.filter { $0 != .dpad }) { input in
                        Button("Extra \(input.displayName) (Turbo)") { addButton(input, turbo: true) }
                    }
                }
            } label: { Image(systemName: "plus.circle") }
            Button { showInspector = true } label: { Image(systemName: "paintbrush") }
                .disabled(selectedIndex == nil && selectedDecorationIndex == nil)
            Toggle(isOn: $snap) { Image(systemName: "grid") }.toggleStyle(.button)
            Button { showControllerSettings = true } label: { Image(systemName: "slider.horizontal.3") }
        }
    }

    // MARK: Actions

    private func addButton(_ input: ControlInput, turbo: Bool = false) {
        let template = layout.buttons.first { !$0.input.isAction && $0.input != .dpad } ?? ButtonSpec(input: .a, frame: NormRect(x: 0, y: 0, w: 0.1, h: 0.05))
        var spec = template
        spec.id = UUID().uuidString
        spec.input = input
        spec.label = turbo ? "T\(input.defaultLabel)" : nil
        spec.turbo = turbo
        spec.shape = input.isAction ? .pill : template.shape
        spec.frame = NormRect(x: 0.42, y: landscape ? 0.45 : 0.75, w: landscape ? 0.08 : 0.16, h: landscape ? 0.12 : 0.05)
        spec.labelSize = input.isAction ? 13 : template.labelSize
        updateLayout { $0.buttons.append(spec) }
        selectedID = spec.id
    }

    private func addDecoration(_ raw: Data) {
        guard let image = AnimatedImage.image(from: raw) else { return }
        let data = AnimatedImage.prepareForTheme(raw)
        let width = landscape ? 0.18 : 0.3
        let aspect = image.size.height / max(image.size.width, 1)
        let canvasAspect = landscape ? 0.46 : 2.17 // height / width of the phone in this orientation
        let height = width * aspect / canvasAspect
        let deco = Decoration(imageData: data,
                              frame: NormRect(x: 0.5 - width / 2, y: landscape ? 0.4 : 0.62, w: width, h: height))
        updateLayout { $0.decorations.append(deco) }
        selectedID = deco.id
    }

    private func moveDecoration(forward: Bool) {
        guard let id = selectedID else { return }
        updateLayout { l in
            guard let i = l.decorations.firstIndex(where: { $0.id == id }) else { return }
            let target = forward ? min(i + 1, l.decorations.count - 1) : max(i - 1, 0)
            l.decorations.swapAt(i, target)
        }
    }

    private func deleteSelected() {
        guard let id = selectedID else { return }
        if layout.decorations.contains(where: { $0.id == id }) {
            updateLayout { $0.decorations.removeAll { $0.id == id } }
            showInspector = false
            selectedID = nil
            return
        }
        updateLayout { l in
            guard let i = l.buttons.firstIndex(where: { $0.id == id }) else { return }
            // Game buttons are hidden instead of deleted so the system always has every input.
            let isOnlyOne = l.buttons.filter { $0.input == l.buttons[i].input }.count == 1
            if !l.buttons[i].input.isAction && isOnlyOne {
                l.buttons[i].hidden = true
            } else {
                l.buttons.remove(at: i)
            }
        }
        showInspector = false
        selectedID = nil
    }

    private func applyStyleToAll(from style: ButtonSpec) {
        skin = skin.restyled { b in
            b.fill = style.fill
            b.pressedFill = style.pressedFill
            b.border = style.border
            b.borderWidth = style.borderWidth
            b.labelColor = style.labelColor
            b.opacity = style.opacity
            b.haptic = style.haptic
            b.sound = style.sound
            if b.input != .dpad && !b.input.isAction && (style.input != .dpad) { b.shape = style.shape }
        }
    }

    private func resetLayout() {
        let fresh = ControllerSkin.standard(for: system)
        let styleSource = layout.buttons.first { $0.input == .a }
        updateLayout { l in
            l = landscape ? fresh.landscape : fresh.portrait
        }
        if let styleSource { applyStyleToAll(from: styleSource) }
    }

    private func save() {
        guard var theme = themes.theme(id: themeID) else { return }
        theme = themes.editableTheme(theme)
        theme.controllers[system.rawValue] = skin
        themes.save(theme)
    }
}

struct ButtonInspector: View {
    @Binding var spec: ButtonSpec
    let applyToAll: (ButtonSpec) -> Void
    let delete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var normalPhoto: PhotosPickerItem?
    @State private var pressedPhoto: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Canvas { ctx, size in
                            ctx.withCGContext { cg in
                                UIGraphicsPushContext(cg)
                                ButtonRenderer.draw(spec, in: CGRect(origin: .zero, size: size), pressedMask: nil, context: cg)
                                UIGraphicsPopContext()
                            }
                        }
                        .frame(width: spec.input == .dpad ? 120 : 90, height: spec.input == .dpad ? 120 : (spec.shape == .pill ? 40 : 90))
                        Spacer()
                    }
                    .listRowBackground(Color.black.opacity(0.6))
                }
                Section("Look") {
                    if spec.input == .dpad {
                        Picker("D-Pad Style", selection: $spec.dpadStyle) {
                            Text("Cross").tag(DPadStyle.cross)
                            Text("Thumb Pad").tag(DPadStyle.circlePad)
                            Text("Four Buttons").tag(DPadStyle.fourButtons)
                        }
                        Toggle("Allow Diagonals", isOn: $spec.dpadDiagonals)
                    } else {
                        Picker("Shape", selection: $spec.shape) {
                            ForEach(ButtonShape.allCases) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        TextField("Label", text: Binding(get: { spec.label ?? spec.input.defaultLabel },
                                                         set: { spec.label = $0 }))
                        VStack(alignment: .leading) {
                            Text("Label Size \(Int(spec.labelSize))")
                            Slider(value: $spec.labelSize, in: 8...40, step: 1)
                        }
                        ColorPicker("Label Color", selection: color(\.labelColor))
                    }
                    ColorPicker("Fill", selection: color(\.fill))
                    ColorPicker("Pressed Fill", selection: color(\.pressedFill))
                    ColorPicker("Border", selection: color(\.border))
                    VStack(alignment: .leading) {
                        Text("Border Width \(Int(spec.borderWidth))")
                        Slider(value: $spec.borderWidth, in: 0...8, step: 0.5)
                    }
                    VStack(alignment: .leading) {
                        Text("Opacity \(Int(spec.opacity * 100))%")
                        Slider(value: $spec.opacity, in: 0.05...1)
                    }
                }
                Section {
                    PhotosPicker(selection: $normalPhoto, matching: .images) {
                        Label(spec.imageData == nil ? "Use a Picture or GIF" : "Change Picture", systemImage: "photo")
                    }
                    if spec.imageData != nil {
                        PhotosPicker(selection: $pressedPhoto, matching: .images) {
                            Label(spec.pressedImageData == nil ? "Picture While Pressed (optional)" : "Change Pressed Picture",
                                  systemImage: "hand.tap")
                        }
                        Button("Remove Pictures", role: .destructive) {
                            spec.imageData = nil
                            spec.pressedImageData = nil
                        }
                    }
                } header: {
                    Text("Picture")
                } footer: {
                    Text("Turn this button into any picture or animated GIF.")
                }
                Section("Feel") {
                    Picker("Vibration", selection: $spec.haptic) {
                        ForEach(HapticStrength.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Picker("Sound", selection: $spec.sound) {
                        ForEach(ButtonSound.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    if !spec.input.isAction && spec.input != .dpad {
                        Toggle("Turbo (rapid fire while held)", isOn: $spec.turbo)
                    }
                    Toggle("Hidden", isOn: $spec.hidden)
                }
                Section {
                    Button("Apply This Style to All Buttons") { applyToAll(spec) }
                    Button(spec.input.isAction ? "Delete Button" : "Remove Button", role: .destructive) { delete() }
                }
            }
            .navigationTitle(spec.input.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: normalPhoto) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), AnimatedImage.image(from: data) != nil {
                        spec.imageData = AnimatedImage.prepareForTheme(data, maxSide: 400)
                    }
                }
            }
            .onChange(of: pressedPhoto) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), AnimatedImage.image(from: data) != nil {
                        spec.pressedImageData = AnimatedImage.prepareForTheme(data, maxSide: 400)
                    }
                }
            }
        }
    }

    private func color(_ keyPath: WritableKeyPath<ButtonSpec, ThemeColor>) -> Binding<Color> {
        Binding(get: { spec[keyPath: keyPath].color }, set: { spec[keyPath: keyPath] = ThemeColor($0) })
    }
}

struct ControllerSettingsSheet: View {
    @Binding var skin: ControllerSkin
    let landscape: Bool
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Controller") {
                    ColorPicker("Controller Area Color", selection: Binding(
                        get: { (landscape ? skin.landscape : skin.portrait).deckColor.color },
                        set: { value in
                            if landscape { skin.landscape.deckColor = ThemeColor(value) } else { skin.portrait.deckColor = ThemeColor(value) }
                        }))
                    Toggle("Vibration", isOn: $skin.hapticsEnabled)
                    Toggle("Button Sounds", isOn: $skin.soundsEnabled)
                    Toggle("Hide When a Controller Is Connected", isOn: $skin.hideWhenControllerConnected)
                }
                Section {
                    Button("Reset \(landscape ? "Landscape" : "Portrait") Layout", role: .destructive) { onReset(); dismiss() }
                }
            }
            .navigationTitle("Controller Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct DecorationInspector: View {
    @Binding var decoration: Decoration
    let delete: () -> Void
    let moveLayer: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var replacement: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        AnimatedImageView(data: decoration.imageData).frame(width: 140, height: 100)
                        Spacer()
                    }
                    .listRowBackground(Color.black.opacity(0.6))
                }
                Section("Picture") {
                    VStack(alignment: .leading) {
                        Text("Opacity \(Int(decoration.opacity * 100))%")
                        Slider(value: $decoration.opacity, in: 0.05...1)
                    }
                    VStack(alignment: .leading) {
                        Text("Rounded Corners \(Int(decoration.cornerRadius))")
                        Slider(value: $decoration.cornerRadius, in: 0...60, step: 1)
                    }
                    Toggle("Show Above Buttons", isOn: $decoration.aboveButtons)
                    HStack {
                        Button("Send Backward") { moveLayer(false) }
                        Spacer()
                        Button("Bring Forward") { moveLayer(true) }
                    }
                    .buttonStyle(.borderless)
                    PhotosPicker(selection: $replacement, matching: .images) { Label("Replace Picture", systemImage: "photo") }
                }
                Section {
                    Button("Delete Picture", role: .destructive) { delete() }
                }
            }
            .navigationTitle("Picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: replacement) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), AnimatedImage.image(from: data) != nil {
                        decoration.imageData = AnimatedImage.prepareForTheme(data)
                    }
                }
            }
        }
    }
}
