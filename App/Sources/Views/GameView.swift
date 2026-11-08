import SwiftUI

/// Creates the play session for a game and shows it, or an error if the file can't be loaded.
struct GameContainerView: View {
    let game: Game
    @EnvironmentObject var library: GameLibrary
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var themes: ThemeStore
    @State private var session: EmulatorSession?
    @State private var failed = false
    @State private var problem: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let session {
                GameView(session: session) { quit() }
            } else if failed {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.yellow)
                    Text("This game couldn't be loaded").font(.title3.bold()).foregroundStyle(.white)
                    Text(problem ?? "The file may be damaged or not a supported game.")
                        .foregroundStyle(.gray).multilineTextAlignment(.center)
                    Button("Back to Library") { router.playing = nil }.buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                ProgressView().tint(.white)
            }
        }
        .task {
            guard session == nil else { return }
            if let reason = EmulatorCores.problem(for: game.system) {
                problem = reason
                failed = true
                return
            }
            if let s = EmulatorSession(game: game, romURL: library.romURL(for: game)) {
                session = s
                let resume = UserDefaults.standard.object(forKey: "autoResume") as? Bool ?? true
                s.start(resumeAutoSave: resume)
                LiveActivityController.shared.begin(game: game, accentHex: themes.theme(for: game).style.accent.hex)
            } else {
                failed = true
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    private func quit() {
        guard let session else { router.playing = nil; return }
        let result = session.finish()
        let accent = themes.theme(for: game).style.accent.hex
        library.recordSession(gameID: game.id, seconds: result.seconds, lastFrame: result.lastFrame, accentHex: accent)
        router.playing = nil
    }
}

struct GameView: View {
    @ObservedObject var session: EmulatorSession
    let onQuit: () -> Void

    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var library: GameLibrary
    @EnvironmentObject var gestures: GestureSettings
    @StateObject private var physical = PhysicalInput()
    @ObservedObject private var tv = ExternalDisplay.shared
    @ObservedObject private var layouts = LayoutStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var controllerHidden = false
    @State private var editingLayout = false

    private var theme: Theme { themes.theme(for: library.game(id: session.game.id) ?? session.game) }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let skin = layouts.skin(for: session.game.id) ?? theme.controller(for: session.game.system)
            let layout = skin.layout(landscape: isLandscape)
            let screenRect = layout.screen.rect(in: geo.size)
            let hideTouch = controllerHidden || (skin.hideWhenControllerConnected && physical.controllerConnected)

            ZStack(alignment: .topLeading) {
                if theme.background.showInGame && layout.screen.h <= 0.95 {
                    ThemeBackground(style: theme.background, paused: session.isMenuOpen)
                } else {
                    Color.black.ignoresSafeArea()
                }

                Group {
                    if tv.connected {
                        VStack(spacing: 8) {
                            Image(systemName: "tv").font(.system(size: 40))
                            Text("Playing on your TV").font(.headline)
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        StyledGameScreen(frame: session.loop.frame, system: session.game.system,
                                         style: screenStyle(fullScreen: layout.screen.h > 0.95),
                                         accent: theme.style.accent.color)
                    }
                }
                .frame(width: screenRect.width, height: screenRect.height)
                .offset(x: screenRect.minX, y: screenRect.minY)

                screenInputLayer(size: screenRect.size, fullScreen: layout.screen.h > 0.95)
                    .frame(width: screenRect.width, height: screenRect.height)
                    .offset(x: screenRect.minX, y: screenRect.minY)

                if session.game.system.hasKeyboard {
                    ComputerKeyboard(visible: $session.keyboardVisible,
                                     onCharacter: { session.type($0) },
                                     onKey: { code, down in session.key(code, down: down) })
                        .frame(width: 1, height: 1)
                }

                if !hideTouch {
                    ControllerOverlay(layout: layout, skin: skin, actions: ControllerActions(
                        press: { input, touch, mask, turbo in session.press(input, touch: touch, mask: mask, turbo: turbo) },
                        direction: { touch, mask in session.updateDirection(touch: touch, mask: mask) },
                        release: { input, touch in session.release(input, touch: touch) },
                        analog: { input, x, y in session.setStick(input, x: x, y: y) }))
                } else {
                    // Always leave a way into the menu.
                    Button { session.openMenu() } label: {
                        Image(systemName: "line.3.horizontal.circle.fill").font(.title).foregroundStyle(.white.opacity(0.35))
                    }
                    .position(x: geo.size.width - 34, y: geo.size.height - 34)
                }

                statusBadges
                    .position(x: geo.size.width / 2, y: max(screenRect.minY, 0) + 22)

                AchievementPopups()
                    .frame(width: geo.size.width)
                    .padding(.top, 48)

                if let toast = session.toast {
                    Text(toast)
                        .font(theme.style.font(.subheadline, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                        .position(x: geo.size.width / 2, y: screenRect.maxY - 30)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: session.toast)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $session.isMenuOpen, onDismiss: { if !editingLayout { session.closeMenu() } }) {
            PauseMenuView(session: session, theme: theme, controllerHidden: $controllerHidden,
                          onEditLayout: { editingLayout = true }, onQuit: onQuit)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $editingLayout, onDismiss: { session.closeMenu() }) {
            ThemeLayoutEditorLauncher(themeID: theme.id, system: session.game.system, gameID: session.game.id)
        }
        .onAppear {
            connectPhysicalInput()
            tv.game = (session.loop.frame, session.game.system, theme.screen)
        }
        .onDisappear { tv.game = nil }
        .background(ShakeDetector { if !session.isMenuOpen { handle(gestures.action(for: .shake)) } }.frame(width: 1, height: 1))
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.resume() } else { session.pause() }
        }
    }

    /// A full-screen picture has no frame, border or glow around it.
    private func screenStyle(fullScreen: Bool) -> ScreenStyle {
        var style = theme.screen
        if fullScreen {
            style.bezel = .none
            style.borderWidth = 0
            style.cornerRadius = 0
            style.glow = 0
        }
        return style
    }

    /// DS games use the screen as their touch screen, computers as a trackpad; everything else gets screen gestures.
    @ViewBuilder
    private func screenInputLayer(size: CGSize, fullScreen: Bool) -> some View {
        let system = session.game.system
        let picture = StyledGameScreen.pictureRect(in: size, system: system, style: screenStyle(fullScreen: fullScreen))
        switch system.screenTouch {
        case .touchScreen:
            ScreenTouchLayer(mode: .touchScreen, pictureRect: picture,
                             onTouch: { x, y, down in session.touchScreen(x: x, y: y, down: down) })
        case .mouse:
            ScreenTouchLayer(mode: .mouse, pictureRect: picture,
                             onMouseMove: { dx, dy in session.moveMouse(dx: dx, dy: dy) },
                             onMouseButtons: { l, r in session.mouseButtons(left: l, right: r) })
        case .none:
            ScreenGestureLayer { gesture in handle(gestures.action(for: gesture)) }
        }
    }

    @ViewBuilder
    private var statusBadges: some View {
        HStack(spacing: 8) {
            if session.isFastForwarding {
                badge("\(session.speedPreset.formatted())×", icon: "forward.fill")
            }
            if session.isRewinding {
                badge("Rewind", icon: "backward.fill")
            }
        }
    }

    private func badge(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private func handle(_ action: GestureAction) {
        switch action {
        case .none: break
        case .menu: session.openMenu()
        case .quickSave: session.quickSave()
        case .quickLoad: session.quickLoad()
        case .fastForward: session.toggleFastForward()
        case .screenshot: session.takeScreenshot()
        case .clip: session.saveClip()
        case .toggleController: controllerHidden.toggle()
        }
    }

    private func connectPhysicalInput() {
        physical.system = session.game.system
        physical.onButtons = { mask, port in session.setPhysicalButtons(mask, port: port) }
        physical.onStick = { stick, x, y, port in session.setStick(stick == 1 ? .rightStick : .leftStick, x: x, y: y, port: port) }
        physical.onKey = { code, down in session.key(code, down: down) }
        physical.onAction = { action in session.press(action, touch: "physical-\(action.rawValue)") }
        physical.onActionReleased = { action in session.release(action, touch: "physical-\(action.rawValue)") }
    }
}

/// Opens the controller layout editor for the theme in use, duplicating built-in themes first.
struct ThemeLayoutEditorLauncher: View {
    let themeID: String
    let system: GameSystem
    var gameID: String? = nil
    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var library: GameLibrary
    @State private var editableID: String?

    var body: some View {
        Group {
            if let id = editableID, let theme = themes.theme(id: id) {
                LayoutEditorView(theme: theme, system: system, gameID: gameID)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard editableID == nil, let theme = themes.theme(id: themeID) else { return }
            // Per-game edits don't touch the theme, so built-ins don't need copying for them.
            editableID = gameID == nil ? themes.editableTheme(theme, library: library).id : theme.id
        }
    }
}
