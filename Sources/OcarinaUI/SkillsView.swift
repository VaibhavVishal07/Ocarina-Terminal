import SwiftUI

/// The skills browser: three lists behind three tabs, and one card under all of
/// them.
///
/// The three sections are the right shape — where to begin, everything, and
/// what you have are genuinely three questions. What was wrong was underneath
/// them: each opened with a different kind of thing, so the modal reshuffled
/// itself every time you moved between them. The first page led with a
/// paragraph and ended with a link that went to the second page, which was
/// already a tab above it. The second led with a search field and a row of
/// pills. The third led with uppercase headings over sections. Three tabs, four
/// navigation idioms, and no two of them starting at the same height.
///
/// Now everything above the tabs is constant — the title, the line saying what
/// a skill is, and the search field, which searches whatever you are looking at
/// — and everything below them is cards. One tab has a row of filter pills,
/// because it is the only one holding two hundred things; that is a filter
/// *inside* a list rather than a second way of choosing which list, and it is
/// one level deep.
///
/// The card is the same object on all three. What changes between them is what
/// goes in its two lines, not the card.
struct SkillsView: View {
    @Environment(\.theme) private var theme

    /// Where an install would go, and what to call it. Nil on a plain shell —
    /// which is a state this view is built for rather than one it refuses to
    /// open in.
    let home: SkillHome?
    let shelf: SkillShelf
    /// Starts Claude, for the line that offers to.
    let startClaude: () -> Void
    let close: () -> Void

    @State private var skills: [Skill] = SkillCatalog.load()
    @State private var page: Page = .start
    @State private var search = ""
    @State private var category: Skill.Category?
    @State private var hovered: String?
    @FocusState private var isSearchFocused: Bool

    /// Wide enough for two columns of card and no wider.
    private static let width: CGFloat = 600
    private static let height: CGFloat = 660
    private static let gutter: CGFloat = 22
    private static let cardHeight: CGFloat = 86

    /// The gap between cards, and the same figure the rest of the panel is
    /// spaced on. Everything vertical here is 6, 14 or 20 — one scale rather
    /// than whatever each pair of things happened to need, which is what made
    /// the panel read as tight in some places and loose in others.
    private static let gap: CGFloat = 14

    private static let columns = [
        GridItem(.flexible(), spacing: gap),
        GridItem(.flexible(), spacing: gap),
    ]

