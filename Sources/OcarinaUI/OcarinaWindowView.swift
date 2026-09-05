import SwiftUI

public struct OcarinaWindowView: View {
    /// The smallest the window may get. Below this the sidebar is pushed off
    /// the window's left edge and clipped — the tab names lose their first
    /// characters and the rows look jammed into the corner — so the window is
    /// held to it rather than the content merely refusing to shrink.
    public static let minimumSize = CGSize(width: 820, height: 420)

    private let model: OcarinaModel

    public init(model: OcarinaModel) {
        self.model = model
    }

    public var body: some View {
        @Bindable var model = model
        return HStack(spacing: 0) {
            // With nothing open there is no list to draw: the empty state gets
            // the whole window rather than sitting beside an empty sidebar.
            if !model.tabs.isEmpty {
                TabSidebarView(model: model)
                    // A tool tip hangs off the sidebar's edge, and the terminal
                    // is drawn after it in the stack.
                    .zIndex(1)
            }

            ZStack {
                // Not fully opaque: the terminal view itself is clear, so this
                // is the only thing between the text and the window's glass.
                Color.black.opacity(0.72)
                if let session = model.selectedSession {
                    // The terminal had no inset at all: the first column sat on
                    // the window edge (clipping its left half) and the top line
                    // ran under the titlebar.
                    TerminalHostView(session: session)
                        .id(session.id)
                        .padding(.leading, 10)
                        .padding(.trailing, 6)
                        .padding(.top, 34)
                } else {
                    EmptyStateView { model.newTab() }
                }
            }
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        .onAppear { model.start() }
        .sheet(isPresented: $model.isCommandPaletteVisible) {
            CommandPaletteView(model: model)
        }
    }
}
