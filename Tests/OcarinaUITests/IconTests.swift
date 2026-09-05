import AppKit
import Testing
@testable import OcarinaUI

@Suite("Icons")
@MainActor
struct IconTests {

    @Test("The app icon is bundled and loads")
    func appIconLoads() throws {
        let icon = try #require(OcarinaIcon.app, "AppIcon.png is not in the resource bundle")
        #expect(icon.size.width > 0)
        #expect(icon.size.width == icon.size.height, "the dock wants a square")
    }

    /// The invariant the 424px regression broke: preparing an icon adds margin
    /// around the art, it never eats into it.
    @Test("Preparing a dock icon adds margin rather than trimming art away")
    func dockIconAddsMargin() {
        let source = NSImage(size: NSSize(width: 200, height: 200))
        source.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 20, y: 20, width: 160, height: 160)).fill()
        source.unlockFocus()

        let art = OcarinaIcon.trimmedToContent(source)
        let dock = OcarinaIcon.dockIcon(from: source)

        #expect(dock.size.width > art.size.width)
        #expect(dock.size.width == dock.size.height)
    }

}

extension IconTests {

    /// The pack's export is a black plate; an icon that keeps it reads as a
    /// small tile inside a dark square in the dock.
    @Test("The dock icon has no plate behind it")
    func dockIconIsTransparentBehindTheTile() throws {
        let icon = try #require(OcarinaIcon.app)
        let data = try #require(icon.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: data))

        // A corner of the canvas, well outside the rounded tile.
        let corner = try #require(rep.colorAt(x: 2, y: 2))
        #expect(corner.alphaComponent < 0.05, "the canvas corner is not transparent")

        // The middle still carries the mark.
        let middle = try #require(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2))
        #expect(middle.alphaComponent > 0.5)
    }
}
