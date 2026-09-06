import Foundation

/// A line drawn under the task list, per project.
///
/// The list is read from the agent's own transcript, which Ocarina does not own
/// and must not edit — deleting somebody's prompts out of Claude's history to
/// tidy a panel would be the worst kind of helpful. So clearing records a
/// timestamp instead, and anything asked before it stops being drawn. Ask the
/// agent something new and it appears, because it is newer than the line.
struct ClearedTasks {
    private let url: URL
    private var marks: [String: Date]

    init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL
        self.marks = Self.load(self.url)
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Ocarina", isDirectory: true)
            .appendingPathComponent("cleared-tasks.json")
    }

    func mark(for directory: URL) -> Date? {
        marks[directory.standardizedFileURL.path]
    }

    mutating func clear(_ directory: URL, at moment: Date = Date()) {
        marks[directory.standardizedFileURL.path] = moment
        save()
    }

    /// Puts a project's history back, for an undo that costs one line.
    mutating func restore(_ directory: URL) {
        marks.removeValue(forKey: directory.standardizedFileURL.path)
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard !marks.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(marks).write(to: url, options: .atomic)
    }

    private static func load(_ url: URL) -> [String: Date] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: Date].self, from: data)) ?? [:]
    }
}
