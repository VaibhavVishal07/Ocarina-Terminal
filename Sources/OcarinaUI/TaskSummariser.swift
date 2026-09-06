import Foundation
import OcarinaTerminalContext
import Observation

/// Asks Claude to name the to-do items and the tabs, because it is better at
/// it than a word filter is.
///
/// The local condenser strips filler and keeps five words in the order they
/// were said. It is fast, free and offline, and it is also obviously a machine
/// doing string surgery: "Toggle option near right-hand", "Current terminal I'm
/// using, unable". Claude turns the same prompts into "Move toggle to right
/// side" and "Fix text field cut function", which is the difference between a
/// list you decode and a list you read.
///
/// Three rules follow from where the work happens:
///
/// - **The heuristic still runs first.** Its title appears immediately and is
///   replaced when a better one arrives. Nothing waits on a subprocess, and a
///   machine with no agent installed loses nothing it had.
/// - **Every prompt is asked about once, ever.** Answers are cached on disk
///   under a hash of the prompt, so the same words asked about from the task
///   panel and from the tab strip cost one call between them. This spends the
///   user's Claude allowance, and re-summarising the same forty prompts on
///   every launch would be spending it on nothing.
/// - **It goes through the `claude` they already installed**, not an API key
///   they would have to find. No key, no configuration, and it is their own
///   prompts going back to a model they already sent them to.
@MainActor
@Observable
public final class TaskSummariser {
    /// Titles keyed by the prompt they were written for, not by where it was
    /// found.
    ///
    /// Keyed by the transcript's uuid, this named tasks and nothing else. The
    /// tab strip asks the same question about the same words — the sidebar's
    /// title is the opening prompt of the conversation the panel is listing —
    /// and keying on the text means it is answered once for both, from one
    /// cache, at one subprocess.
    public private(set) var titles: [String: String] = [:]

    /// Prompts waiting to be named, oldest first.
    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var asked: Set<String> = []
    @ObservationIgnored private var inFlight = false

    /// One batch is one subprocess launch, which is most of the cost.
    private static let batchLimit = 24

    /// Where the answers are kept between launches. Injectable so a test gets
    /// a cache of its own — sharing the real one, a test asserting that
    /// nothing has been named yet passes or fails on what the app happened to
    /// ask about last.
    @ObservationIgnored private let cacheURL: URL

    public init(cache: URL? = nil) {
        cacheURL = cache ?? Self.defaultCacheURL
        titles = Self.loadCache(from: cacheURL)
    }

    /// The better name for a prompt, once there is one.
    public func title(for prompt: String) -> String? {
        titles[Self.key(for: prompt)]
    }

    /// Fills in anything not already named. Safe to call repeatedly.
    public func refresh(_ tasks: [AgentTask]) {
        refresh(prompts: tasks.map(\.prompt))
    }

    /// The same, for prompts that did not arrive as tasks — the one that names
    /// a tab, which the panel may never list because it belongs to a
    /// conversation in another tab.
    public func refresh(prompts: [String]) {
        for prompt in prompts {
            let key = Self.key(for: prompt)
            guard titles[key] == nil, !asked.contains(key),
                  !queue.contains(where: { Self.key(for: $0) == key })
            else { continue }
            queue.append(prompt)
        }
        drain()
    }

    /// Sends the next batch, and the one after it when that comes back.
    ///
    /// Draining on completion rather than waiting for the panel's next poll is
    /// what a tab title needs: nothing polls on its behalf, so a queue that
    /// only moved when the task list was re-read left a background tab on its
    /// heuristic name until somebody typed in it.
    private func drain() {
        guard !inFlight, !queue.isEmpty,
              let agent = ErrorHelp.located(), agent.name == "claude"
        else { return }

        // The end of the queue, because the most recent thing asked is the
        // thing being looked at.
        let batch = Array(queue.suffix(Self.batchLimit))
        queue.removeLast(batch.count)

        // Marked before the call, not after: a failure should not put the same
        // batch back on the queue two seconds later, forever.
        asked.formUnion(batch.map(Self.key(for:)))
        inFlight = true

        let executable = agent.url
        Task { [weak self] in
            let summaries = await Self.summarise(batch, using: executable)
            guard let self else { return }
            inFlight = false
            if summaries.count == batch.count {
                for (prompt, summary) in zip(batch, summaries) where !summary.isEmpty {
                    titles[Self.key(for: prompt)] = summary
                }
                Self.save(titles, to: cacheURL)
            }
            drain()
        }
    }

