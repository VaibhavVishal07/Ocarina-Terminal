import SwiftUI

/// The skills browser: two hundred folders of instructions, and one click to
/// put one where the agent in front of you will read it.
///
/// It opens on a tab running an agent and nowhere else, because everything in
/// it is answered by which agent that is. The same skill installs to a
/// different directory for Claude Code than for Codex, the row's button says
/// which, and on a plain shell there is no answer to give — so rather than
/// showing the browser with the install disabled, the way in is not there.
struct SkillsView: View {
    @Environment(\.theme) private var theme

    /// Where an install would go, and what to call it. The whole view is
    /// about this one value.
    let home: SkillHome
    let close: () -> Void

    @State private var skills: [Skill] = SkillCatalog.load()
    @State private var installed: Set<String> = []
    @State private var search = ""
    @State private var category: Skill.Category?
    /// The one being fetched, if any. One at a time: two skills arriving at
    /// once is two progress spinners and no way to tell which failed.
    @State private var working: String?
    @State private var failure: String?
    @State private var hovered: String?
    @FocusState private var isSearchFocused: Bool

    /// Wide enough for two columns of card, because one column of two hundred
    /// rows is a list you read and two columns of cards is a shelf you scan.
    /// The eye takes a pair at a time and the descriptions stop being the
    /// widest thing on screen.
    private static let width: CGFloat = 780
    private static let height: CGFloat = 620
    private static let gutter: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            header
            filters
            Rectangle().fill(theme.chrome.border.color.opacity(0.12)).frame(height: 1)
            if let failure { trouble(failure) }
            list
        }
        .frame(width: Self.width, height: Self.height)
        .background { OcarinaWindowView.panelSurface(theme, at: .top) }
        .clipShape(OcarinaWindowView.PanelStyle.shape)
        .overlay {
            OcarinaWindowView.PanelStyle.shape
                .stroke(theme.chrome.border.color.opacity(0.22), lineWidth: 1)
        }
        .onAppear {
            installed = home.installedNames()
            isSearchFocused = true
        }
    }

    // MARK: - Head

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Skills")
                .font(theme.uiFont(15, weight: .semibold))
                .foregroundStyle(theme.chrome.textPrimary.color)
            // Not decoration. A skill is instructions the agent will follow, so
            // where it is going is part of what you are agreeing to.
            Text("for \(home.agent)")
                .font(theme.uiFont(11.5, weight: .medium))
                .foregroundStyle(theme.chrome.textTertiary.color)
            Spacer(minLength: 8)
            // What is on the shelf, and what the filter has left of it. A
            // catalogue that never says how big it is reads as a short list
            // that happens to scroll.
            Text(tally)
                .font(theme.uiFont(10.5, weight: .medium))
                .foregroundStyle(theme.chrome.textTertiary.color)
                .monospacedDigit()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(theme.uiFont(11, weight: .semibold))
                    .foregroundStyle(theme.chrome.textTertiary.color)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Self.gutter)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    /// "216 skills", or "12 of 216" once something is filtering.
    private var tally: String {
        let shown = matches.count
        return shown == skills.count ? "\(skills.count) skills" : "\(shown) of \(skills.count)"
    }

    private var filters: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(theme.uiFont(11, weight: .medium))
                    .foregroundStyle(theme.chrome.textTertiary.color)
                TextField("Search skills", text: $search)
                    .textFieldStyle(.plain)
                    .font(theme.uiFont(12.5))
                    .foregroundStyle(theme.chrome.textPrimary.color)
                    .focused($isSearchFocused)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.chrome.rowHover.color.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(theme.chrome.border.color.opacity(0.14), lineWidth: 1)
                    }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("All", isOn: category == nil) { category = nil }
                    ForEach(Skill.Category.allCases, id: \.self) { option in
                        chip(option.label, isOn: category == option) {
                            // Pressing the one already on clears it, so the
                            // filter never becomes a thing you cannot get out
                            // of without finding "All" again.
                            category = category == option ? nil : option
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(height: 26)
        }
        .padding(.horizontal, Self.gutter)
        .padding(.bottom, 14)
    }

    /// What went wrong, where the row that failed was.
    ///
    /// Said out loud rather than left as a button that quietly did nothing.
    /// Half of what can go wrong here is somebody's network or GitHub's rate
    /// limit, and both of those look exactly like a broken app if the only
    /// evidence is an install that did not happen.
    private func trouble(_ message: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle")
                .font(theme.uiFont(10.5, weight: .medium))
            Text(message)
                .font(theme.uiFont(11.5))
                .lineLimit(2)
            Spacer(minLength: 4)
            Button { failure = nil } label: {
                Image(systemName: "xmark").font(theme.uiFont(9, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(theme.chrome.textSecondary.color)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.terminal.ansi[1].color.opacity(0.12))
    }

    func chip(_ label: String, isOn: Bool, press: @escaping () -> Void) -> some View {
        Button(action: press) {
            Text(label)
                .font(theme.uiFont(11, weight: .medium))
                .foregroundStyle(isOn ? theme.chrome.textPrimary.color
                                      : theme.chrome.textSecondary.color)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background {
                    Capsule()
                        .fill(theme.chrome.accent.color.opacity(isOn ? 0.22 : 0.06))
                        .overlay {
                            Capsule().stroke(
                                theme.chrome.accent.color.opacity(isOn ? 0.5 : 0.14),
                                lineWidth: 1
                            )
                        }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    private var matches: [Skill] {
        SkillCatalog.filter(skills, search: search, category: category)
    }

    @ViewBuilder
    private var list: some View {
        let rows = matches
        if rows.isEmpty {
            VStack(spacing: 7) {
                Text("Nothing matches")
                    .font(theme.uiFont(13, weight: .medium))
                    .foregroundStyle(theme.chrome.textSecondary.color)
                Text("\(skills.count) skills, and none of them this.")
                    .font(theme.uiFont(11.5))
                    .foregroundStyle(theme.chrome.textTertiary.color)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                    ],
                    spacing: 10
                ) {
                    ForEach(rows) { card($0) }
                }
                .padding(.horizontal, Self.gutter)
                .padding(.vertical, 14)
            }
        }
    }

    /// One skill on the shelf.
    ///
    /// The card is calm until you point at it. Two hundred of these with a
    /// border, a fill and a lit button each is the wall this replaced — every
    /// row shouting at the same volume, so nothing on the page had any weight
    /// and the only way through it was to read all of it. At rest a card is a
    /// mark, a name, a publisher and one line; the fill and the button arrive
    /// under the pointer, which is also the only moment either is any use.
    func card(_ skill: Skill) -> some View {
        let isHere = installed.contains(skill.name)
        let isBusy = working == skill.id
        let isHovered = hovered == skill.id

        return HStack(alignment: .top, spacing: 11) {
            // The category, as a shape. It is what makes the grid scannable
            // before a word of it has been read — nine kinds, one mark each,
            // in the same place on every card.
            Image(systemName: skill.category.symbol)
                .font(theme.uiFont(12, weight: .medium))
                .foregroundStyle(isHere ? theme.board.lit.color
                                        : theme.chrome.textTertiary.color)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.chrome.rowHover.color.opacity(0.07))
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .font(theme.uiFont(12.5, weight: .semibold))
                        .foregroundStyle(theme.chrome.textPrimary.color)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    trailing(for: skill, isHere: isHere, isBusy: isBusy, isHovered: isHovered)
                }
                // Who wrote it, always. A skill is instructions the agent will
                // follow, so the publisher is most of the decision.
                Text(skill.author)
                    .font(theme.uiFont(10, weight: .medium))
                    .foregroundStyle(theme.chrome.textTertiary.color)
                    .lineLimit(1)
                // One line, and a line that ends where a sentence does. See
                // `Skill.headline`: these descriptions are written for the
                // agent, which reads all of them, and clipping the raw text to
                // the card's width broke every card mid-word.
                Text(skill.headline)
                    .font(theme.uiFont(11))
                    .foregroundStyle(theme.chrome.textSecondary.color)
                    .lineLimit(1)
                    .padding(.top, 3)
            }
        }
        .padding(11)
        .frame(height: 74, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.chrome.rowHover.color.opacity(isHovered ? 0.07 : 0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            theme.chrome.border.color.opacity(isHovered ? 0.18 : 0),
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

    /// The right-hand end of a card's title line.
    ///
    /// Nothing at all until it is either installed or under the pointer. Two
    /// hundred Install buttons drawn at once is two hundred things asking to
    /// be pressed, and a shelf where everything is asking is a shelf you
    /// cannot read.
    @ViewBuilder
    private func trailing(
        for skill: Skill, isHere: Bool, isBusy: Bool, isHovered: Bool
    ) -> some View {
        if isBusy {
            ProgressView().controlSize(.small)
        } else if isHere {
            Button { remove(skill) } label: {
                // A tick that becomes the way out, rather than a second
                // control appearing beside the first.
                Text(isHovered ? "Remove" : "Installed")
                    .font(theme.uiFont(9.5, weight: .medium))
                    .foregroundStyle(theme.chrome.textTertiary.color)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else if isHovered {
            Button { install(skill) } label: {
                Text("Install")
                    .font(theme.uiFont(9.5, weight: .semibold))
                    .foregroundStyle(theme.chrome.textPrimary.color)
                    .padding(.horizontal, 9)
                    .frame(height: 19)
                    .background {
                        Capsule().fill(theme.chrome.accent.color.opacity(0.26))
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Doing it

    private func install(_ skill: Skill) {
        guard working == nil else { return }
        working = skill.id
        failure = nil
        Task { @MainActor in
            do {
                try await SkillInstaller.install(skill, into: home)
                installed = home.installedNames()
            } catch {
                failure = error.localizedDescription
            }
            working = nil
        }
    }

    private func remove(_ skill: Skill) {
        try? SkillInstaller.remove(skill, from: home)
        installed = home.installedNames()
    }
}
