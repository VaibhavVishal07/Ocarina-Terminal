import Foundation

/// Minimal tail/head reader for agent transcripts.
///
/// Transcripts grow to megabytes, and only the recent end matters, so the tail
/// is read by seeking rather than by loading the file.
enum JSONLReader {
    static func tailLines(of url: URL, maxBytes: Int = 512 * 1024) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        guard let end = try? handle.seekToEnd() else { return [] }
        let offset = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return [] }

        var lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        // A mid-line seek leaves a partial first record.
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }

    /// The tail of a file, as bytes.
    ///
    /// `tailLines` decodes and validates the whole block as UTF-8 before the
    /// caller has looked at a single line, which is the wrong shape when the
    /// caller only wants a handful of records out of megabytes: the usage
    /// meter reads sixty transcripts a poll, and decoding four megabytes of
    /// each of them took the first reading past ten seconds. Handing back the
    /// bytes lets a caller throw lines out on a byte search and decode only
    /// what survives.
    static func tailData(of url: URL, maxBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let offset = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: offset)
        guard var data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        // A mid-file seek leaves a partial first record.
        if offset > 0, let newline = data.firstIndex(of: 0x0A) {
            data = data[data.index(after: newline)...]
        }
        return data
    }

    /// The opening lines of a transcript.
    ///
    /// The mirror of `tailLines`, and it exists for the same reason in
    /// reverse: what a session is *about* is settled by its first prompt, and
    /// that record never moves. Reading the head means the answer stops
    /// changing once the file has been written to twice.
    static func headLines(of url: URL, maxBytes: Int = 512 * 1024) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: maxBytes), !data.isEmpty else { return [] }
        var lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        // Stopping at a byte count leaves a partial last record, unless the
        // read reached the end of the file.
        if data.count == maxBytes, !lines.isEmpty { lines.removeLast() }
        return lines
    }

    static func firstLine(of url: URL, maxBytes: Int = 64 * 1024) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes), !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)
    }

    static func object(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Files under `directory` matching `predicate`, newest modification first.
    static func files(
        in directory: URL,
        recursive: Bool,
        limit: Int,
        where predicate: (String) -> Bool
    ) -> [URL] {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey, .isRegularFileKey]
        var candidates: [URL] = []

        if recursive {
            guard let walker = manager.enumerator(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return [] }
            for case let url as URL in walker where predicate(url.lastPathComponent) {
                candidates.append(url)
            }
        } else {
            let contents = (try? manager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )) ?? []
            candidates = contents.filter { predicate($0.lastPathComponent) }
        }

        return candidates
            .map { ($0, modificationDate(of: $0)) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// A session file appears after its process does, never before it. The
    /// second of slack is for clock granularity, not for a real gap: widening
    /// it lets a neighbouring session that started moments earlier qualify.
    static let launchTolerance: TimeInterval = 1

    /// Which transcript in `directory` belongs to the terminal whose agent
    /// started at `startedAt`.
    ///
    /// Picking the most recently written file names a tab after whichever
    /// conversation typed last — which, with two agents open on one project,
    /// is regularly the other tab's. Binding to the process start time is what
    /// makes a tab show its own work, and it is what makes the task panel show
    /// the tasks of the tab you are looking at rather than the folder's.
    ///
    /// A session writes its file on its first prompt rather than at launch, so
    /// two sessions started close together can still be told apart only by the
    /// order their files appear in. That order is usually the order they
    /// started in; when it is not, the worst case is the old behaviour.
    static func session(in directory: URL, startedAt: Date?) -> URL? {
        let candidates = files(
            in: directory,
            recursive: false,
            limit: Int.max,
            where: { $0.hasSuffix(".jsonl") }
        )
        guard let startedAt else { return candidates.first }

        // The session this terminal opened: the first file created once the
        // process existed.
        let threshold = startedAt.addingTimeInterval(-launchTolerance)
        let own = candidates
            .map { ($0, creationDate(of: $0)) }
            .filter { $0.1 >= threshold }
            .min { $0.1 < $1.1 }
        if let own { return own.0 }

        // `--continue` and `--resume` reopen a file older than the process, so
        // fall back to the newest one this process can have written.
        return candidates.first { modificationDate(of: $0) >= threshold }
    }

    static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    /// When the file was first written. Distinguishes a session started in
    /// this terminal from one that merely wrote to disk more recently.
    static func creationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
            ?? modificationDate(of: url)
    }
}
