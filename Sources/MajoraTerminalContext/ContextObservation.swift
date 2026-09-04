import Foundation

/// A single provider's reading of what a terminal is doing.
///
/// Observations are proposals, not decisions. `TabNamingEngine` decides whether
/// one is strong enough to replace the title a tab already carries.
public struct ContextObservation: Sendable, Equatable {
    /// Title-cased, already trimmed to a scannable length.
    public var title: String
    /// The underlying task text, kept for tooltips and the command palette.
    public var activeTask: String?
    public var source: ContextSource
    /// 0...1. Providers should be conservative; the engine treats confidence as
    /// the cost of overwriting a title the user may already have memorised.
    public var confidence: Double
    public var processName: String?
    public var projectName: String?
    public var workingDirectory: URL?

    public init(
        title: String,
        activeTask: String? = nil,
        source: ContextSource,
        confidence: Double,
        processName: String? = nil,
        projectName: String? = nil,
        workingDirectory: URL? = nil
    ) {
        self.title = title
        self.activeTask = activeTask
        self.source = source
        self.confidence = min(max(confidence, 0), 1)
        self.processName = processName
        self.projectName = projectName
        self.workingDirectory = workingDirectory
    }
}
