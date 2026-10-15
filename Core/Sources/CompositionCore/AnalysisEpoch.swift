/// Admission/publication identity used by FrameAnalyzer under its state lock.
/// Every motion transition invalidates work already in flight or queued for UI delivery.
public struct AnalysisEpoch: Sendable {
    public private(set) var revision = 0
    public private(set) var enabled = false
    public private(set) var stable = false
    public init() {}
    public var ticket: Int? { enabled && stable ? revision : nil }
    public mutating func configure(enabled: Bool) {
        self.enabled = enabled
        revision &+= 1
    }
    @discardableResult
    public mutating func setStable(_ value: Bool) -> Bool {
        guard stable != value else { return false }
        stable = value
        revision &+= 1
        return true
    }
    public func accepts(_ ticket: Int) -> Bool {
        enabled && stable && ticket == revision
    }
}
