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
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
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

    private static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }
}
