import Foundation

/// A command somebody would otherwise have to find on a website.
///
/// The trip to a browser is the thing this removes. Installing an agent meant
/// opening docs, copying a line you cannot read, coming back, pasting, and
/// hoping — and every step of that is a place to get lost or to paste the wrong
/// thing.
public struct Recipe: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    /// One line, in the user's terms, about what the thing *is*.
    public let blurb: String
    public let command: String
    /// What the command does, in plain language. Shown before it runs, every
    /// time, because `curl … | bash` is exactly the pattern a beginner should
    /// never learn to trust on sight.
    public let explain: String
    /// Run afterwards to say whether it worked.
    public let verify: String?
    /// Where the command came from. Required, so a stale recipe has somewhere
    /// to be checked against.
    public let docs: String
    /// When a human last checked `command` against `docs`. Required for the
    /// same reason.
    public let lastVerified: String
    public let alternatives: [Alternative]?

    public struct Alternative: Codable, Sendable, Equatable {
        public let label: String
        public let command: String
    }
}

/// Recipes under a heading that says what you are trying to do, rather than
/// what the tool is called. Someone who does not know the word "CLI" can still
/// find "Install an AI coding agent".
public struct RecipeGroup: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let items: [Recipe]
}

public enum RecipeCatalog {
    /// Bundled groups, then anything the user has written.
    public static func load() -> [RecipeGroup] {
        bundled() + userAuthored()
    }

    public static var userDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ocarina/recipes", isDirectory: true)
    }

    static func bundled() -> [RecipeGroup] {
        let urls = Bundle.module.urls(
            forResourcesWithExtension: "json",
            subdirectory: "Recipes"
        ) ?? []
        return decode(urls.sorted { $0.lastPathComponent < $1.lastPathComponent })
    }

    static func userAuthored() -> [RecipeGroup] {
        guard let names = try? FileManager.default
            .contentsOfDirectory(atPath: userDirectory.path) else { return [] }
        return decode(names.filter { $0.hasSuffix(".json") }
            .sorted()
            .map { userDirectory.appendingPathComponent($0) })
    }

    private static func decode(_ urls: [URL]) -> [RecipeGroup] {
        let decoder = JSONDecoder()
        return urls.flatMap { url -> [RecipeGroup] in
            guard let data = try? Data(contentsOf: url),
                  let groups = try? decoder.decode([RecipeGroup].self, from: data)
            else { return [] }
            return groups
        }
    }
}
