import SwiftUI

/// The skills browser: a question, a field, and what the answer turned up.
///
/// It was three tabs, nine category pills, a search box and a grid of cards —
/// four ways of narrowing two hundred and sixteen things, offered to somebody
/// who has one: they know roughly what they want and they cannot name the
/// folder. Every one of those four was a different idiom, and the modal
/// reshuffled itself whenever you moved between them.
///
/// So it asks. One line, one field, and nothing else until you have typed
/// something — the panel is 300pt tall at rest and grows to its full height
/// when there is a list to hold, because a modal that opens at 640pt with one
/// field in it is mostly empty room saying "there is more here" about nothing.
///
/// What the tabs were carrying had to go somewhere. **Installed** is a question
/// with no query — you go there to see what you have, which no typed phrase can
/// match — so it is a line in the footer that swaps the list for your shelf.
/// **Browsing** was the starting shelf, and it is now four example sentences
/// under the field: they are the whole merchandising surface of this screen, and
/// they are written in the register the field expects, which is the only way an
/// empty box teaches you that "make my UI look less generic" is a thing you may
/// type. One of them is design, because the house order is. See
/// `Skill.Category.ordered`.
struct SkillsView: View {
    @Environment(\.theme) private var theme

    /// Where an install would go, and what to call it. Nil on a plain shell —
    /// which is a state this view is built for rather than one it refuses to
    /// open in.
    let home: SkillHome?
    let shelf: SkillShelf
    /// Starts Claude, for the line that offers to.
    let startClaude: () -> Void
    /// Puts a question in front of the agent in the front tab, for the one
    /// screen the catalogue cannot answer. It types and does not press Return.
    let askAgent: (String) -> Void
    let close: () -> Void

    @State private var skills: [Skill] = SkillCatalog.load()
    @State private var query = ""
    @State private var showingShelf = false
    @State private var hovered: String?
    @FocusState private var isFocused: Bool

    private static let width: CGFloat = 620
    /// The question, the field and the four sentences, with room under the last
    /// of them.
    ///
    /// Measured against what is in it — 24 above the title, 26 of title, 18, a
    /// 50pt field, 22, and 116pt of example block — which comes to 296 with the
    /// footer. At 306 that left ten points between the last sentence's
    /// underline and the footer's rule, and two things a hairline apart read as
    /// one thing that has gone wrong.
    private static let askingHeight: CGFloat = 336
    private static let listHeight: CGFloat = 640
    private static let gutter: CGFloat = 26

    /// The sentences under the field.
    ///
    /// Not pills and not category names. A pill teaches you that this box takes
    /// nouns; these teach you that it takes the sentence you would have said out
    /// loud, which is the whole difference the field is for.
    private static let examples = [
        "make my UI look less generic",
        "review a pull request properly",
        "work with spreadsheets and CSVs",
        "write commit messages I'd actually read",
    ]

    private var asked: String { query.trimmingCharacters(in: .whitespaces) }
    private var isAsking: Bool { asked.isEmpty && !showingShelf }

    private var matches: [SkillCatalog.Match] {
        if showingShelf {
            let mine = skills.filter { shelf.installed.contains($0.name) }
            let pool = shelf.queued + mine.filter { !shelf.queued.contains($0) }
            return SkillCatalog.search(pool, for: asked)
        }
        return SkillCatalog.search(skills, for: asked)
    }

