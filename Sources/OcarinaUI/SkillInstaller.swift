import Foundation

/// Fetches a skill's folder out of its repository and writes it where the
/// agent will find it.
///
/// Two requests' worth of work: one to GitHub's tree API to learn which files
/// the folder holds, then one `raw.githubusercontent.com` fetch per file. A
/// skill is a `SKILL.md` and usually a handful of things beside it, so that is
/// a few hundred kilobytes at worst — small enough not to need a tarball, and
/// a tarball of a repository like `microsoft/azure-skills` to extract one
/// folder is thirty megabytes to save four requests.
///
/// Nothing is written until every file has been fetched. A skill is a folder an
/// agent reads as a unit, and half of one on disk is worse than none: the
/// `SKILL.md` promises a script that is not there.
public enum SkillInstaller {
    public enum Failure: LocalizedError {
        case listing
        case empty
        case download(String)
        case tooLarge
        case unsafePath(String)
        case write(String)

        public var errorDescription: String? {
            switch self {
            case .listing: "GitHub would not say what is in this skill."
            case .empty: "There is nothing in this skill's folder."
            case let .download(file): "Could not download \(file)."
            case .tooLarge: "This skill is larger than Ocarina will install."
            case let .unsafePath(path): "This skill asks to write outside its own folder (\(path))."
            case let .write(reason): "Could not write the skill: \(reason)"
            }
        }
    }

    /// The ceiling on one skill. Generous for instructions and assets, and low
    /// enough that a repository which has quietly become a data set cannot be
    /// pulled into somebody's home directory by one click.
    static let sizeLimit = 12 * 1024 * 1024
    static let fileLimit = 200

    /// Downloads `skill` into `home`, replacing whatever was there.
    ///
    /// Replacing rather than merging: a new version with a file deleted, merged
    /// over an old one, leaves the deleted file behind and the agent reads it.
    public static func install(_ skill: Skill, into home: SkillHome) async throws {
        let files = try await listing(for: skill)
        guard !files.isEmpty else { throw Failure.empty }
        guard files.count <= fileLimit else { throw Failure.tooLarge }

        var fetched: [(String, Data)] = []
        var total = 0
        for file in files {
            // Every path is checked before a byte of it is written, and again
            // by `destination` below. A repository is somebody else's data.
            guard Self.isSafe(file) else { throw Failure.unsafePath(file) }
            let raw = "https://raw.githubusercontent.com/\(skill.repo)/\(skill.branch)/\(skill.path)/\(file)"
            guard let url = URL(string: raw) else { throw Failure.download(file) }
            let data: Data
            do {
                let (bytes, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw Failure.download(file)
                }
                data = bytes
            } catch {
                throw Failure.download(file)
            }
            total += data.count
            guard total <= sizeLimit else { throw Failure.tooLarge }
            fetched.append((file, data))
        }

        let folder = home.location(of: skill)
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: home.directory, withIntermediateDirectories: true)
            // Into a sibling first, then swapped in. A download that fails part
            // way through must not be able to delete a working skill.
            let staging = home.directory.appendingPathComponent(
                ".\(skill.name).incoming", isDirectory: true
            )
            try? manager.removeItem(at: staging)
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)

            for (file, data) in fetched {
                let destination = staging.appendingPathComponent(file)
                guard destination.standardizedFileURL.path
                    .hasPrefix(staging.standardizedFileURL.path + "/")
                else { throw Failure.unsafePath(file) }
                try manager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: destination)
            }

            try? manager.removeItem(at: folder)
            try manager.moveItem(at: staging, to: folder)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.write(error.localizedDescription)
        }
    }

    /// Takes a skill back off disk. Only ever its own folder, by name.
    public static func remove(_ skill: Skill, from home: SkillHome) throws {
        let folder = home.location(of: skill)
        guard folder.deletingLastPathComponent().standardizedFileURL
            == home.directory.standardizedFileURL
        else { throw Failure.unsafePath(skill.name) }
        try FileManager.default.removeItem(at: folder)
    }

    /// The files under the skill's folder, as paths relative to it.
    static func listing(for skill: Skill) async throws -> [String] {
        let api = "https://api.github.com/repos/\(skill.repo)/git/trees/\(skill.branch)?recursive=1"
        guard let url = URL(string: api) else { throw Failure.listing }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Ocarina", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tree = root["tree"] as? [[String: Any]]
        else { throw Failure.listing }

        let prefix = skill.path + "/"
        return tree.compactMap { entry -> String? in
            guard entry["type"] as? String == "blob",
                  let path = entry["path"] as? String,
                  path.hasPrefix(prefix)
            else { return nil }
            return String(path.dropFirst(prefix.count))
        }
    }

    /// A path from somebody else's repository, checked before it is joined onto
    /// a directory in this user's home.
    static func isSafe(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.contains("") && !parts.contains("..") && !parts.contains(".")
    }
}
