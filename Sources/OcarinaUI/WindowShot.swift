import AppKit
import Foundation

/// Lets the app take a picture of its own window.
///
/// Not a feature — a way to see the real thing. `screencapture` and everything
/// else that reads the display needs Screen Recording, granted to whichever
/// bundle the calling process is attributed to, and a shell running inside
/// another app does not have it. Nothing here reads the display: the window
/// draws itself into a bitmap, which is a thing any app may do about its own
/// windows.
///
/// It does nothing at all unless `OCARINA_SHOT` names a file, so it costs a
/// normal launch one dictionary lookup.
///
///     OCARINA_SHOT=/tmp/shot.png \
///     OCARINA_SHOT_RUN='claude' \
///     OCARINA_SHOT_AFTER=8 \
///     OCARINA_SHOT_STATE=themes \
///     build/Kazoo.app/Contents/MacOS/Kazoo
///
/// `OCARINA_SHOT_RUN` opens a tab in the working directory and types the
/// command, so the picture has a real session in it rather than the landing
/// screen. The app quits once the file is written: it was started to be
/// photographed.
///
/// `OCARINA_SHOT_STATE` opens one of the surfaces that a launch cannot reach
/// on its own, a beat before the shutter:
///
/// | Value | What it opens |
/// |---|---|
/// | `themes` | the theme picker |
/// | `skills` | the skills shelf |
/// | `quick` | the quick actions drawer |
/// | `empty` | closes every tab, leaving the landing board |
///
/// The first two draw inside the window, so the window's own bitmap holds
/// them. The drawer is a sheet, which macOS gives its own window, and `write`
/// photographs that instead when one is attached.
@MainActor
public enum WindowShot {

    public static func arm(_ model: OcarinaModel) {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["OCARINA_SHOT"] else { return }
        let after = Double(environment["OCARINA_SHOT_AFTER"] ?? "") ?? 6

        if let command = environment["OCARINA_SHOT_RUN"], !command.isEmpty {
            let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            model.newTab(workingDirectory: directory)
            // A beat for the shell to reach its first prompt. Typing into a zsh
            // that has not drawn one yet loses the line.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                model.selectedSession?.send(text: command + "\n")
            }
        }

        let state = environment["OCARINA_SHOT_STATE"] ?? ""

        DispatchQueue.main.asyncAfter(deadline: .now() + after) {
            open(state, on: model)
            // A beat for the surface to land. A sheet animates in, and a
            // bitmap taken on the same tick catches it half way up the screen.
            let settle = state.isEmpty ? 0.0 : 0.55
            DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
                write(to: path)
                // The drawer is a sheet, and a sheet holds the app open through
                // `terminate` — it asks the window whether it may close and the
                // window is busy being modal. Put it away first, and keep a
                // hard exit behind that, because the shot is already on disk
                // and a photographer that will not leave is worse than an
                // abrupt one.
                close(state, on: model)
                NSApp.terminate(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exit(0) }
            }
        }
    }

    /// Opens the surface `OCARINA_SHOT_STATE` names.
    ///
    /// Setting the model's own flags rather than sending keystrokes: a
    /// shortcut has to go through the responder chain and the menu, and this
    /// runs before anybody has clicked into the window.
    private static func open(_ state: String, on model: OcarinaModel) {
        switch state {
        case "themes": model.isThemePickerVisible = true
        case "skills": model.isSkillsVisible = true
        case "quick":  model.isQuickActionsVisible = true
        case "empty":
            // The landing board is what the window draws with nothing open, so
            // the way to photograph it is to close what the launch opened.
            for tab in model.tabs { model.closeTab(tab.id) }
        default: break
        }
    }

    /// Puts back whatever `open` raised, so nothing is left holding the app.
    private static func close(_ state: String, on model: OcarinaModel) {
        model.isThemePickerVisible = false
        model.isSkillsVisible = false
        model.isQuickActionsVisible = false
    }

    /// Draws the window's content view into a PNG.
    ///
    /// On the window's own background first. `NSVisualEffectView` is the one
    /// thing in this hierarchy that cannot draw itself into a bitmap — the blur
    /// is composited by the window server, from the desktop behind the window,
    /// which is exactly the thing a self-portrait has no access to. Left alone
    /// it comes out transparent and every panel floats on nothing, so the
    /// theme's ground is painted underneath, which is what the glass is
    /// standing in for anyway.
    public static func write(to path: String) {
        // The sheet first when there is one. A quick actions drawer is its own
        // window as far as AppKit is concerned, so the main window's bitmap
        // comes back with the drawer missing and the window dimmed behind it.
        let main = NSApp.windows.first(where: { $0.isVisible && $0.attachedSheet == nil && !$0.isSheet })
        guard let window = NSApp.windows.first(where: { $0.isSheet && $0.isVisible })
                        ?? main
                        ?? NSApp.windows.first(where: { $0.isVisible }),
              let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)

        let size = view.bounds.size
        let image = NSImage(size: size)
        image.lockFocus()
        (window.backgroundColor ?? .black).setFill()
        NSRect(origin: .zero, size: size).fill()
        rep.draw(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()

        guard let data = image.tiffRepresentation,
              let flattened = NSBitmapImageRep(data: data),
              let png = flattened.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
