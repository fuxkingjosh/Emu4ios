import SwiftUI
import UIKit

/// TV play: when an AirPlay TV or USB-C/HDMI display is connected, the game fills the big screen
/// and the iPhone becomes the controller.
@MainActor
final class ExternalDisplay: ObservableObject {
    static let shared = ExternalDisplay()

    /// True while a TV/monitor scene is attached.
    @Published fileprivate(set) var connected = false
    /// What the TV shows: the running game (frame + system + screen style), or the Emu4ios logo.
    @Published var game: (frame: FrameBuffer, system: GameSystem, style: ScreenStyle)?

    var enabled: Bool { UserDefaults.standard.object(forKey: "tvMode") as? Bool ?? true }
}

/// Scene delegate for the external display role (declared in Info.plist).
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: ExternalDisplayView())
        window.isHidden = false
        self.window = window
        Task { @MainActor in ExternalDisplay.shared.connected = ExternalDisplay.shared.enabled }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window = nil
        Task { @MainActor in ExternalDisplay.shared.connected = false }
    }
}

struct ExternalDisplayView: View {
    @ObservedObject var display = ExternalDisplay.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if display.enabled, let game = display.game {
                StyledGameScreen(frame: game.frame, system: game.system, style: game.style)
                    .padding(24)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 90)).foregroundStyle(.purple)
                    Text("Emu4ios").font(.system(size: 54, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    Text("Start a game on your iPhone to play it here").font(.title3).foregroundStyle(.gray)
                }
            }
        }
    }
}
