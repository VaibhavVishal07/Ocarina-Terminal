import Foundation

/// What an agent has spent in the limit window it is currently inside.
public struct UsageWindow: Sendable, Equatable {
    /// Tokens counted once each: what was sent, what was written to cache, and
    /// what came back. See `TokenUsageSource.tokens(in:)` for why cache *reads*
    /// are not in here.
    public let tokens: Int
    /// When the window opened — the first request after the last one lapsed.
    public let startedAt: Date
    /// And when it lapses, which is what the card counts down to.
    public let resetsAt: Date

    public init(tokens: Int, startedAt: Date, resetsAt: Date) {
        self.tokens = tokens
        self.startedAt = startedAt
        self.resetsAt = resetsAt
    }

    /// 0 at the top of the window, 1 at the end of it.
    public func elapsedFraction(at now: Date = Date()) -> Double {
        let span = resetsAt.timeIntervalSince(startedAt)
        guard span > 0 else { return 1 }
        return min(max(now.timeIntervalSince(startedAt) / span, 0), 1)
    }
}

/// Reads how much an agent has spent, from the transcripts it writes anyway.
///
/// ## What this cannot tell you, and why
///
/// It reports what has been **used**, not what is left. Nothing on this machine
/// records the size of the allowance or when the account's own quota renews:
/// not `~/.claude.json`, whose two rate-limit tier fields are null; not the
/// session files; not the transcripts, which carry no rate-limit record of any
/// kind. The number exists only in the responses Anthropic sends back, and the
/// only way to ask for it would be to take the user's OAuth token out of their
/// home directory and spend it on a request they did not make. A terminal does
/// not get to do that.
///
/// So the card says what can be said honestly — how much has gone through the
/// window you are in, and how long that window has left to run. A meter with a
/// denominator invented for it would be worse than no meter.
///
/// ## The window
///
/// Usage is counted in blocks: a block opens on the first request made after
/// the last one lapsed, and runs for five hours. That is reconstructed here
/// from the timestamps, which is the one part of it the transcripts do record.
public struct TokenUsageSource: Sendable {
    /// How long a block runs.
    public static let windowLength: TimeInterval = 5 * 60 * 60

    /// How far back to look. Two windows, so the block that is running now can
    /// always be traced back to the request that opened it.
    public static let lookback: TimeInterval = windowLength * 2

    private let root: URL

    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// One request's cost, and when it was made.
    struct Sample: Sendable, Equatable {
        let at: Date
        let tokens: Int
    }

    // MARK: - Reading