    /// Records a title without asking for one. For tests, and for nothing
    /// else: every other route to a title goes through `drain`.
    func remember(_ title: String, for prompt: String) {
        titles[Self.key(for: prompt)] = title
    }

    /// Two prompts are the same question if they read the same.
    ///
    /// Hashed rather than stored whole: the cache is a file on disk, and a
    /// file of somebody's prompts is a different object from a file of titles
    /// they can already see in the app.
    static func key(for prompt: String) -> String {
        let flattened = prompt
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        // FNV-1a. A hash, not a checksum: it needs to be stable across
        // launches, which rules out `Hasher`, and nothing here is adversarial.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in flattened.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    // MARK: - Talking to the agent

    /// Read from a detached task, so they sit outside the actor.
    ///
    /// Haiku on purpose: naming a to-do item is not work that needs a large
    /// model, and this runs unprompted in the background on the user's own
    /// allowance.
    private nonisolated static let model = "claude-haiku-4-5-20251001"
    private nonisolated static let timeout: Duration = .seconds(60)

    private nonisolated static func summarise(
        _ prompts: [String],
        using executable: URL
    ) async -> [String] {
        let numbered = prompts.enumerated()
            .map { "\($0.offset + 1). \($0.element.replacingOccurrences(of: "\n", with: " "))" }
            .joined(separator: "\n")

        // Says the line count twice and forbids numbering, because the reply is
        // matched back to the prompts by position: one extra line and the whole
        // batch is discarded.
        let instruction = """
        Below are \(prompts.count) requests someone typed to a coding agent, numbered.
        Write a to-do item for each, at most five words, imperative where it reads \
        naturally. Keep any negation. Output exactly \(prompts.count) lines, one per \
        request, in the same order, with no numbering, no bullets and no other text.

        \(numbered)
        """

        guard let output = await run(instruction, using: executable) else { return [] }
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                var text = line.trimmingCharacters(in: .whitespaces)
                // Strip numbering or a bullet the model added anyway.
                while let first = text.first, first.isNumber || ". -•*".contains(first) {
                    text.removeFirst()
                }
                return text.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }

    private nonisolated static func run(_ instruction: String, using executable: URL) async -> String? {
        await withCheckedContinuation { continuation in
            Task.detached {
                let process = Process()
                // The binary itself, not `env`: see `ErrorHelp.located`.
                process.executableURL = executable
                process.arguments = ["-p", "--model", Self.model, instruction]

                let out = Pipe()
                process.standardOutput = out
                process.standardError = Pipe()
                // Without this the CLI waits three seconds for piped input that
                // is never coming.
                process.standardInput = FileHandle.nullDevice

                guard (try? process.run()) != nil else {
                    continuation.resume(returning: nil)
                    return
                }

                // A hung agent must not leak a process for the life of the app.
                let killer = Task {
                    try? await Task.sleep(for: Self.timeout)
                    if process.isRunning { process.terminate() }
                }

                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                killer.cancel()

                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: String(data: data, encoding: .utf8))
            }
        }
    }

    // MARK: - Cache

    static var defaultCacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Ocarina", isDirectory: true)
            .appendingPathComponent("prompt-titles.json")
    }

    /// The cache before this one, keyed by transcript uuid. Its keys mean
    /// nothing now, so it is deleted rather than left to sit in Application
    /// Support forever.
    private static func supersededCacheURL(beside url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent("task-titles.json")
    }

    private static func loadCache(from url: URL) -> [String: String] {
        try? FileManager.default.removeItem(at: supersededCacheURL(beside: url))
        guard let data = try? Data(contentsOf: url),
              let titles = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return titles
    }

    private static func save(_ titles: [String: String], to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? JSONEncoder().encode(titles).write(to: url, options: .atomic)
    }
}
