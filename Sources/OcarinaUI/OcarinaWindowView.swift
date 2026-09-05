import SwiftUI

public struct OcarinaWindowView: View {
    private let model: OcarinaModel

    public init(model: OcarinaModel) {
        self.model = model
    }

    public var body: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            // With nothing open there is nothing to strip: the empty state
            // gets the whole window rather than sitting under an empty bar.
            if !model.tabs.isEmpty {
                TabStripView(model: model)
                    // A tool tip hangs below the strip, and the terminal is
                    // drawn after it in the stack.
                    .zIndex(1)
            }

            ZStack {
                // Not fully opaque: the terminal view itself is clear, so this
                // is the only thing between the text and the window's glass.
                Color.black.opacity(0.72)
                if let session = model.selectedSession {
                    // The terminal had no inset at all: the first column sat on
                    // the window edge (clipping its left half) and the top line
                    // ran straight into the tab strip.
                    TerminalHostView(session: session)
                        .id(session.id)
                        .padding(.leading, 10)
                        .padding(.trailing, 6)
                        .padding(.top, 8)
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
    }
}
