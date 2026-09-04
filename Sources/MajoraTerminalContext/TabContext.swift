import Foundation

/// Naming state for one tab. Lives beside the PTY, never inside it.
public struct TabContext: Sendable, Equatable {
    public var tabID: UUID

    /// Set by the user. Wins over everything and freezes automatic naming.
    public var manualTitle: String?
    /// Most recent title accepted from a provider.
    public var generatedTitle: String?
    /// Fallback used before any provider has spoken (project or shell name).
    public var fallbackTitle: String

    public var processName: String?
    public var activeTask: String?
    public var projectName: String?
    public var workingDirectory: URL?

    public var contextSource: ContextSource
    public var contextConfidence: Double
    public var lastContextUpdate: Date
    public var isAutoNamingEnabled: Bool

    public init(
        tabID: UUID = UUID(),
        fallbackTitle: String = "Terminal",
        manualTitle: String? = nil,
        generatedTitle: String? = nil,
        processName: String? = nil,
        activeTask: String? = nil,
        projectName: String? = nil,
        workingDirectory: URL? = nil,
        contextSource: ContextSource = .shell,
        contextConfidence: Double = 0,
        lastContextUpdate: Date = .distantPast,
        isAutoNamingEnabled: Bool = true
    ) {
        self.tabID = tabID
        self.fallbackTitle = fallbackTitle
        self.manualTitle = manualTitle
        self.generatedTitle = generatedTitle
        self.processName = processName
        self.activeTask = activeTask
        self.projectName = projectName
        self.workingDirectory = workingDirectory
        self.contextSource = contextSource
        self.contextConfidence = contextConfidence
        self.lastContextUpdate = lastContextUpdate
        self.isAutoNamingEnabled = isAutoNamingEnabled
    }

    /// What the tab strip renders.
    public var displayTitle: String {
        manualTitle ?? generatedTitle ?? fallbackTitle
    }

    /// Secondary line for hover and the command palette, e.g.
    /// `Claude Code · ~/Projects/checkout`.
    public var subtitle: String? {
        var parts: [String] = []
        if let processName { parts.append(processName) }
        if let workingDirectory { parts.append(Self.abbreviate(workingDirectory)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The user renamed the tab by hand: auto naming stops until re-enabled.
    public mutating func applyManualTitle(_ title: String?) {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            manualTitle = trimmed
            contextSource = .manual
            contextConfidence = 1
            isAutoNamingEnabled = false
        } else {
            manualTitle = nil
        }
    }

    /// Hand the tab back to automatic naming.
    public mutating func resumeAutomaticNaming() {
        manualTitle = nil
        isAutoNamingEnabled = true
        // Let the next observation win outright rather than fighting the
        // confidence of whatever was current before the manual rename.
        contextConfidence = 0
        contextSource = .shell
        lastContextUpdate = .distantPast
    }

    static func abbreviate(_ url: URL) -> String {
        let path = url.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
