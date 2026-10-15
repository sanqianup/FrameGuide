import Foundation

/// Identifies a response by both request and immutable photo. No stale result can apply after exit.
public struct RequestGate: Sendable {
    public struct Ticket: Equatable, Sendable { public let request: UUID; public let photo: UUID }
    public private(set) var active: Ticket?
    public init() {}
    public mutating func begin(photo: UUID) -> Ticket? {
        guard active == nil else { return nil }
        let ticket = Ticket(request: UUID(), photo: photo); active = ticket; return ticket
    }
    public func accepts(_ ticket: Ticket, photo: UUID) -> Bool { active == ticket && ticket.photo == photo }
    public mutating func finish(_ ticket: Ticket) { if active == ticket { active = nil } }
    public mutating func cancel() { active = nil }
}
