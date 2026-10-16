import Foundation

public enum LocalLook: String, CaseIterable, Sendable, Identifiable {
    case natural, softPortrait, clearScene
    public var id: String { rawValue }
    public var title: String {
        switch self { case .natural: return "自然"; case .softPortrait: return "柔和人像"; case .clearScene: return "清透景物" }
    }
    public var recipe: ToneRecipe {
        switch self {
        case .natural: return .natural
        case .softPortrait: return ToneRecipe(exposureEV: 0.10, saturation: 0.98, warmth: 0.035, contrast: 0.97)
        case .clearScene: return ToneRecipe(exposureEV: 0.04, saturation: 1.08, warmth: -0.02, contrast: 1.04)
        }
    }
    public static func suggest(person: Bool, luminance: Double) -> Self {
        if person { return .softPortrait }
        return luminance.isFinite && luminance > 0.28 ? .clearScene : .natural
    }
}

public enum FrameDirection: Equatable, Sendable {
    case left, right, up, down, hold
    /// Refers to screen content, never inferred 3D camera translation.
    public var text: String {
        switch self {
        case .left: return "让主体在画面中向左靠近目标"
        case .right: return "让主体在画面中向右靠近目标"
        case .up: return "让主体在画面中向上靠近目标"
        case .down: return "让主体在画面中向下靠近目标"
        case .hold: return "画面位置接近，保持稳定"
        }
    }
}

public struct GuidedSnapshot: Equatable, Sendable {
    public let target: Subject
    public let direction: FrameDirection
    public let aligned: Bool
    /// Relative digital crop suggestion; not a physical focal length or subject distance.
    public let relativeZoom: Double?
    public let sizeText: String
}

public enum SubjectSelection {
    public static func seed(x: Double, y: Double, candidates: [Subject]) -> Subject? {
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else { return nil }
        if let hit = candidates.filter({ $0.isValid && x >= $0.x && x <= $0.x + $0.width
            && y >= $0.y && y <= $0.y + $0.height }).min(by: { $0.width * $0.height < $1.width * $1.height }) { return hit }
        return Subject(x: min(0.78, max(0, x - 0.11)), y: min(0.72, max(0, y - 0.14)),
                       width: 0.22, height: 0.28, confidence: 1)
    }
}

/// Wall-clock freshness at the UI handoff; a late callback cannot renew its own lifetime.
public struct TrackingFreshness: Sendable {
    private var capturedAt: Double?
    public init() {}
    @discardableResult public mutating func accept(captured: Double, now: Double) -> Bool {
        guard captured.isFinite, now.isFinite, captured <= now, now - captured <= 1.2,
              capturedAt == nil || captured >= capturedAt! else { return false }
        capturedAt = captured; return true
    }
    public func expired(now: Double) -> Bool {
        guard now.isFinite, let capturedAt, now >= capturedAt else { return true }
        return now - capturedAt > 1.2
    }
}

public enum DigitalZoom {
    public static func requested(current: Double, factor: Double, minimum: Double, maximum: Double) -> Double? {
        guard [current, factor, minimum, maximum].allSatisfy(\.isFinite), current > 0,
              (1.0 / 3...1.8).contains(factor), minimum > 0, maximum >= minimum else { return nil }
        return max(minimum, min(max(minimum, min(3, maximum)), current * factor))
    }
}

/// Sticky screen-space target. No generative model, depth, or photographer score.
public struct GuidedComposition: Sendable {
    public private(set) var target: Subject?
    private var closeSince: Double?
    private var lastTime: Double?
    private var reached = false
    public init() {}
    public mutating func reset() { self = Self() }
    public mutating func begin(_ subject: Subject) {
        reset()
        guard subject.isValid else { return }
        let scale = subject.height < 0.30 ? min(1.8, 0.36 / subject.height) : 1
        let width = min(0.72, subject.width * scale), height = min(0.76, subject.height * scale)
        let cx = width > 0.5 ? 0.5 : (subject.x + subject.width / 2 < 0.5 ? 1.0 / 3 : 2.0 / 3)
        let cy = height > 0.65 ? 0.5 : 0.42
        target = Subject(x: min(0.94 - width, max(0.06, cx - width / 2)),
                         y: min(0.94 - height, max(0.06, cy - height / 2)),
                         width: width, height: height, confidence: 1)
    }
    public mutating func update(_ subject: Subject?, stable: Bool, now: Double) -> GuidedSnapshot? {
        guard stable, now.isFinite, let subject, subject.isValid, subject.confidence >= 0.65,
              let target else { reset(); return nil }
        if let lastTime, now < lastTime || now - lastTime > 2 { closeSince = nil; reached = false }
        lastTime = now
        let dx = subject.x + subject.width / 2 - target.x - target.width / 2
        let dy = subject.y + subject.height / 2 - target.y - target.height / 2
        let factor = min(target.width / subject.width, target.height / subject.height)
        let threshold = reached ? 0.075 : 0.045
        let positionClose = abs(dx) <= threshold && abs(dy) <= threshold
        let sizeClose = (0.82...1.22).contains(factor)
        if positionClose && sizeClose {
            if closeSince == nil { closeSince = now }
            reached = now - (closeSince ?? now) >= 0.65
        } else { closeSince = nil; reached = false }
        let direction: FrameDirection = positionClose ? .hold :
            (abs(dx) > abs(dy) ? (dx > 0 ? .left : .right) : (dy > 0 ? .up : .down))
        let zoom = factor > 1.22 && positionClose ? min(1.8, factor) : nil
        let sizeText = factor > 1.22 ? "主体偏小 · 可手动放大取景" :
            (factor < 0.82 ? "主体偏大 · 可手动缩小取景或重新选主体" : "主体大小接近目标")
        return GuidedSnapshot(target: target, direction: direction, aligned: reached,
                              relativeZoom: zoom, sizeText: sizeText)
    }
}
