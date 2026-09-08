import SwiftUI

/// Jump between terminals by what they are doing.
///
/// Same ordering as the tab strip: the task leads, the process and project
/// follow underneath.
struct CommandPaletteView: View {
    @Bindable var model: OcarinaModel
    @State private var query: String = ""
    @FocusState private var isSearchFocused: Bool

    private var matches: [TabItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        // Nothing typed yet: most recently looked at first, not the column's
        // own order. The palette is what you open when the session you want is
        // not the one beside you — and with ten open, the two you are moving
        // between are almost never neighbours in the sidebar. Typing hands the
        // order back to the match.
        guard !trimmed.isEmpty else { return model.tabsByRecency }
        return model.tabs.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || ($0.subtitle?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Go to terminal", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($isSearchFocused)
                    .onSubmit { select(matches.first) }
            }
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(matches) { tab in
                        Button {
                            select(tab)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tab.title)
                                    .font(.system(size: 15, weight: .medium))
                                if let subtitle = tab.subtitle {
                                    Text(subtitle)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .background(
                            tab.id == model.selectedTabID ? .white.opacity(0.06) : .clear
                        )
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .frame(width: 460)
        .background(.regularMaterial)
        .onAppear { isSearchFocused = true }
    }

    private func select(_ tab: TabItem?) {
        guard let tab else { return }
        model.selectTab(tab.id)
        model.isCommandPaletteVisible = false
    }
}
