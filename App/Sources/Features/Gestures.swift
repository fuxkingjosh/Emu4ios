import SwiftUI

/// Gestures on the game screen that trigger app actions. Fully remappable in Settings.
enum ScreenGesture: String, CaseIterable, Identifiable, Codable {
    case swipeDown, swipeUp, swipeLeft, swipeRight, twoFingerTap, threeFingerTap, longPress, doubleTap
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .swipeDown: return "Swipe down on screen"
        case .swipeUp: return "Swipe up on screen"
        case .swipeLeft: return "Swipe left on screen"
        case .swipeRight: return "Swipe right on screen"
        case .twoFingerTap: return "Two-finger tap"
        case .threeFingerTap: return "Three-finger tap"
        case .longPress: return "Long press on screen"
        case .doubleTap: return "Double tap on screen"
        }
    }
}

enum GestureAction: String, CaseIterable, Identifiable, Codable {
    case none, menu, quickSave, quickLoad, fastForward, screenshot, clip, toggleController
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none: return "Nothing"
        case .menu: return "Open Menu"
        case .quickSave: return "Quick Save"
        case .quickLoad: return "Quick Load"
        case .fastForward: return "Toggle Fast Forward"
        case .screenshot: return "Screenshot"
        case .clip: return "Save Last Clip"
        case .toggleController: return "Hide/Show Controller"
        }
    }
}

@MainActor
final class GestureSettings: ObservableObject {
    @Published var mapping: [ScreenGesture: GestureAction] {
        didSet { save() }
    }

    static let defaults: [ScreenGesture: GestureAction] = [
        .swipeDown: .quickSave, .swipeUp: .quickLoad, .swipeLeft: .none, .swipeRight: .fastForward,
        .twoFingerTap: .menu, .threeFingerTap: .screenshot, .longPress: .none, .doubleTap: .none,
    ]

    init() {
        if let data = UserDefaults.standard.data(forKey: "gestureMapping"),
           let decoded = try? JSONDecoder().decode([ScreenGesture: GestureAction].self, from: data) {
            mapping = decoded
        } else {
            mapping = Self.defaults
        }
    }

    func action(for gesture: ScreenGesture) -> GestureAction { mapping[gesture] ?? .none }

    private func save() {
        if let data = try? JSONEncoder().encode(mapping) {
            UserDefaults.standard.set(data, forKey: "gestureMapping")
        }
    }
}

/// Transparent layer over the game screen that recognizes the gestures above.
struct ScreenGestureLayer: UIViewRepresentable {
    var handler: (ScreenGesture) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(handler: handler) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let c = context.coordinator
        for (direction, gesture) in [(UISwipeGestureRecognizer.Direction.down, ScreenGesture.swipeDown),
                                     (.up, .swipeUp), (.left, .swipeLeft), (.right, .swipeRight)] {
            let swipe = UISwipeGestureRecognizer(target: c, action: #selector(Coordinator.swiped(_:)))
            swipe.direction = direction
            c.swipes[swipe] = gesture
            view.addGestureRecognizer(swipe)
        }
        let two = UITapGestureRecognizer(target: c, action: #selector(Coordinator.twoTap))
        two.numberOfTouchesRequired = 2
        view.addGestureRecognizer(two)
        let three = UITapGestureRecognizer(target: c, action: #selector(Coordinator.threeTap))
        three.numberOfTouchesRequired = 3
        view.addGestureRecognizer(three)
        let double = UITapGestureRecognizer(target: c, action: #selector(Coordinator.doubleTap))
        double.numberOfTapsRequired = 2
        view.addGestureRecognizer(double)
        let long = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.longPress(_:)))
        long.minimumPressDuration = 0.6
        view.addGestureRecognizer(long)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.handler = handler
    }

    final class Coordinator: NSObject {
        var handler: (ScreenGesture) -> Void
        var swipes: [UISwipeGestureRecognizer: ScreenGesture] = [:]
        init(handler: @escaping (ScreenGesture) -> Void) { self.handler = handler }

        @objc func swiped(_ g: UISwipeGestureRecognizer) { if let gesture = swipes[g] { handler(gesture) } }
        @objc func twoTap() { handler(.twoFingerTap) }
        @objc func threeTap() { handler(.threeFingerTap) }
        @objc func doubleTap() { handler(.doubleTap) }
        @objc func longPress(_ g: UILongPressGestureRecognizer) { if g.state == .began { handler(.longPress) } }
    }
}
