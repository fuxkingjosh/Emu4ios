import Foundation

/// Keeps recent save states in memory so the player can rewind.
struct RewindBuffer {
    private(set) var states: [Data] = []
    let capacity: Int
    /// Capture one state every N frames.
    let interval: Int
    private var frameCounter = 0

    init(stateSize: Int, memoryBudgetMB: Int = 64, interval: Int = 10) {
        let budget = memoryBudgetMB * 1_024 * 1_024
        capacity = max(30, min(1_800, budget / max(stateSize, 1)))
        self.interval = interval
    }

    /// Seconds of gameplay that can be rewound at most (at 60 fps).
    var maxSeconds: Double { Double(capacity * interval) / 60 }

    mutating func tick(capture: () -> Data?) {
        frameCounter += 1
        guard frameCounter >= interval else { return }
        frameCounter = 0
        guard let state = capture() else { return }
        if states.count >= capacity { states.removeFirst(states.count - capacity + 1) }
        states.append(state)
    }

    mutating func pop() -> Data? {
        frameCounter = 0
        return states.popLast()
    }

    mutating func clear() {
        states.removeAll()
        frameCounter = 0
    }
}
