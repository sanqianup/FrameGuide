import Foundation

public struct LiveScene: Equatable, Sendable {
    public let lens: String
    public let rotation: Int
    public let epoch: UInt64
    public init(lens: String, rotation: Int, epoch: UInt64) {
        self.lens = lens; self.rotation = rotation; self.epoch = epoch
    }
}

/// Pure state machine shared by the live UI and tests. No image or credential is stored here.
public struct LiveRequestGate: Sendable {
    public enum Phase: Equatable, Sendable { case idle, sampling, confirming, requesting }
    public struct Ticket: Equatable, Sendable {
        public let id: UUID
        public let scene: LiveScene
        public let created: Double
    }
    public private(set) var phase = Phase.idle
    public private(set) var ticket: Ticket?
    public private(set) var scene = LiveScene(lens: "", rotation: 90, epoch: 0)
    private var lastRequest = -Double.infinity
    private var lastSample = -Double.infinity
    public let cooldown = 8.0
    public init() {}
    public mutating func invalidate(lens: String, rotation: Int) {
        scene = LiveScene(lens: lens, rotation: rotation, epoch: scene.epoch &+ 1)
        phase = .idle; ticket = nil // retain cooldown across cancel, rotation and lens changes
    }
    public func remainingCooldown(now: Double) -> Double { max(0, cooldown - (now - lastRequest)) }
    public mutating func begin(now: Double, eligible: Bool) -> Ticket? {
        guard eligible, now.isFinite, phase == .idle, !scene.lens.isEmpty,
              now - lastSample >= 1.5, remainingCooldown(now: now) == 0 else { return nil }
        lastSample = now
        let value = Ticket(id: UUID(), scene: scene, created: now)
        ticket = value; phase = .sampling; return value
    }
    public mutating func sampled(_ value: Ticket, now: Double) -> Bool {
        guard ticket == value, scene == value.scene, phase == .sampling,
              now.isFinite, now >= value.created, now - value.created <= 3 else { return false }
        phase = .confirming; return true
    }
    public mutating func confirm(_ value: Ticket, now: Double, eligible: Bool) -> Bool {
        guard eligible, ticket == value, scene == value.scene, phase == .confirming,
              now.isFinite, now >= value.created, now - value.created <= 15,
              remainingCooldown(now: now) == 0 else { return false }
        lastRequest = now; phase = .requesting; return true
    }
    public func accepts(_ value: Ticket, now: Double) -> Bool {
        phase == .requesting && ticket == value && scene == value.scene
            && now.isFinite && now >= value.created && now - value.created <= 30
    }
    public mutating func finish(_ value: Ticket) {
        guard ticket == value else { return }
        ticket = nil; phase = .idle
    }
}

/// Coarse luminance change detector; a safety invalidator, not semantic scene understanding.
public struct SceneFingerprint: Sendable {
    private var reference: [Double]?
    public init() {}
    public mutating func reset() { reference = nil }
    public mutating func changed(_ samples: [Double]) -> Bool {
        guard samples.count == 64, samples.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return false }
        guard let old = reference else { reference = samples; return false }
        let difference = zip(old, samples).map { pair in abs(pair.0 - pair.1) }.reduce(0, +) / 64
        if difference > 0.12 { reference = samples; return true }
        return false // compare against a fixed reference, so gradual changes still invalidate
    }
}
