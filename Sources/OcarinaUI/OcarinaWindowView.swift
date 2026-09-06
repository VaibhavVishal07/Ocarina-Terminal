import AppKit
import SwiftUI

public struct OcarinaWindowView: View {
    /// The smallest the window may get. Below this the sidebar is pushed off
    /// the window's left edge and clipped — the tab names lose their first
    /// characters and the rows look jammed into the corner — so the window is
    /// held to it rather than the content merely refusing to shrink.
    public static let minimumSize = CGSize(width: 820, height: 420)

    /// The terminal's gap from the top and the left, which are one number
    /// because they are one gap seen twice.
    ///
    /// 22 rather than 24 because the terminal cell carries about 2pt of its
    /// own above and to the left of the first glyph. Measured off the rendered
    /// window, 22 here is the 24 you see; 24 here would read as 26.
    private static let terminalInset: CGFloat = 22

    private let model: OcarinaModel

    public init(model: OcarinaModel) {
        self.model = model
    }

    /// Read from the store, not from the environment.
    ///
    /// This view is the one that *publishes* the theme, and `.environment` only
    /// reaches descendants — a view cannot read a value it sets on itself. Doing
    /// so silently handed the terminal's bed the compiled-in fallback while
    /// every view below it drew the chosen theme, so a light theme came up with
    /// a pale sidebar against a near-black terminal.
    private var theme: Theme { model.themes.theme }

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
                theme.chrome.bed.color
                    .opacity(theme.chrome.bedOpacity)
                    .ignoresSafeArea(edges: .top)
                if let session = model.selectedSession {
                    // The terminal had no inset at all: the first column sat on
                    // the window edge (clipping its left half) and the top line
                    // ran under the titlebar.
                    //
                    // The top was 34 against a leading 10, so the first line
                    // sat three times as far from the titlebar as the first
                    // column did from the edge. That 34 was clearing the
                    // titlebar a second time: the window's safe area already
                    // does it — which is what the sidebar relies on, and why
                    // it needs nothing but its own 10 of breathing room. Same
                    // number on both sides now, and the same number the
                    // sidebar uses, so the two halves start together.
                    TerminalHostView(session: session)
                        .id(session.id)
                        .padding(.leading, Self.terminalInset)
                        .padding(.trailing, 6)
                        .padding(.top, Self.terminalInset)
                } else {
                    EmptyStateView { model.newTab() }
                }
            }
            .overlay(alignment: .top) {
                if let code = model.selectedFailure, model.isErrorBannerVisible {
                    ErrorBannerView(
                        exitCode: code,
                        hasAgent: ErrorHelp.installedAgent() != nil,
                        explain: { model.explainLastFailure() },
                        dismiss: { model.isErrorBannerVisible = false }
                    )
                    // Clear of the titlebar, which the content sits under.
                    .padding(.top, 30)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: model.selectedFailure)

            // A column again, and a permanent one. It was an overlay only so it
            // could animate in without resizing the terminal — every frame of
            // that resize being an `ioctl(TIOCSWINSZ)` and a SIGWINCH. Nothing
            // animates now, so the terminal is laid out once, at its real width,
            // and the panel covers none of it.
            // No animation on this. Showing the column resizes the terminal,
            // and animating that resize is what made the old drawer judder: a
            // SIGWINCH per frame, the shell repainting through the whole slide.
            if model.isTaskPanelVisible {
                TaskPanelView(tasks: model.tasks)
            }
        }
        // Not a sheet. A sheet on macOS is modal and will not dismiss on a
        // click outside it, and picking a theme is a thing you do by trying
        // three and then getting on with your work.
        .overlay {
            if model.isThemePickerVisible {
                ZStack {
                    Color.black.opacity(0.42)
                        .ignoresSafeArea()
                        .contentShape(.rect)
                        .onTapGesture { model.isThemePickerVisible = false }
                    ThemePickerView(model: model) { model.isThemePickerVisible = false }
                }
                .environment(\.theme, model.themes.theme)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.isThemePickerVisible)
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        // Published once, here, so every view below reads the same theme.
        .environment(\.theme, model.themes.theme)
        .onAppear {
            model.start()
            model.applyThemeToSessions()
            Self.matchSystemAppearance(to: model.themes.theme)
        }
        .onChange(of: model.themes.selectedID) { _, _ in
            model.applyThemeToSessions()
            Self.matchSystemAppearance(to: model.themes.theme)
        }
        .sheet(isPresented: $model.isCommandPaletteVisible) {
            CommandPaletteView(model: model)
        }
        .sheet(item: $model.pendingPaste) { reading in
            PasteReviewView(
                reading: reading,
                paste: { model.confirmPendingPaste() },
                cancel: { model.pendingPaste = nil }
            )
            .environment(\.theme, model.themes.theme)
        }
        .sheet(isPresented: $model.isQuickActionsVisible) {
            QuickActionsView(model: model)
                .environment(\.theme, model.themes.theme)
        }
    }

    /// System controls draw themselves — the keep-awake switch, menus, the
    /// window's own furniture — and they take their cue from `NSAppearance`,
    /// not from us. Without this a light theme keeps a dark switch and dark
    /// scrollbars, which reads as a half-finished theme rather than a choice.
    private static func matchSystemAppearance(to theme: Theme) {
        NSApp.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    }
}
