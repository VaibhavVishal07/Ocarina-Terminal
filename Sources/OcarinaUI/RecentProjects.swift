import Foundation
import OcarinaTerminalContext

/// A project folder Ocarina has seen you work in.
public struct RecentProject: Codable, Sendable, Identifiable, Equatable {
    public let path: String
    public var lastOpened: Date
    /// The agent that was in front of the terminal here, if one was — the
    /// executable name, `claude` or `codex`, not a display name.
    ///
    /// Recorded and shown, never acted on. The landing screen opens a terminal
    /// in the folder and stops there; starting an agent because you started one
    /// last time is the app deciding what you came to do.
    public var agent: String?

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }

    /// What the folder is called, tidied the way a tab's fallback name is, so
    /// a project reads the same here as it does in the sidebar.
    public var name: String {
        let leaf = url.lastPathComponent
        return TitleFormatter.humanize(leaf) ?? leaf
    }

    /// The path with the home directory folded back to a tilde — the form
    /// people recognise their own folders in, and short enough for a row.
    public var shortPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

/// The folders you keep coming back to, so a new window can offer them.
///
/// ## Where the folders come from
///
/// Not from anything you are asked to do. The shell reports where it is on
/// every prompt — see `ShellIntegration` — and a directory that is not your
/// home is a project you are working in. So the list builds itself out of
/// ordinary use, which is the only way a "recent" list is ever right: one you
/// have to curate is one that goes stale the week you stop curating it.
///
/// ## What is left out
///
/// The home directory, and the root. A terminal opens in your home when it has
/// nowhere better to be, so recording it would put the one folder you did not
/// choose at the top of a list of folders you did. A folder that has since been
/// deleted is dropped on the way out rather than on the way in — projects move
/// and come back, and forgetting one the moment it is unmounted would lose it
/// for good.
struct RecentProjects {
    private let url: URL
    private var projects: [String: RecentProject]

    /// How many the landing screen can hold without becoming a file browser.
    static let shown = 5

    init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL
        self.projects = Self.load(self.url)
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Ocarina", isDirectory: true)
            .appendingPathComponent("recent-projects.json")
    }

    /// Whether a directory is worth remembering at all.
    static func isProject(_ directory: URL) -> Bool {
        let path = directory.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        return path != home && path != "/" && !path.isEmpty
    }

    /// The most recent first, and only ones that are still there.
    ///
    /// The check is a `stat` per row on a list of five, run when a window has
    /// no tabs in it — which is the one moment in this app where there is
    /// nothing else happening.
    func recent(limit: Int = shown) -> [RecentProject] {
        projects.values
            .sorted { $0.lastOpened > $1.lastOpened }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .prefix(limit)
            .map { $0 }
    }

    /// Records a visit. An agent name of nil leaves whatever was known before:
    /// walking through a project in a plain shell is not evidence that you have
    /// stopped using Claude there.
    mutating func note(_ directory: URL, agent: String? = nil) {
        guard Self.isProject(directory) else { return }
        let path = directory.standardizedFileURL.path
        var project = projects[path] ?? RecentProject(path: path, lastOpened: .distantPast, agent: nil)
        project.lastOpened = Date()
        if let agent { project.agent = agent }
        projects[path] = project
        save()
    }

    mutating func forget(_ directory: URL) {
        projects.removeValue(forKey: directory.standardizedFileURL.path)
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard !projects.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(projects).write(to: url, options: .atomic)
    }

    private static func load(_ url: URL) -> [String: RecentProject] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: RecentProject].self, from: data)) ?? [:]
    }
}
