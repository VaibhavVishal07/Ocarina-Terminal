import AppKit
import Combine
import SwiftUI

/// Commits an edit when the next click lands anywhere but the field.
///
/// A rename had two ways out: Return, and losing SwiftUI's focus. The second
/// never happened. `@FocusState` tracks SwiftUI's own idea of focus, and the
/// thing you click to leave the field is usually the terminal — an AppKit view
/// that takes the window's first responder without SwiftUI hearing about it.
/// The same mismatch is already documented where the field takes focus, which
/// has to drop the responder by hand before `@FocusState` can land. So the
/// field stayed open, holding a name that had been typed and not applied,
/// until Return was pressed.
///
/// A local mouse-down monitor is the level this actually happens at. It sees
/// the click before the window dispatches it, which is what makes the test
/// simple: the field editor is still the first responder at that moment, so
/// the question is only whether the click landed inside it.
private struct CommitOnClickOutside: ViewModifier {
    let commit: () -> Void

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            // The field exists only while renaming, so its lifetime is the
            // monitor's — nothing has to track a flag.
            .onAppear(perform: start)
            .onDisappear(perform: stop)
            // Switching away from the app is leaving the field too, and would
            // otherwise strand the edit until you came back.
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
                commit()
            }
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            if isOutsideField(event) { commit() }
            // Always handed back: leaving the field should not also swallow
            // the click that left it. Clicking another tab selects it.
            return event
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func isOutsideField(_ event: NSEvent) -> Bool {
        guard let window = event.window ?? NSApp.keyWindow else { return false }
        // Focus has not settled yet — the field asks for it one runloop turn
        // after appearing. A click in this gap is the one that opened the
        // field, and must not close it again.
        guard let responder = window.firstResponder as? NSView else { return false }

        // The shared field editor is an `NSTextView` living inside the control
        // it edits, and the control is the box the pointer is aiming at. Using
        // the editor's own bounds would treat the field's padding as outside.
        let field = (responder as? NSTextView)?.delegate as? NSView ?? responder
        return !field.bounds.contains(field.convert(event.locationInWindow, from: nil))
    }
}

extension View {
    /// Treats a click anywhere but this field as a commit, the way Return is.
    func commitOnClickOutside(perform commit: @escaping () -> Void) -> some View {
        modifier(CommitOnClickOutside(commit: commit))
    }
}
