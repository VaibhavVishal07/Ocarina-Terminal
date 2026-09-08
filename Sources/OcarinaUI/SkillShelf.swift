import Foundation
import Observation

/// What has been installed, what is being installed, and what is waiting for
/// an agent to appear before it can be.
///
/// The browser used to open only on a tab with an agent in front of it, and
/// nowhere else. The reasoning was sound as far as it went — a skill installs
/// into `~/.claude/skills` or `~/.agents/skills` depending on which agent reads
/// it, and on a plain shell there is no answer to "install this where". But the
/// conclusion was wrong, because it made the shelf reachable only by somebody
/// who had already got where the shelf was meant to help them get. You find out
/// what a skill is by browsing them, and you cannot browse them until you have
/// started an agent, which is the thing the skills are for.
///
/// So the browser is always open, and this holds what to do about a press that
/// arrives with no agent to install into: keep it, say so, and put it in as
/// soon as one starts. The queue survives switching tabs and closing the
/// browser. It does not survive quitting, and deliberately — a queue restored
/// three days later would install something somebody has forgotten asking for.
@MainActor
@Observable
public final class SkillShelf {
    /// Waiting for an agent. In the order they were asked for, because that is
    /// the order they will go in and the panel says so.
    public private(set) var queued: [Skill] = []
    /// The one being fetched. One at a time: two skills arriving at once is two
    /// spinners and no way to tell which failed.
    public private(set) var installing: Skill?
    /// What the strip across the window is saying, if anything.
    public private(set) var notice: Notice?
    /// What is on disk, by the directory it is in. Kept here rather than read
    /// on every draw because `installedNames()` is a directory scan and the
    /// browser asks for it once per row.
    ///
    /// Every home and not just the one in front of you, which is what lets the
    /// count on the sidebar row and the "Yours" list be true on a plain shell.
    /// Reading only the selected agent's directory meant that closing Claude
    /// took your four installed skills off the screen — they were still on
    /// disk, and the app had simply stopped looking.
    ///
    /// Two directories in practice, not four: Codex, Gemini and OpenCode all
    /// read `~/.agents/skills`.
    public private(set) var byDirectory: [URL: Set<String>] = [:]

    /// Everything installed anywhere, which is what "yours" means.
    public var installed: Set<String> {
        byDirectory.values.reduce(into: Set<String>()) { $0.formUnion($1) }
    }

    /// Whether this skill is installed *where the agent in front of you would
    /// read it*, which is a different question from whether you have it.
    ///
    /// With no agent there is no such directory, so the honest answer is the
    /// global one: you have it, and which agent gets to see it is settled when
    /// one starts.
    public func has(_ skill: Skill, in home: SkillHome?) -> Bool {
        guard let home else { return installed.contains(skill.name) }
        return byDirectory[home.directory.standardizedFileURL]?.contains(skill.name) ?? false
    }

    public init() {}

    /// A line across the top of the window, and what kind of thing it is.
    ///
    /// It exists because the browser is a modal you close. Everything the app
    /// knew about an install used to be inside that modal — the spinner, the
    /// "Installed" label — so closing it took the only evidence with it, and
    /// what was left was a folder appearing in your home directory. The strip
    /// is what says a thing you asked for actually happened, after you have
    /// stopped looking at the screen that asked.
    public struct Notice: Equatable, Identifiable {
        public enum Kind: Equatable { case done, waiting, trouble }
        public let id = UUID()
        public let kind: Kind
        public let text: String
        /// What the button on the strip does, named. Nil draws no button.
        public let action: String?

        public static func == (a: Notice, b: Notice) -> Bool {
            a.kind == b.kind && a.text == b.text && a.action == b.action
        }
    }

    // MARK: - Asking for one

    /// Install it now if there is somewhere to put it, and otherwise keep it.
    public func add(_ skill: Skill, into home: SkillHome?) {
        guard let home else {
            // Already asked for. Pressing twice is not two installs, and the
            // strip saying so twice is worse than it saying so once.
            guard !queued.contains(skill) else { return }
            queued.append(skill)
            notice = Notice(
                kind: .waiting,
                // Named, so the sentence is about the thing they pressed
                // rather than about the app's internal state.
                text: "\(skill.name) is waiting for an agent. Start Claude and it goes in on its own.",
                action: "Start Claude"
            )
            return
        }
        install(skill, into: home)
    }

    public func cancel(_ skill: Skill) {
        queued.removeAll { $0 == skill }
        if queued.isEmpty, notice?.kind == .waiting { notice = nil }
    }

    public func dismissNotice() { notice = nil }

    // MARK: - Doing it

    private func install(_ skill: Skill, into home: SkillHome) {
        guard installing == nil else {
            if !queued.contains(skill) { queued.append(skill) }
            return
        }
        installing = skill
        Task { @MainActor in
            do {
                try await SkillInstaller.install(skill, into: home)
                rescan()
                notice = Notice(
                    kind: .done,
                    // What actually changed, and when it takes effect. An
                    // agent reads its skills directory when it starts, so a
                    // skill installed into a conversation already running is
                    // not in that conversation — saying "installed" and
                    // stopping there is how somebody comes to believe the
                    // feature is broken.
                    text: "\(skill.name) is installed. \(home.agent) reads it the next time it starts.",
                    action: nil
                )
            } catch {
                notice = Notice(
                    kind: .trouble,
                    text: "\(skill.name) did not install: \(error.localizedDescription)",
                    action: nil
                )
            }
            installing = nil
            // Whatever is next in the queue, if this was one of several.
            if let next = queued.first {
                queued.removeFirst()
                install(next, into: home)
            }
        }
    }

    /// An agent has appeared. Put in whatever was waiting for one.
    ///
    /// Called from the model's own watch on `skillHome` rather than polled
    /// here: what counts as an agent being in front of you is a question about
    /// the pty and the selected tab, and this object has no business knowing
    /// the answer.
    public func drain(into home: SkillHome) {
        rescan()
        guard installing == nil, let next = queued.first else { return }
        queued.removeFirst()
        install(next, into: home)
    }

    /// Re-read what is on disk. Cheap enough to call when the browser opens and
    /// after anything that writes.
    public func refresh() { rescan() }

    private func rescan() {
        var found: [URL: Set<String>] = [:]
        for home in SkillHome.all {
            let directory = home.directory.standardizedFileURL
            // Three of the four homes are the same directory. Scanning it once
            // is not only cheaper, it keeps the map keyed by what actually
            // distinguishes them.
            guard found[directory] == nil else { continue }
            found[directory] = home.installedNames()
        }
        byDirectory = found
    }

    /// Takes a skill off disk.
    ///
    /// From the agent's own directory when there is an agent, and from
    /// everywhere it is found when there is not. A Remove that quietly did
    /// nothing because no agent happened to be running is the worst of the
    /// three possible behaviours, and it is what the guard on the old call
    /// site produced.
    public func remove(_ skill: Skill, from home: SkillHome?) {
        let targets = home.map { [$0] } ?? SkillHome.all.filter { $0.has(skill) }
        for target in targets {
            try? SkillInstaller.remove(skill, from: target)
        }
        rescan()
    }

    /// Everything the sidebar's count and the panel are built from: what is on
    /// disk plus what is waiting to be.
    public var total: Int { installed.count + queued.count }
}
