import Foundation

/// Finds the project a directory belongs to.
///
/// A tab is named after its project, and until now "project" meant the folder
/// the shell happened to be standing in. That is the same thing only at the top
/// of a repository: `cd Sources/OcarinaUI` renamed the tab to "Ocarina UI", and
/// a tab opened straight into `~/work/api/services/billing` never said `api` at
/// all. The one thing you always know about a terminal — which codebase it is
/// in — was still the thing it would not tell you.
///
/// So the walk goes up. The nearest ancestor under version control is the
/// codebase boundary and is what a person means by "which project"; a nested
/// repository is its own project, which is why it is the *nearest* and not the
/// outermost. Failing that a build manifest marks the root. Failing both, the
/// folder itself stands, which is exactly the old behaviour — so a plain
/// directory of scratch files is named the way it always was.
public enum ProjectLocator {

    /// Version control marks the codebase. Present as a directory in a normal
    /// checkout and as a *file* in a submodule or a linked worktree, so the
    /// test is existence, not directory-ness.
    static let versionControlMarkers = [".git", ".hg", ".svn", ".jj", ".bzr"]

    /// A manifest at the top of a package, for the projects that never got as
    /// far as `git init`.
    static let manifestMarkers = [
        "Package.swift", "package.json", "Cargo.toml", "go.mod", "pyproject.toml",
        "pom.xml", "build.gradle", "build.gradle.kts", "Gemfile", "composer.json",
        "CMakeLists.txt", "mix.exs", "pubspec.yaml", "flake.nix", "deno.json"
    ]

    /// Suffixes that make a directory a project on their own, for the trees
    /// whose manifest is named after the project rather than the tool.
    static let manifestSuffixes = [".xcodeproj", ".xcworkspace"]

    /// How far up to walk before giving up. A path deeper than this is not
    /// somebody's checkout, and the bound keeps a poll off a pathological tree.
    static let maximumDepth = 24

    /// The root of the project `directory` is inside, or nil where there is no
    /// project — the home directory and the root of the disk are places, not
    /// projects, and a tab in one has no project name to take.
    public static func root(
        of directory: URL,
        fileManager: FileManager = .default,
        home: URL? = nil
    ) -> URL? {
        let home = (home ?? fileManager.homeDirectoryForCurrentUser).standardizedFileURL
        var current = directory.standardizedFileURL

        // Version control first, and over the whole walk rather than level by
        // level: a `package.json` two folders down must not outrank the
        // repository that contains it.
        // Places are never candidates, only stopping points: a `.git` in your
        // home directory — which people do have — makes every terminal on the
        // machine a tab called after your username, and that is worse than no
        // name at all.
        var candidates: [URL] = []
        for _ in 0..<maximumDepth {
            if !isPlace(current, home: home) { candidates.append(current) }
            guard !isBoundary(current, home: home) else { break }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            guard parent != current else { break }
            current = parent
        }

        if let repository = candidates.first(where: {
            contains(versionControlMarkers, in: $0, fileManager: fileManager)
        }) {
            return repository
        }
        if let package = candidates.first(where: { hasManifest($0, fileManager: fileManager) }) {
            return package
        }

        // Nothing marks a root, so the folder is the project — the behaviour
        // this walk replaced, kept for the directories it was always right for.
        let start = directory.standardizedFileURL
        return isPlace(start, home: home) ? nil : start
    }

    /// The project's name, ready for a tab: the root's folder name, humanized.
    public static func projectName(
        for directory: URL,
        fileManager: FileManager = .default,
        home: URL? = nil
    ) -> String? {
        guard let root = root(of: directory, fileManager: fileManager, home: home) else { return nil }
        let component = root.lastPathComponent
        guard !component.isEmpty, component != "/" else { return nil }
        return TitleFormatter.humanize(component) ?? component
    }

    // MARK: - Tests

    /// Where the walk stops. Above your home directory is not your work.
    private static func isBoundary(_ url: URL, home: URL) -> Bool {
        url.path == home.path || url.path == "/"
    }

    /// A place rather than a project: home, the root of the disk, or nothing.
    private static func isPlace(_ url: URL, home: URL) -> Bool {
        let path = url.path
        return path.isEmpty || path == "/" || path == home.path
    }

    private static func contains(_ markers: [String], in directory: URL, fileManager: FileManager) -> Bool {
        markers.contains { fileManager.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    private static func hasManifest(_ directory: URL, fileManager: FileManager) -> Bool {
        if contains(manifestMarkers, in: directory, fileManager: fileManager) { return true }
        guard !manifestSuffixes.isEmpty,
              let entries = try? fileManager.contentsOfDirectory(atPath: directory.path)
        else { return false }
        return entries.contains { entry in
            manifestSuffixes.contains { entry.hasSuffix($0) }
        }
    }
}