    var body: some View {
        VStack(spacing: 0) {
            head
            if !isAsking {
                list
            } else {
                // The floor has to be pushed to the floor. A `VStack` inside a
                // fixed `.frame(height:)` centres what it holds when there is
                // slack, so without this the question and the footer floated as
                // one block in the middle of the panel — the footer a third of
                // the way up, with the panel's own ground under it. `list`
                // carries `maxHeight: .infinity` and does this itself.
                Spacer(minLength: 0)
            }
            footer
        }
        .frame(width: Self.width, height: isAsking ? Self.askingHeight : Self.listHeight)
        .background { OcarinaWindowView.panelSurface(theme, at: .top) }
        .clipShape(OcarinaWindowView.PanelStyle.shape)
        .overlay {
            OcarinaWindowView.PanelStyle.shape
                .stroke(theme.chrome.border.color.opacity(0.22), lineWidth: 1)
        }
        // The one piece of motion in the panel, and it is the panel itself.
        // Nothing inside slides; the box finds the height its contents need.
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: isAsking)
        .onAppear {
            shelf.refresh()
            isFocused = true
        }
        // Typing is always a search of the whole catalogue. Leaving somebody
        // typing into their own shelf of four is the sort of dead end that
        // reads as the field being broken.
        .onChange(of: query) { _, text in
            if !text.isEmpty, showingShelf { showingShelf = false }
        }
    }

    // MARK: - The question

    private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(showingShelf ? "What you have" : "What are you looking for?")
                    .font(theme.uiFont(21, weight: .medium))
                    .foregroundStyle(theme.chrome.textPrimary.color)
                    .contentTransition(.opacity)
                Spacer(minLength: 12)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(theme.uiFont(11, weight: .semibold))
                        .foregroundStyle(theme.chrome.textTertiary.color)
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, 18)

            field

            if isAsking {
                examples
                    .padding(.top, 22)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Self.gutter)
        .padding(.top, 24)
        .padding(.bottom, isAsking ? 0 : 20)
    }

    /// Big, because it is the only thing here.
    ///
    /// 17pt against the 12.5 the old search box used — the field is not a
    /// filter on a page any more, it is the page, and a control that is the
    /// whole interface should be the size of the question it is answering.
    var field: some View {
        HStack(spacing: 12) {
            TextField(
                "",
                text: $query,
                prompt: Text("a code reviewer, PDFs, nicer UI…")
                    .foregroundStyle(theme.chrome.textTertiary.color)
            )
            .textFieldStyle(.plain)
            .font(theme.uiFont(17))
            .foregroundStyle(theme.chrome.textPrimary.color)
            .focused($isFocused)

            if !asked.isEmpty {
                // The tally, not a spinner. It moves on every keystroke, so it
                // is the thing that says the field is live — and it counts
                // rather than fades, because the number itself is the news.
                Text("\(matches.count)")
                    .font(theme.uiFont(12, weight: .medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(theme.chrome.textTertiary.color)
                    .animation(.easeOut(duration: 0.18), value: matches.count)

                Button {
                    query = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(theme.uiFont(13))
                        .foregroundStyle(theme.chrome.textTertiary.color)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(theme.chrome.rowHover.color.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(
                            isFocused
                                ? theme.chrome.accent.color.opacity(0.5)
                                : theme.chrome.border.color.opacity(0.16),
                            lineWidth: 1
                        )
                }
        }
        .animation(.easeOut(duration: 0.14), value: isFocused)
    }

    var examples: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("OR TRY")
                .font(theme.uiFont(9.5, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(theme.chrome.textTertiary.color.opacity(0.75))
            ForEach(Self.examples, id: \.self) { line in
                Button {
                    query = line
                    isFocused = true
                } label: {
                    Text(line)
                        .font(theme.uiFont(13))
                        .foregroundStyle(
                            hovered == line
                                ? theme.chrome.textPrimary.color
                                : theme.chrome.textSecondary.color
                        )
                        .underline(true, color: theme.chrome.border.color.opacity(
                            hovered == line ? 0.5 : 0.22
                        ))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { hovered = line } else if hovered == line { hovered = nil }
                }
                .animation(.easeOut(duration: 0.1), value: hovered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The answer

    @ViewBuilder
    private var list: some View {
        let rows = matches
        VStack(spacing: 0) {
            Rectangle().fill(theme.chrome.border.color.opacity(0.11)).frame(height: 1)
            if rows.isEmpty {
                nothing
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { match in
                            row(match)
                            Rectangle()
                                .fill(theme.chrome.border.color.opacity(0.08))
                                .frame(height: 1)
                                .padding(.horizontal, Self.gutter)
                        }
                        // What is on disk is not always what this app put
                        // there. A skill installed by hand, or by another
                        // machine's sync, is in the directory and is read by
                        // the agent, and a list that silently omitted it would
                        // be a list of what Ocarina remembers rather than of
                        // what the agent has.
                        if showingShelf, shelf.installed.count > rows.count {
                            Text("\(shelf.installed.count - rows.count) more in the folder that are not in this catalogue.")
                                .font(theme.uiFont(10.5))
                                .foregroundStyle(theme.chrome.textTertiary.color)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Self.gutter)
                                .padding(.vertical, 16)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// One skill, at the width the modal now has.
    ///
    /// A row rather than a card, and the reason is the request: "with details".
    /// The card was 86pt in a two-up grid, which is why `Skill.headline` exists
    /// to cut the description at 48 characters — at full width the whole
    /// sentence fits, including the "use this when" half that a person choosing
    /// wants and the card never had room for.
    func row(_ match: SkillCatalog.Match) -> some View {
        let skill = match.skill
        let isHovered = hovered == skill.id

        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    // In the terminal's own face, because it is a folder name
                    // and the agent will call it exactly this.
                    Text(skill.name)
                        .font(.custom(BundledFonts.mono, fixedSize: 15).weight(.medium))
                        .foregroundStyle(theme.chrome.textPrimary.color)
                    Text(skill.author)
                        .font(theme.uiFont(11.5))
                        .foregroundStyle(theme.chrome.textSecondary.color)
                    chip(skill.category.label)
                    Spacer(minLength: 8)
                    Text(Self.compact(skill.installs))
                        .font(theme.uiFont(10.5))
                        .monospacedDigit()
                        .foregroundStyle(theme.chrome.textTertiary.color.opacity(0.8))
                }
                Text(highlighted(skill.description, hits: match.hits))
                    .font(theme.uiFont(12))
                    .foregroundStyle(theme.chrome.textSecondary.color)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            button(for: skill, isHovered: isHovered)
                .padding(.top, 2)
        }
        .padding(.horizontal, Self.gutter)
        .padding(.vertical, 16)
        .background(theme.chrome.rowHover.color.opacity(isHovered ? 0.05 : 0))
        .contentShape(.rect)
        .onHover { inside in
            if inside { hovered = skill.id } else if hovered == skill.id { hovered = nil }
        }
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .help(skill.repo)
    }

    /// The description with the words that earned the match picked out.
    ///
    /// This is the row showing its working. A search for "UI design" answers
    /// with a skill whose description says *frontend* and *visual*, and without
    /// this the ranking looks like a mistake — with it, the near-word table in
    /// `SkillCatalog.search` is visible on the page and the field teaches you
    /// what it understands.
    ///
    /// Whole words only, matched the same way the search matched them, so the
    /// underline can never land inside another word.
    private func highlighted(_ text: String, hits: Set<String>) -> AttributedString {
        guard !hits.isEmpty else { return AttributedString(text) }
        var out = AttributedString()
        var word = ""
        var gap = ""

        func flush() {
            guard !word.isEmpty else { return }
            var piece = AttributedString(word)
            if hits.contains(word.lowercased()) {
                piece.foregroundColor = theme.chrome.textPrimary.color
                piece.underlineStyle = Text.LineStyle(
                    pattern: .solid, color: theme.chrome.accent.color.opacity(0.55)
                )
            }
            out.append(AttributedString(gap))
            gap = ""
            out.append(piece)
            word = ""
        }

        for character in text {
            if character.isLetter || character.isNumber {
                word.append(character)
            } else {
                flush()
                gap.append(character)
            }
        }
        flush()
        out.append(AttributedString(gap))
        return out
    }

    /// 864,315 as "864K".
    ///
    /// Written out rather than `.formatted(.number.notation(.compactName))`,
    /// which is localised: on an Indian-English machine that renders the same
    /// number as "8.6L" — the lakh — in a column of GitHub install counts that
    /// nobody, anywhere, reads in lakhs. The count is a rough sense of scale
    /// borrowed from one American website, so it is spelled the way that
    /// website spells it, in every region.
    private static func compact(_ count: Int) -> String {
        switch count {
        case 1_000_000...:
            let millions = (Double(count) / 100_000).rounded() / 10
            return millions == millions.rounded()
                ? "\(Int(millions))M"
                : "\(millions)M"
        case 1_000...:
            return "\(count / 1_000)K"
        default:
            return "\(count)"
        }
    }

    private func chip(_ label: String) -> some View {
        Text(label.uppercased())
            .font(theme.uiFont(8.5, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(theme.chrome.textTertiary.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .overlay {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .stroke(theme.chrome.border.color.opacity(0.22), lineWidth: 1)
            }
    }

    /// The one screen a single field must get right, because it has no grid to
    /// fall back on.
    ///
    /// It says what it looked for and what came nearest, and then offers the
    /// only thing in the building that can actually answer: the agent one pane
    /// away. That is a button and not a search-as-you-type — it takes seconds
    /// and costs tokens, and no modal should wait on a model to draw its first
    /// row.
    private var nothing: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(showingShelf ? "Nothing installed yet." : "Nothing in the catalogue matches that.")
                .font(theme.uiFont(14, weight: .medium))
                .foregroundStyle(theme.chrome.textPrimary.color)

            if !showingShelf {
                if !nearest.isEmpty {
                    Text("The nearest are \(nearest.joined(separator: " and ")) — neither of them quite it.")
                        .font(theme.uiFont(12))
                        .foregroundStyle(theme.chrome.textTertiary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    askAgent("Which skill should I install for this, and why: \(asked)")
                    close()
                } label: {
                    HStack(spacing: 6) {
                        Text("Ask the agent in this tab")
                        Image(systemName: "arrow.right")
                            .font(theme.uiFont(10, weight: .semibold))
                    }
                    .font(theme.uiFont(12, weight: .medium))
                    .foregroundStyle(theme.chrome.textPrimary.color)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background {
                        Capsule().stroke(theme.chrome.accent.color.opacity(0.45), lineWidth: 1)
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, Self.gutter)
        .padding(.top, 30)
    }

    /// The best each single word could do on its own, when the whole phrase
    /// found nothing. Named rather than counted: two names say more about why
    /// the search failed than "3 partial matches" does.
    private var nearest: [String] {
        let singles = asked.split(separator: " ").flatMap { word in
            SkillCatalog.search(skills, for: String(word)).prefix(1)
        }
        var seen: Set<String> = []
        return singles.sorted { $0.score > $1.score }
            .filter { seen.insert($0.skill.name).inserted }
            .prefix(2)
            .map(\.skill.name)
    }

    // MARK: - The floor

    /// Where an install is going, and the way back to your own shelf.
    ///
    /// Installed lives here because it is the one question on this screen with
    /// no query — you come to see what you have, and no phrase can match that.
    /// The sidebar's Skills row already carries the count, so this line is the
    /// second half of a sentence the sidebar started.
    var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.chrome.border.color.opacity(0.11)).frame(height: 1)
            HStack(spacing: 8) {
                if shelf.total > 0 {
                    Button {
                        showingShelf.toggle()
                        if showingShelf { query = "" } else { isFocused = true }
                    } label: {
                        Text(showingShelf
                             ? "Back to searching"
                             : "\(shelf.total) installed · show them")
                            .font(theme.uiFont(10.5, weight: .medium))
                            .foregroundStyle(theme.chrome.textSecondary.color)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                    Text("·")
                        .font(theme.uiFont(10.5))
                        .foregroundStyle(theme.chrome.border.color.opacity(0.6))
                }

                if let home {
                    Text("Installing for \(home.agent).")
                        .font(theme.uiFont(10.5))
                        .foregroundStyle(theme.chrome.textTertiary.color)
                    Spacer(minLength: 0)
                } else {
                    // Not a warning and not a disabled state. It is a fact
                    // about what will happen, and the thing it describes is
                    // fine.
                    Text("No agent is running. Anything you add waits, and goes in when one starts.")
                        .font(theme.uiFont(10.5))
                        .foregroundStyle(theme.chrome.textTertiary.color)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Button(action: startClaude) {
                        Text("Start Claude")
                            .font(theme.uiFont(10.5, weight: .semibold))
                            .foregroundStyle(theme.chrome.textSecondary.color)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Self.gutter)
            .padding(.vertical, 13)
            .background(theme.chrome.rowHover.color.opacity(0.045))
        }
    }

    // MARK: - Add, or what has become of Add

    /// Two treatments and not four: an outlined **Add**, which is the one thing
    /// on the row asking to be pressed, and a plain word for everything that
    /// has already happened. A state that is not a call to action should not be
    /// drawn like one.
    @ViewBuilder
    private func button(for skill: Skill, isHovered: Bool) -> some View {
        if shelf.installing == skill {
            ProgressView().controlSize(.small)
        } else if shelf.queued.contains(skill) {
            action("Waiting", asked: false) { shelf.cancel(skill) }
                .help("Waiting for an agent to start. Click to cancel.")
        } else if shelf.has(skill, in: home) {
            // The word becomes the way out under the pointer, rather than a
            // second control appearing beside the first.
            action(isHovered ? "Remove" : "Installed", asked: false) {
                shelf.remove(skill, from: home)
            }
        } else {
            action("Add", asked: true) {
                // The same stroke the sidebar's switches play. Adding a skill
                // is the one thing on this screen that changes what is on
                // disk, and it is the only press here worth feeling.
                TactileClick.shared.play(.down)
                shelf.add(skill, into: home)
            }
        }
    }

    private func action(_ label: String, asked: Bool, press: @escaping () -> Void) -> some View {
        Button(action: press) {
            Text(label)
                .font(theme.uiFont(11, weight: asked ? .semibold : .medium))
                .foregroundStyle(asked ? theme.chrome.textSecondary.color
                                       : theme.chrome.textTertiary.color)
                .padding(.horizontal, asked ? 12 : 2)
                .frame(height: 24)
                .background {
                    // A hairline, not a fill. The accent capsule this replaced
                    // put the loudest colour in the theme on the least
                    // consequential control on the screen, two hundred times.
                    Capsule().stroke(
                        theme.chrome.border.color.opacity(asked ? 0.35 : 0),
                        lineWidth: 1
                    )
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // The word swaps rather than crossfades: Add → Installed is a change of
        // fact, and a fade makes it look like it is still deciding.
        .contentTransition(.identity)
    }
}
