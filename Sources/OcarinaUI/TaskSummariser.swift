import Foundation
import OcarinaTerminalContext
import Observation

/// Asks Claude to name the to-do items, because it is better at it.
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
/// - **Every prompt is asked about once, ever.** Answers are cached on disk by
///   the transcript's own uuid. This spends the user's Claude allowance, and
///   re-summarising the same forty prompts on every launch would be spending it
///   on nothing.
/// - **It goes through the `claude` they already installed**, not an API key
///   they would have to find. No key, no configuration, and it is their own
///   prompts going back to a model they already sent them to.
@MainActor
@Observable
public final class TaskSummariser {
    /// Titles keyed by the transcript uuid of the prompt.
    public private(set) var titles: [String: String] = [:]

    @ObservationIgnored private var asked: Set<String> = []
    @ObservationIgnored private var inFlight = false

    /// One batch is one subprocess launch, which is most of the cost.
    private static let batchLimit = 24

    public init() { titles = Self.loadCache() }

    /// Fills in anything not already named. Safe to call repeatedly.
    public func refresh(_ tasks: [AgentTask]) {
        guard !inFlight,
              let agent = ErrorHelp.located(), agent.name == "claude"
        else { return }

        let pending = tasks
            .filter { titles[$0.id] == nil && !asked.contains($0.id) }
            .suffix(Self.batchLimit)
        guard !pending.isEmpty else { return }

        // Marked before the call, not after: a failure should not put the same
        // batch back on the queue two seconds later, forever.
        asked.formUnion(pending.map(\.id))
        inFlight = true

        let batch = Array(pending)
        let executable = agent.url
        Task { [weak self] in
            let summaries = await Self.summarise(batch.map(\.prompt), using: executable)
            guard let self else { return }
            inFlight = false
            guard summaries.count == batch.count else { return }
            for (task, summary) in zip(batch, summaries) where !summary.isEmpty {
                titles[task.id] = summary
            }
            Self.saveCache(titles)
        }
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

    static var cacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Ocarina", isDirectory: true)
            .appendingPathComponent("task-titles.json")
    }

    private static func loadCache() -> [String: String] {
        guard let data = try? Data(contentsOf: cacheURL),
              let titles = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return titles
    }

    private static func saveCache(_ titles: [String: String]) {
        let url = cacheURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? JSONEncoder().encode(titles).write(to: url, options: .atomic)
    }
}
