import Foundation

/// A tab that outlives the app.
///
/// Only three things are worth keeping, and none of them is the session: a pty
/// cannot be frozen and thawed, and pretending otherwise — replaying
/// scrollback, re-running the last command — would be a lie about what came
/// back. What survives is the answer to "where was I": the directory, and the
/// name the tab had earned there.
public struct PinnedTab: Codable, Identifiable, Equatable {
    public let id: UUID
    public var title: String
    /// Stored as a path rather than a `URL` so the file stays readable, and so a
    /// directory that has since been deleted is a string to fall back from
    /// rather than a decode failure that loses every other pin with it.
    public var directoryPath: String

    public var directory: URL { URL(fileURLWithPath: directoryPath) }
}

/// Injectable, like `SleepGuard`, so a test can pin tabs without writing over
/// the pins of whoever is running the test.
public struct PinnedTabStore {
    let url: URL

    public init(url: URL? = nil) { self.url = url ?? Self.defaultURL }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Ocarina", isDirectory: true)
            .appendingPathComponent("pinned-tabs.json")
    }

    func load() -> [PinnedTab] {
        guard let data = try? Data(contentsOf: url),
              let pins = try? JSONDecoder().decode([PinnedTab].self, from: data)
        else { return [] }
        return pins
    }

    func save(_ pins: [PinnedTab]) {
        let target = url
        try? FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard !pins.isEmpty else {
            try? FileManager.default.removeItem(at: target)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(pins).write(to: target, options: .atomic)
    }
}
