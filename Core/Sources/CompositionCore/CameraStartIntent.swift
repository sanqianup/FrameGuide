/// Serial-queue lifecycle intent. Permission callbacks cannot restart a stopped/background camera.
public struct CameraStartIntent: Sendable {
    public private(set) var wantsRunning = false
    public private(set) var authorizationPending = false
    public init() {}
    public mutating func start(needsPermission: Bool) -> Bool {
        wantsRunning = true
        guard needsPermission, !authorizationPending else { return false }
        authorizationPending = true; return true
    }
    public mutating func stop() { wantsRunning = false }
    public mutating func resolved(granted: Bool) -> Bool {
        authorizationPending = false
        if !granted { wantsRunning = false }
        return granted && wantsRunning
    }
}
