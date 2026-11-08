import CoreHaptics
import UIKit
import SwiftUI

/// One beat of a custom vibration pattern.
struct HapticBeat: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    /// Seconds after the previous beat ends.
    var delay: Double = 0
    var intensity: Double = 0.8
    var sharpness: Double = 0.5
    /// 0 = a single tap; longer = a buzz.
    var duration: Double = 0
}

enum HapticPreset: String, CaseIterable, Identifiable {
    case doubleTap, heartbeat, buzz, rumble, triple, ramp
    var id: String { rawValue }
    var title: String {
        switch self {
        case .doubleTap: return "Double Tap"
        case .heartbeat: return "Heartbeat"
        case .buzz: return "Short Buzz"
        case .rumble: return "Rumble"
        case .triple: return "Triple Tap"
        case .ramp: return "Power Up"
        }
    }
    var beats: [HapticBeat] {
        switch self {
        case .doubleTap: return [HapticBeat(intensity: 1, sharpness: 0.7), HapticBeat(delay: 0.07, intensity: 1, sharpness: 0.7)]
        case .heartbeat: return [HapticBeat(intensity: 1, sharpness: 0.2), HapticBeat(delay: 0.12, intensity: 0.6, sharpness: 0.2)]
        case .buzz: return [HapticBeat(intensity: 0.7, sharpness: 0.9, duration: 0.12)]
        case .rumble: return [HapticBeat(intensity: 1, sharpness: 0.05, duration: 0.25)]
        case .triple: return (0..<3).map { HapticBeat(delay: $0 == 0 ? 0 : 0.05, intensity: 0.9, sharpness: 0.8) }
        case .ramp: return (0..<4).map { HapticBeat(delay: $0 == 0 ? 0 : 0.03, intensity: 0.3 + Double($0) * 0.23, sharpness: 0.5) }
        }
    }
}

/// Plays custom vibration patterns with Core Haptics.
final class HapticPlayer {
    static let shared = HapticPlayer()
    private var engine: CHHapticEngine?
    private var cache: [[HapticBeat]: CHHapticPattern] = [:]

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.playsHapticsOnly = true
        engine?.isAutoShutdownEnabled = true
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        try? engine?.start()
    }

    func play(_ beats: [HapticBeat]) {
        guard let engine, !beats.isEmpty else { return }
        do {
            let pattern = try cache[beats] ?? makePattern(beats)
            cache[beats] = pattern
            try engine.start()
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func makePattern(_ beats: [HapticBeat]) throws -> CHHapticPattern {
        var time = 0.0
        var events: [CHHapticEvent] = []
        for beat in beats {
            time += beat.delay
            let params = [CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(beat.intensity)),
                          CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(beat.sharpness))]
            if beat.duration > 0.01 {
                events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: params, relativeTime: time, duration: beat.duration))
                time += beat.duration
            } else {
                events.append(CHHapticEvent(eventType: .hapticTransient, parameters: params, relativeTime: time))
                time += 0.01
            }
        }
        return try CHHapticPattern(events: events, parameters: [])
    }
}

/// Invisible view that becomes first responder during play so it can hear shake gestures.
struct ShakeDetector: UIViewRepresentable {
    var onShake: () -> Void

    func makeUIView(context: Context) -> ShakeView {
        let view = ShakeView()
        view.onShake = onShake
        return view
    }

    func updateUIView(_ view: ShakeView, context: Context) {
        view.onShake = onShake
        if view.window != nil, !view.isFirstResponder { view.becomeFirstResponder() }
    }

    final class ShakeView: UIView {
        var onShake: (() -> Void)?
        override var canBecomeFirstResponder: Bool { true }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { becomeFirstResponder() }
        }
        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            if motion == .motionShake { onShake?() }
            super.motionEnded(motion, with: event)
        }
    }
}
