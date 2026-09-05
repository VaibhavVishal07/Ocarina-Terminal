import SwiftUI

/// The drawer that carries the commands you would otherwise go and look up.
///
/// It does not run anything. Choosing a recipe types its command at the prompt
/// and leaves the cursor after it, so the last act is always yours. That is
/// deliberate on two counts: nothing executes that you did not trigger, and you
/// see the command each time, which is how you eventually stop needing this
/// drawer at all.
struct QuickActionsView: View {
    @Environment(\.theme) private var theme
    @Bindable var model: OcarinaModel

    @State private var query = ""
    @State private var expanded: String?
    @FocusState private var searching: Bool

    private var groups: [RecipeGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return model.recipes }
        return model.recipes.compactMap { group in
            let hits = group.items.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed)
                    || $0.blurb.localizedCaseInsensitiveContains(trimmed)
                    || $0.command.localizedCaseInsensitiveContains(trimmed)
            }
            return hits.isEmpty ? nil : RecipeGroup(id: group.id, title: group.title, items: hits)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            search
            Rectangle().fill(theme.chrome.border.color.opacity(0.14)).frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if groups.isEmpty { empty } else {
                        ForEach(groups) { group in
                            Text(group.title)
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.08)
                                .textCase(.uppercase)
                                .foregroundStyle(theme.chrome.textTertiary.color)
                                .padding(.horizontal, 16)
                                .padding(.top, 18)
                                .padding(.bottom, 6)

                            ForEach(group.items) { recipe in
                                row(recipe)
                            }
                        }
                    }
                }
                .padding(.bottom, 14)
            }
            .frame(maxHeight: 380)

            footer
        }
        .frame(width: 520)
        .background(theme.chrome.panelTop.color)
        .onAppear { searching = true }
    }

    private var search: some View {
        HStack(spacing: 9) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(theme.chrome.textTertiary.color)
            TextField("What do you want to do?", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(theme.chrome.textPrimary.color)
                .focused($searching)
            Text("esc")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.chrome.textTertiary.color)
        }
        .padding(14)
    }

    private var empty: some View {
        Text("Nothing here matches “\(query)”.")
            .font(.system(size: 13))
            .foregroundStyle(theme.chrome.textSecondary.color)
            .padding(16)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.chrome.border.color.opacity(0.14)).frame(height: 1)
            HStack(spacing: 6) {
                Image(systemName: "return")
                    .font(.system(size: 9, weight: .bold))
                Text("Choosing types the command at your prompt. You press Return to run it.")
                    .font(.system(size: 11))
            }
            .foregroundStyle(theme.chrome.textTertiary.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func row(_ recipe: Recipe) -> some View {
        let isOpen = expanded == recipe.id

        VStack(alignment: .leading, spacing: 0) {
            Button {
                // First press opens it, so the explanation is read before the
                // command is anywhere near the prompt.
                expanded = isOpen ? nil : recipe.id
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recipe.name)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(theme.chrome.textPrimary.color)
                        Text(recipe.blurb)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.chrome.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.chrome.textTertiary.color)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isOpen { details(recipe) }
        }
        .background(isOpen ? theme.chrome.rowHover.color.opacity(0.05) : .clear)
    }

    private func details(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recipe.explain)
                .font(.system(size: 12))
                .foregroundStyle(theme.chrome.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)

            commandRow(recipe.command, primary: true)

            ForEach(recipe.alternatives ?? [], id: \.command) { alternative in
                VStack(alignment: .leading, spacing: 4) {
                    Text(alternative.label)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(theme.chrome.textTertiary.color)
                    commandRow(alternative.command, primary: false)
                }
            }

            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 9))
                Text("Checked against \(recipe.docs) on \(recipe.lastVerified)")
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(theme.chrome.textTertiary.color)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func commandRow(_ command: String, primary: Bool) -> some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(theme.chrome.textPrimary.color)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Put it at my prompt") { insert(command) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(theme.chrome.accent.color)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(theme.terminal.background.color.opacity(primary ? 1 : 0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(theme.chrome.border.color.opacity(0.14), lineWidth: 1)
                }
        }
    }

    private func insert(_ command: String) {
        model.typeAtPrompt(command)
        model.isQuickActionsVisible = false
    }
}