    /// Every transcript that could hold a request inside the lookback.
    ///
    /// The window is account-wide rather than per project — two tabs working on
    /// two repositories draw on the same allowance — so this is every project
    /// folder, not the one the tab is sitting in. A file whose last write
    /// predates the lookback cannot contain a sample inside it, which throws
    /// out almost all of them for the cost of a `stat`.
    func transcripts(since cutoff: Date) -> [URL] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return folders.flatMap { folder in
            JSONLReader.files(
                in: folder,
                recursive: false,
                limit: Int.max,
                where: { $0.hasSuffix(".jsonl") }
            )
            .filter { JSONLReader.modificationDate(of: $0) >= cutoff }
        }
    }

    /// The samples in one transcript's recent end.
    ///
    /// Only the tail is read. A long session's file runs to tens of megabytes
    /// and the lookback is ten hours, so the front of it is guaranteed to be
    /// older than anything being asked about.
    static func samples(in transcript: URL, since cutoff: Date) -> [Sample] {
        guard let handle = try? FileHandle(forReadingFrom: transcript),
              let end = try? handle.seekToEnd()
        else { return [] }
        defer { try? handle.close() }

        // One formatter for the whole file rather than one per line. It cannot
        // be a shared static — `ISO8601DateFormatter` is not `Sendable` — and
        // building one per timestamp is most of the cost of the parse.
        let clock = ISO8601DateFormatter.transcript()
        var samples: [Sample] = []
        var upper = end
        /// The partial line at the front of the chunk just read; the rest of
        /// it is in the chunk before, which is the one read next.
        var carry = Data()

        while upper > 0, end - upper < UInt64(ceiling) {
            let size = min(UInt64(chunk), upper)
            let lower = upper - size
            try? handle.seek(toOffset: lower)
            guard var data = try? handle.read(upToCount: Int(size)) else { break }
            data.append(carry)

            var lines = data.lines()
            carry = lower > 0 && !lines.isEmpty ? lines.removeFirst() : Data()

            var reachedCutoff = false
            // Backwards, so the walk can stop. A transcript is chronological,
            // so the first record older than the cutoff means every record
            // before it is older too — and on most of the sixty transcripts a
            // poll looks at, that happens in the first chunk.
            for line in lines.reversed() {
                // Almost every line is a tool result or a prompt, and
                // JSON-parsing all of them to find the assistant turns is the
                // expensive way round. A byte search throws them out before
                // they are ever a String.
                guard line.range(of: usageMarker) != nil,
                      let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let at = date(row["timestamp"], using: clock)
                else { continue }
                guard at >= cutoff else { reachedCutoff = true; break }
                guard let message = row["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any]
                else { continue }
                samples.append(Sample(at: at, tokens: tokens(in: usage)))
            }
            if reachedCutoff { break }
            upper = lower
        }
        return samples
    }

    /// The samples in the bytes appended to a transcript since it was last
    /// read.
    ///
    /// A transcript is an append-only log, and the one you are talking to is
    /// rewritten every few seconds — so re-reading its whole window on every
    /// poll is re-reading the same megabytes to find the two lines that are
    /// new. Reading forward from where the last read stopped costs what
    /// actually happened since.
    static func samples(in transcript: URL, since cutoff: Date, from offset: UInt64) -> Appended? {
        guard let handle = try? FileHandle(forReadingFrom: transcript),
              let end = try? handle.seekToEnd()
        else { return nil }
        defer { try? handle.close() }
        // Shorter than last time means it is not the same file any more —
        // rotated, truncated, replaced. Start again rather than guess.
        guard end >= offset else { return nil }
        guard end > offset else { return Appended(samples: [], readTo: end) }

        try? handle.seek(toOffset: offset)
        guard let data = try? handle.read(upToCount: Int(end - offset)) else { return nil }

        let clock = ISO8601DateFormatter.transcript()
        var samples: [Sample] = []
        for line in data.lines() {
            guard line.range(of: usageMarker) != nil,
                  let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let at = date(row["timestamp"], using: clock), at >= cutoff,
                  let message = row["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }
            samples.append(Sample(at: at, tokens: tokens(in: usage)))
        }
        return Appended(samples: samples, readTo: end)
    }

    /// What a forward read found, and where it stopped.
    ///
    /// The offset comes back from the read itself rather than from a `stat`
    /// taken beside it. They are not the same number: a transcript being
    /// written to grows between the two, and recording the smaller one meant
    /// the next poll started inside bytes already counted and added the same
    /// responses to the window again. A meter that overcounts the busiest
    /// session on the machine is the one case where it matters most.
    struct Appended: Sendable {
        let samples: [Sample]
        let readTo: UInt64
    }

    /// How much of a transcript is read at a time.
    ///
    /// A fixed tail was the wrong shape in both directions. Four megabytes
    /// decoded per file put the first reading past ten seconds across sixty
    /// transcripts; cutting it to one megabyte fixed that and quietly lost two
    /// thirds of a busy session's window, which is worse — a usage meter that
    /// undercounts is not a usage meter.
    ///
    /// Reading backwards a chunk at a time costs what the answer actually
    /// spans: one chunk for a file with nothing recent in it, as many as it
    /// takes for the one you have been talking to all afternoon.
    static let chunk = 256 * 1024

    /// The most any one transcript may be read. A stop, not a budget: without
    /// it a corrupt or timestamp-free file would be walked end to end.
    static let ceiling = 64 * 1024 * 1024

    private static let usageMarker = Data(#""usage":"#.utf8)

    /// What one response cost.
    ///
    /// Input, cache writes and output. Cache *reads* are deliberately left
    /// out: they are the same tokens being read back, and they were already
    /// counted on the turn that wrote them. Adding them counts a long
    /// conversation's context once per turn, which on a session like this one
    /// is millions of tokens that were never sent twice.
    static func tokens(in usage: [String: Any]) -> Int {
        func count(_ key: String) -> Int { (usage[key] as? Int) ?? 0 }
        return count("input_tokens")
            + count("cache_creation_input_tokens")
            + count("output_tokens")
    }

    private static func date(_ raw: Any?, using clock: ISO8601DateFormatter) -> Date? {
        guard let string = raw as? String else { return nil }
        return clock.date(from: string)
    }

    // MARK: - The window

    /// A block opens on the hour, not on the request that opened it.
    ///
    /// This is the difference between a countdown that agrees with the one the
    /// account is actually keeping and one that is up to an hour out. A block
    /// runs from the top of the hour containing its first request — a first
    /// message at 09:47 opens a block that ends at 14:00, not 14:47 — so a
    /// window rebuilt from the raw timestamp reports a reset that has already
    /// happened, and goes on counting the spent block into the renewed one.
    ///
    /// Floored in UTC, which is where the hour boundary is: an account on a
    /// half-hour offset resets at half past the local hour.
    static func blockStart(containing date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.dateInterval(of: .hour, for: date)?.start ?? date
    }

    /// The block the given samples are currently inside.
    ///
    /// A block opens on the hour of the first request made after the previous
    /// one lapsed, and runs `windowLength`. Walking forward from the oldest
    /// sample rebuilds that: each request that lands after the open block has
    /// expired opens the next one.
    ///
    /// `anchor` is the block this meter last reported, and it is what keeps
    /// the card steady. Reconstruction alone cannot: the samples it works from
    /// are only the ones inside the lookback, so as the oldest of them fall
    /// out the chain re-anchors and the reported window moves under a user who
    /// has done nothing. A block that has been established is kept until the
    /// clock says it has lapsed, and only then is the next one derived — from
    /// the requests made after it ended, never from the ones that filled it.
    static func window(from samples: [Sample], now: Date = Date(), anchor: Date? = nil) -> UsageWindow? {
        let ordered = samples.sorted { $0.at < $1.at }
        let start: Date

        if let anchor, anchor <= now, now < anchor.addingTimeInterval(windowLength) {
            start = anchor
        } else {
            // A lapsed anchor draws a line under itself: the block that has
            // ended cannot name the one that follows it.
            let lapsed = anchor.map { $0.addingTimeInterval(windowLength) }
            guard let opener = ordered.first(where: { lapsed == nil || $0.at >= lapsed! })?.at
            else { return nil }

            var derived = blockStart(containing: opener)
            for sample in ordered where sample.at >= derived.addingTimeInterval(windowLength) {
                derived = blockStart(containing: sample.at)
            }
            // The last block has already lapsed: nothing has been spent in the
            // one that is open now, because nothing has opened it yet.
            guard derived.addingTimeInterval(windowLength) > now else { return nil }
            start = derived
        }

        let end = start.addingTimeInterval(windowLength)
        let tokens = ordered
            .filter { $0.at >= start && $0.at < end }
            .reduce(0) { $0 + $1.tokens }
        return UsageWindow(tokens: tokens, startedAt: start, resetsAt: end)
    }
}

extension ISO8601DateFormatter {
    /// Transcript timestamps carry milliseconds, which the default
    /// configuration refuses outright rather than ignoring.
    static func transcript() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

private extension Data {
    /// The block's lines, as slices, without decoding any of them.
    func lines() -> [Data] {
        var lines: [Data] = []
        var start = startIndex
        while let newline = self[start...].firstIndex(of: 0x0A) {
            if newline > start { lines.append(self[start..<newline]) }
            start = index(after: newline)
        }
        if start < endIndex { lines.append(self[start..<endIndex]) }
        return lines
    }
}