    enum Page: Equatable, Hashable { case start, browse, installed }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            content
            footnote
        }
        .frame(width: Self.width, height: Self.height)
        .background { OcarinaWindowView.panelSurface(theme, at: .top) }
        .clipShape(OcarinaWindowView.PanelStyle.shape)
        .overlay {
            OcarinaWindowView.PanelStyle.shape
                .stroke(theme.chrome.border.color.opacity(0.22), lineWidth: 1)
        }
        .onAppear {
            shelf.refresh()
            // Opens on what you have once you have anything. Somebody with four
            // skills installed came here to look at them or to add a fifth, and
            // neither of those starts with the beginners' shelf.
            if shelf.total > 0 { page = .installed }
            isSearchFocused = true
        }
        // Typing is a search of the catalogue, whichever list you were on.
        // Filtering eight starters down to two is not a thing anybody wants,
        // and leaving somebody typing into a list that cannot answer them is
        // the sort of dead end that reads as the search box being broken.
        .onChange(of: search) { _, text in
            if !text.isEmpty, page != .browse { page = .browse }
        }
    }

    // MARK: - Everything above the tabs, which never changes

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Skills")
                        .font(theme.uiFont(15.5, weight: .semibold))
                        .foregroundStyle(theme.chrome.textPrimary.color)
                    Spacer(minLength: 8)
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(theme.uiFont(11, weight: .semibold))
                            .foregroundStyle(theme.chrome.textTertiary.color)
                            .frame(width: 20, height: 20)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }
                // What the thing is, in one line, always. Nobody arriving from
                // a sidebar row called "Skills" has been told, and a catalogue
                // answers "which one" to somebody not told "of what".
                Text("Written instructions your agent reads when a task calls for it.")
                    .font(theme.uiFont(11.5))
                    .foregroundStyle(theme.chrome.textTertiary.color)
            }

            searchField
        }
        .padding(.horizontal, Self.gutter)
        .padding(.top, 20)
        .padding(.bottom, 18)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(theme.uiFont(11.5, weight: .medium))
                .foregroundStyle(theme.chrome.textTertiary.color)
            TextField("Search \(skills.count) skills", text: $search)
                .textFieldStyle(.plain)
                .font(theme.uiFont(12.5))
                .foregroundStyle(theme.chrome.textPrimary.color)
                .focused($isSearchFocused)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(theme.uiFont(11.5))
                        .foregroundStyle(theme.chrome.textTertiary.color)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.chrome.rowHover.color.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(
                            theme.chrome.border.color.opacity(isSearchFocused ? 0.3 : 0.14),
                            lineWidth: 1
                        )
                }
        }
        .animation(.easeOut(duration: 0.12), value: isSearchFocused)
    }

    // MARK: - The three sections

    /// Tabs sitting *on* the rule rather than floating above a separate one.
    ///
    /// The underline and the divider used to be two lines a few points apart,
    /// which is the sort of thing that makes a panel look assembled rather than
    /// drawn. One rule across the full width, and the active tab's mark is a
    /// heavier length of that same rule.
    private var tabs: some View {
        HStack(spacing: 20) {
            tab("Start here", page: .start)
            tab("Browse all", page: .browse)
            tab(shelf.total > 0 ? "Installed \(shelf.total)" : "Installed", page: .installed)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.gutter)
        .background(alignment: .bottom) {
            Rectangle()
                .fill(theme.chrome.border.color.opacity(0.13))
                .frame(height: 1)
        }
    }

    private func tab(_ label: String, page destination: Page) -> some View {
        let isOn = page == destination
        return Button {
            page = destination
            // A tab is a change of list, so the filter inside the long list
            // does not survive leaving it.
            if destination != .browse { category = nil }
        } label: {
            Text(label)
                .font(theme.uiFont(12, weight: isOn ? .semibold : .medium))
                .foregroundStyle(isOn ? theme.chrome.textPrimary.color
                                      : theme.chrome.textTertiary.color)
                .padding(.top, 2)
                .padding(.bottom, 11)
                // An overlay rather than a rule stacked under the label: a
                // `Rectangle` in a `VStack` has no width of its own, so it
                // swallowed the row's free space and pushed the three tabs
                // apart to the panel's edges. This one is exactly as wide as
                // the word it belongs to.
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(theme.chrome.textPrimary.color.opacity(isOn ? 0.6 : 0))
                        .frame(height: 1.5)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: isOn)
    }

    // MARK: - Everything below them, which is cards

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            // The one thing that is not on every tab. It is a filter inside the
            // long list, not a second way of choosing which list, and it
            // belongs only to the tab that holds two hundred things.
            if page == .browse { pills }

            let rows = shown
            if rows.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVGrid(columns: Self.columns, spacing: Self.gap) {
                        ForEach(rows) { card($0) }
                    }
                    .padding(.horizontal, Self.gutter)
                    .padding(.top, 20)
                    .padding(.bottom, 22)

                    // What is on disk is not always what this app put there. A
                    // skill installed by hand, or by another machine's sync, is
                    // in the directory and is read by the agent, and a list
                    // that silently omitted it would be a list of what Ocarina
                    // remembers rather than of what the agent has.
                    if page == .installed, shelf.installed.count > rows.count {
                        Text("\(shelf.installed.count - rows.count) more in the folder that are not in this catalogue.")
                            .font(theme.uiFont(10.5))
                            .foregroundStyle(theme.chrome.textTertiary.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Self.gutter)
                            .padding(.bottom, 22)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var pills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                pill("All", isOn: category == nil) { category = nil }
                // Design leads, because the app does. See `Category.ordered`.
                ForEach(Skill.Category.ordered, id: \.self) { option in
                    pill(option.label, isOn: category == option) {
                        // Pressing the one already on clears it, so a filter is
                        // never a thing you cannot get out of without hunting
                        // for "All".
                        category = category == option ? nil : option
                    }
                }
            }
            .padding(.horizontal, Self.gutter)
            .padding(.vertical, 1)
        }
        .frame(height: 28)
        .padding(.top, 18)
    }

    func pill(_ label: String, isOn: Bool, press: @escaping () -> Void) -> some View {
        Button(action: press) {
            Text(label)
                .font(theme.uiFont(11, weight: isOn ? .semibold : .medium))
                .foregroundStyle(isOn ? theme.chrome.textPrimary.color
                                      : theme.chrome.textSecondary.color)
                .padding(.horizontal, 11)
                .frame(height: 24)
                .background {
                    Capsule()
                        .fill(theme.chrome.rowHover.color.opacity(isOn ? 0.16 : 0.05))
                        .overlay {
                            Capsule().stroke(
                                theme.chrome.border.color.opacity(isOn ? 0.34 : 0.13),
                                lineWidth: 1
                            )
                        }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.1), value: isOn)
    }

    /// The plain-language line for each starter, by id.
    private var plainly: [String: String] {
        Dictionary(uniqueKeysWithValues:
            SkillCatalog.starting(from: skills).map { ($0.skill.id, $0.plainly) })
    }

    private var shown: [Skill] {
        switch page {
        case .start:
            return SkillCatalog.starting(from: skills).map(\.skill)
        case .browse:
            return SkillCatalog.filter(skills, search: search, category: category)
        case .installed:
            // Waiting first, then what is on disk. The card's own button says
            // which is which, so the order is the only grouping this needs —
            // it was two uppercase headings over two grids.
            let mine = skills.filter { shelf.installed.contains($0.name) }
            let pool = shelf.queued + mine.filter { !shelf.queued.contains($0) }
            return SkillCatalog.filter(pool, search: search, category: nil)
        }
    }

    /// One empty state, worded from what was asked for.
    private var empty: some View {
        VStack(spacing: 10) {
            Text(page == .installed && search.isEmpty
                 ? "Nothing installed yet"
                 : "Nothing matches")
                .font(theme.uiFont(13, weight: .medium))
                .foregroundStyle(theme.chrome.textSecondary.color)
            Button {
                search = ""
                category = nil
                page = .start
            } label: {
                Text("See where to start")
                    .font(theme.uiFont(11.5, weight: .medium))
                    .foregroundStyle(theme.chrome.textTertiary.color)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Where an install is going, said once, at the foot of the panel.
    ///
    /// It was in the title — "Skills for Claude Code" — which put the answer
    /// above the question. Down here it reads as the footnote it is, and on a
    /// plain shell it has something useful to say instead of disappearing. It
    /// carries a fill of its own so it reads as the panel's floor rather than
    /// as a line of text that happened to end up at the bottom.
    private var footnote: some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.chrome.border.color.opacity(0.11)).frame(height: 1)
            HStack(spacing: 6) {
                if let home {
                    Text("Installing for \(home.agent).")
                        .font(theme.uiFont(10.5))
                        .foregroundStyle(theme.chrome.textTertiary.color)
                } else {
                    // Not a warning and not a disabled state. It is a fact about
                    // what will happen, and the thing it describes is fine.
                    Text("No agent is running. Anything you add waits, and goes in when one starts.")
                        .font(theme.uiFont(10.5))
                        .foregroundStyle(theme.chrome.textTertiary.color)
                    Spacer(minLength: 6)
                    Button(action: startClaude) {
                        Text("Start Claude")
                            .font(theme.uiFont(10.5, weight: .semibold))
                            .foregroundStyle(theme.chrome.textSecondary.color)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Self.gutter)
            .padding(.vertical, 13)
            .background(theme.chrome.rowHover.color.opacity(0.045))
        }
    }

    // MARK: - One card

    /// A skill: two lines and a button, in that arrangement everywhere.
    ///
    /// It carried four things — a headline, a supporting line, the author and
    /// the button — which is one more than a card this size can lay out without
    /// the eye having to decide what to read next. The author moved onto the
    /// supporting line rather than off the card: a skill is instructions an
    /// agent will follow, so the publisher is most of the decision.
    ///
    /// On the starting shelf the plain-language line leads and the folder name
    /// joins the author underneath. Everywhere else the folder name leads,
    /// because that is what you are searching by and what the agent will call
    /// it. Same two slots either way.
    func card(_ skill: Skill) -> some View {
        let isHovered = hovered == skill.id
        let plain = page == .start ? plainly[skill.id] : nil
        let title = plain ?? skill.name
        let support = plain == nil
            ? "\(skill.author) · \(skill.headline)"
            : "\(skill.name) · \(skill.author)"

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(theme.uiFont(12.5, weight: .semibold))
                    .foregroundStyle(theme.chrome.textPrimary.color)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(support)
                    .font(theme.uiFont(10.5))
                    .foregroundStyle(theme.chrome.textTertiary.color)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            button(for: skill, isHovered: isHovered)
        }
        .padding(.horizontal, 14)
        .frame(height: Self.cardHeight)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.chrome.rowHover.color.opacity(isHovered ? 0.085 : 0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            theme.chrome.border.color.opacity(isHovered ? 0.22 : 0.09),
                            lineWidth: 1
                        )
                }
        }
        .contentShape(.rect)
        .onHover { inside in
            if inside { hovered = skill.id } else if hovered == skill.id { hovered = nil }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help("\(skill.description)\n\n\(skill.repo)")
    }

    /// Add, or what has become of Add.
    ///
    /// Two treatments and not four: an outlined **Add**, which is the one thing
    /// on the card asking to be pressed, and a plain word for everything that
    /// has already happened. A state that is not a call to action should not be
    /// drawn like one, and four differently weighted buttons for one control
    /// was most of why this page read as busy.
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
            action("Add", asked: true) { shelf.add(skill, into: home) }
        }
    }

    private func action(_ label: String, asked: Bool, press: @escaping () -> Void) -> some View {
        Button(action: press) {
            Text(label)
                .font(theme.uiFont(10.5, weight: asked ? .semibold : .medium))
                .foregroundStyle(asked ? theme.chrome.textSecondary.color
                                       : theme.chrome.textTertiary.color)
                .padding(.horizontal, asked ? 11 : 2)
                .frame(height: 22)
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
    }
}
