import Foundation

public enum Heat: Sendable { case nominal, fair, serious, critical }
public struct AnalysisPolicy: Equatable, Sendable {
    public let interval: Double
    public let saliencyEnabled: Bool
    public let mayCapture: Bool
    /// Fast local ROI tracking stays separate from slower detection/composition decisions.
    public var trackingInterval: Double {
        guard mayCapture else { return .infinity }
        return interval >= 1 ? 0.5 : (interval >= 0.65 ? 0.2 : 0.125)
    }
    public static func make(heat: Heat, lowPower: Bool, memoryPressure: Bool) -> Self {
        switch heat {
        case .critical: return Self(interval: .infinity, saliencyEnabled: false, mayCapture: false)
        case .serious: return Self(interval: 1.5, saliencyEnabled: false, mayCapture: true)
        case .fair: return Self(interval: lowPower || memoryPressure ? 1.2 : 0.65,
                                saliencyEnabled: !lowPower && !memoryPressure, mayCapture: true)
        case .nominal: return Self(interval: lowPower || memoryPressure ? 1.0 : 0.4,
                                   saliencyEnabled: !lowPower && !memoryPressure, mayCapture: true)
        }
    }
}

public struct FrameGate: Sendable {
    private var last = -Double.infinity
    public init() {}
    public mutating func admit(now: Double, interval: Double) -> Bool {
        guard now.isFinite, interval.isFinite, interval >= 0, now - last >= interval else { return false }
        last = now
        return true
    }
    public mutating func reset() { last = -.infinity }
}

public enum LevelMath {
    /// Gravity projected into the current screen axes; avoids Euler roll errors when aimed down.
    public static func angle(gx: Double, gy: Double, clockwiseQuarterTurns: Int) -> Double? {
        guard gx.isFinite, gy.isFinite, hypot(gx, gy) > 0.2 else { return nil }
        var x = gx, y = gy
        for _ in 0..<((clockwiseQuarterTurns % 4 + 4) % 4) { (x, y) = (-y, x) }
        var a = atan2(x, -y) * 180 / .pi
        if a > 90 { a -= 180 }; if a < -90 { a += 180 }
        return a
    }
    public static func relative(_ raw: Double, zero: Double) -> Double {
        var d = raw - zero
        while d > 90 { d -= 180 }; while d < -90 { d += 180 }
        return d
    }
}
