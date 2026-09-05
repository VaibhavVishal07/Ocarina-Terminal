import AppKit
import Testing
@testable import OcarinaUI

@Suite("Icons")
@MainActor
struct IconTests {

    @Test("The app icon is bundled and loads")
    func appIconLoads() throws {
        let icon = try #require(OcarinaIcon.app, "AppIcon-512.png is not in the resource bundle")
        #expect(icon.size.width >= 512)
        #expect(icon.size.height >= 512)
    }

    @Test("The tab mark is bundled and loads")
    func markLoads() throws {
        let mark = try #require(OcarinaIcon.mark, "AppIcon-64.png is not in the resource bundle")
        #expect(mark.size.width > 0)
        #expect(mark.isValid)
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
