import Foundation

/// Keeps the usage reading current without re-reading what has not changed.
///
/// The window is account-wide, so a reading means touching every project's
/// transcripts rather than one — and the hot one among them is a file that
/// grows all session. Re-parsing all of it on a timer is exactly the cost the
/// task panel already learned not to pay, so a file is parsed once per version
/// of itself and its samples are kept.
public actor TokenUsageMeter {
    private let source: TokenUsageSource
    private var cached: [URL: Reading] = [:]

    private struct Reading {
        let signature: String
        /// How far into the file the samples account for, so the next poll can
        /// read forward from there instead of starting again.
        let readTo: UInt64
        let samples: [TokenUsageSource.Sample]
    }

    public init(source: TokenUsageSource = TokenUsageSource()) {
        self.source = source
    }

    /// The window that is running now, or nil when nothing has been spent in
    /// one — a machine that has not talked to an agent in five hours.
    public func read(now: Date = Date()) -> UsageWindow? {
        let cutoff = now.addingTimeInterval(-TokenUsageSource.lookback)
        let transcripts = source.transcripts(since: cutoff)

        var samples: [TokenUsageSource.Sample] = []
        var fresh: [URL: Reading] = [:]
        for transcript in transcripts {
            let signature = Self.signature(of: transcript)
            let size = Self.size(of: transcript)
            let reading: Reading
            if let previous = cached[transcript], previous.signature == signature {
                // Unchanged since the last poll.
                reading = previous
            } else if let previous = cached[transcript],
                      let appended = TokenUsageSource.samples(
                          in: transcript, since: cutoff, from: previous.readTo
                      ) {
                // Changed, but only by growing — which is all a transcript
                // ever does. Read the new bytes, keep the old samples, and
                // drop whatever has fallen out of the window since.
                reading = Reading(
                    signature: signature,
                    readTo: size,
                    samples: previous.samples.filter { $0.at >= cutoff } + appended
                )
            } else {
                reading = Reading(
                    signature: signature,
                    readTo: size,
                    samples: TokenUsageSource.samples(in: transcript, since: cutoff)
                )
            }
            fresh[transcript] = reading
            samples.append(contentsOf: reading.samples)
        }
        // Files that have fallen out of the lookback fall out of the cache with
        // them, so this does not grow for the life of the app.
        cached = fresh

        // A cached file was read against an older cutoff than this one, and the
        // cutoff moves with the clock: without this, a sample from six hours
        // ago could still be the one that looks like it opened the window.
        return TokenUsageSource.window(from: samples.filter { $0.at >= cutoff }, now: now)
    }

    private static func size(of url: URL) -> UInt64 {
        UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    /// Path, size and modification date — one `stat`, which is the whole point
    /// of it compared with parsing the file to find out it had not changed.
    private static func signature(of url: URL) -> String {
        let values = try? url.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey]
        )
        let size = values?.fileSize ?? 0
        let stamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(url.path):\(size):\(stamp)"
    }
}
