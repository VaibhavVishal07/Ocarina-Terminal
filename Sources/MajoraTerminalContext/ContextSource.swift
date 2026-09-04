import Foundation

/// Where a tab's title came from.
///
/// The raw values encode the priority chain from the design doc: a higher
/// value outranks a lower one, and `manual` outranks everything.
public enum ContextSource: Int, Sendable, Codable, CaseIterable, Comparable {
    case shell = 1
    case project = 2
    case foregroundCommand = 3
    case llmSession = 4
    case manual = 5

    public static func < (lhs: ContextSource, rhs: ContextSource) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
