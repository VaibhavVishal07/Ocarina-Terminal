import SwiftUI

public struct MajoraWindowView: View {
    @State private var model = MajoraModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // With nothing open there is nothing to strip: the empty state
            // gets the whole window rather than sitting under an empty bar.
            if !model.tabs.isEmpty {
                TabStripView(model: model)
                Divider().opacity(0.3)
            }

            ZStack {
                Color.black
                if let session = model.selectedSession {
                    TerminalHostView(session: session)
                        .id(session.id)
                } else {
                    EmptyStateView { model.newTab() }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .onAppear { model.start() }
        .sheet(isPresented: $model.isCommandPaletteVisible) {
            CommandPaletteView(model: model)
        }
        .background {
            // Keyboard shortcuts, kept out of the visual tree.
            Group {
                Button("") { model.newTab() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("") {
                    if let id = model.selectedTabID { model.closeTab(id) }
                }
                .keyboardShortcut("w", modifiers: .command)
                Button("") { model.isCommandPaletteVisible.toggle() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            .opacity(0)
        }
    }
}
