import Foundation

public struct Subject: Equatable, Sendable {
    /// Top-left origin, normalized to the displayed (possibly mirrored) image.
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var confidence: Double
    public init(x: Double, y: Double, width: Double, height: Double, confidence: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
        self.confidence = confidence
    }
    public var isValid: Bool {
        [x, y, width, height, confidence].allSatisfy(\.isFinite)
            && x >= 0 && y >= 0 && width > 0 && height > 0
            && x + width <= 1.001 && y + height <= 1.001 && confidence >= 0.55
    }
}

public enum Guidance: String, Sendable {
    case searching, steady, aligned, panLeft, panRight, tiltUp, tiltDown, stepBack
    public func cameraAdvice(mirrored: Bool) -> Self {
        guard mirrored else { return self }
        if self == .panLeft { return .panRight }
        if self == .panRight { return .panLeft }
        return self
    }
    public var text: String {
        switch self {
        case .searching: return "寻找清晰主体"
        case .steady: return "先稳住手机"
        case .aligned: return "构图已接近 · 可以拍摄"
        case .panLeft: return "镜头轻轻向左转"
        case .panRight: return "镜头轻轻向右转"
        case .tiltUp: return "镜头轻轻向上抬"
        case .tiltDown: return "镜头轻轻向下压"
        case .stepBack: return "主体靠近边缘 · 稍退后"
        }
    }
}

/// A deterministic heuristic, not an aesthetic model or a 3D movement estimator.
/// Debounce + smoothing + sticky thirds + an alignment dead band prevent flicker.
public struct CompositionGuide: Sendable {
    private var smooth: Subject?
    private var targetX: Double?
    private var candidate = Guidance.searching
    private var candidateSince = 0.0
    private var lastSeen = -Double.infinity
    public private(set) var displayed = Guidance.searching
    public init() {}

    public mutating func reset() { self = CompositionGuide() }

    public mutating func update(subject: Subject?, stable: Bool, now: Double) -> Guidance {
        guard now.isFinite else { return displayed }
        guard stable else {
            // Reset the target after a pan; never retain old direction during motion.
            smooth = nil; targetX = nil; displayed = .steady
            candidate = .steady; candidateSince = now
            return displayed
        }
        guard let s = subject, s.isValid else {
            if now - lastSeen > 0.9 {
                smooth = nil; targetX = nil; displayed = .searching
                candidate = .searching; candidateSince = now
            }
            return displayed
        }
        lastSeen = now
        if let old = smooth {
            let jump = hypot(s.x + s.width / 2 - old.x - old.width / 2,
                             s.y + s.height / 2 - old.y - old.height / 2)
            if jump > 0.25 { smooth = nil; targetX = nil }
        }
        if let old = smooth {
            let a = 0.35
            smooth = Subject(x: old.x + a * (s.x - old.x), y: old.y + a * (s.y - old.y),
                             width: old.width + a * (s.width - old.width),
                             height: old.height + a * (s.height - old.height), confidence: s.confidence)
        } else { smooth = s }
        guard let box = smooth else { return displayed }
        let cx = box.x + box.width / 2
        let cy = box.y + box.height / 2
        if targetX == nil { targetX = cx < 0.5 ? 1.0 / 3 : 2.0 / 3 }
        let dx = cx - (targetX ?? 0.5)
        let dy = cy - 0.42
        // A large subject is more comfortable centered than forced onto a third.
        let horizontal = box.width > 0.55 ? cx - 0.5 : dx
        let threshold = displayed == .aligned ? 0.105 : 0.065
        let next: Guidance
        if box.x < 0.025 || box.y < 0.025 || box.x + box.width > 0.975 || box.y + box.height > 0.975 {
            next = .stepBack
        } else if abs(horizontal) <= threshold && abs(dy) <= threshold {
            next = .aligned
        } else if abs(horizontal) > abs(dy) {
            // Panning right moves a stationary image subject left, towards the target.
            next = horizontal > 0 ? .panRight : .panLeft
        } else { next = dy > 0 ? .tiltDown : .tiltUp }
        if next != candidate { candidate = next; candidateSince = now }
        if now - candidateSince >= 0.45 { displayed = next }
        return displayed
    }
}
