import SwiftUI
import SwiftTerm

/// Hosts a session's terminal view. The view is owned by the session, not by
/// SwiftUI, so scrollback survives tab switches and re-layouts.
struct TerminalHostView: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> DroppableTerminalView {
        session.terminalView
    }

    func updateNSView(_ view: DroppableTerminalView, context: Context) {}
}
