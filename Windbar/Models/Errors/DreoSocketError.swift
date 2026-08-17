import Foundation

enum DreoSocketError: Error, Equatable, Sendable {
    case notConnected
    case ackTimeout
    /// The fan received the command and refused it, e.g. a value outside the
    /// range that model accepts. Distinct from a timeout on purpose: the fan
    /// is plainly reachable, so retrying sends the same rejected value again
    /// and telling the user to check their connection would be a lie.
    case rejected(code: Int?, message: String?)

    /// Whether sending the identical command again could plausibly work.
    var isRetryable: Bool {
        if case .rejected = self { return false }
        return true
    }
}
