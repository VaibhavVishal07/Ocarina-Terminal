import AppKit

/// The app's mark, from the dot-matrix icon pack.
///
/// Two sizes are carried rather than one: the dock wants a large image, and a
/// 16pt tab icon scaled down from 512px is both wasteful and softer than the
/// 64px export, which was drawn for that size.
public enum OcarinaIcon {
    /// For `NSApplication.applicationIconImage`.
    public static let app: NSImage? = load("AppIcon").map(dockIcon)

    /// The tile alone, for anything drawing the mark *inside* the app.
    ///
    /// Not `app`: that one is padded onto a transparent canvas at the ~80% the
    /// dock grid expects, so drawn at 26pt in a row it arrives as a 21pt tile
    /// floating in space. This is the tile itself, and the caller rounds it to
    /// whatever corner its context wants.
    public static let tile: NSImage? = load("AppIcon").map(trimmedToContent)

    /// The dock wants art on a transparent canvas. The export is a black plate
    /// with the tile inside it, which macOS draws verbatim — so the icon reads
    /// as a small tile sitting in a dark square rather than as the icon.
    ///
    /// The tile is cut out, its corners clipped to transparency, and it is laid
    /// on a clear canvas at the ~80% the macOS icon grid expects.
    static func dockIcon(from image: NSImage) -> NSImage {
        let tile = trimmedToContent(image)
        let side = max(tile.size.width, tile.size.height)
        guard side > 0 else { return image }

        let canvas = (side / 0.80).rounded()
        let result = NSImage(size: NSSize(width: canvas, height: canvas))
        result.lockFocus()
        let inset = ((canvas - side) / 2).rounded()
        let box = NSRect(x: inset, y: inset, width: side, height: side)
        let rounded = NSBezierPath(roundedRect: box,
                                   xRadius: side * 0.225,
                                   yRadius: side * 0.225)
        rounded.addClip()
        tile.draw(in: box)
        result.unlockFocus()
        return result
    }

    /// Crops away the flat backdrop, leaving the drawn tile.
    static func trimmedToContent(_ image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let source = rep.cgImage else { return image }

        var minX = rep.pixelsWide, maxX = -1, minY = rep.pixelsHigh, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let colour = rep.colorAt(x: x, y: y),
                      colour.alphaComponent > 0.15,
                      colour.brightnessComponent > 0.10 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX > minX, maxY > minY else { return image }

        let box = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cropped = source.cropping(to: box) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: box.width, height: box.height))
    }

    private static func load(_ name: String) -> NSImage? {
        guard let url = PackagedResources.bundle.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
