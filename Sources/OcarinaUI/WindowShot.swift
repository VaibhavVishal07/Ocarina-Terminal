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
///     build/Kazoo.app/Contents/MacOS/Kazoo
///
/// `OCARINA_SHOT_RUN` opens a tab in the working directory and types the
/// command, so the picture has a real session in it rather than the landing
/// screen. The app quits once the file is written: it was started to be
/// photographed.
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

        DispatchQueue.main.asyncAfter(deadline: .now() + after) {
            write(to: path)
            NSApp.terminate(nil)
        }
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
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
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
