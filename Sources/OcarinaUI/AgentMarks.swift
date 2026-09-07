import SwiftUI

/// Which mark a tool wears on the landing screen.
///
/// Drawn here as geometry rather than shipped as image files. Three reasons,
/// in order: a bundled logo is somebody else's trademark travelling inside this
/// app; a PNG cannot take the theme's colour, and every other lit thing on this
/// screen does; and a shape drawn at the size it is displayed stays sharp on a
/// display this app has not met yet.
///
/// They are recognisable rather than exact — a burst, a spark, a hexagon — and
/// the word underneath is what actually names the tool.
public enum AgentMark: Sendable, Hashable {
    /// Anthropic's radiating burst.
    case burst
    /// The four-pointed spark Google's assistant tools wear.
    case spark
    /// OpenAI's hexagon.
    case hexagon
    /// Everything not on the shelf.
    case plus
}

extension AgentMark {
    /// The mark, filled, sized to whatever box it is given.
    ///
    /// Filled here rather than handed back as a `Shape` for the caller to fill:
    /// each case is a different concrete type, so a switch that returned them
    /// bare would have to be erased anyway, and every one of these is painted
    /// the same way.
    @ViewBuilder
    func filled(with colour: Color) -> some View {
        switch self {
        case .burst: BurstShape().fill(colour)
        case .spark: SparkShape().fill(colour)
        case .hexagon: HexagonShape().fill(colour)
        case .plus: PlusShape().fill(colour)
        }
    }
}

/// Tapered blades around a common centre.
struct BurstShape: Shape {
    var blades = 12
    /// Where a blade starts, as a fraction of the radius. Without a hole the
    /// twelve of them meet in a solid disc and the mark reads as a dot.
    var hole: CGFloat = 0.16

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for blade in 0..<blades {
            let angle = Double(blade) / Double(blades) * 2 * .pi
            path.move(to: CGPoint(
                x: centre.x + cos(angle) * radius * hole,
                y: centre.y + sin(angle) * radius * hole
            ))
            path.addLine(to: CGPoint(
                x: centre.x + cos(angle) * radius,
                y: centre.y + sin(angle) * radius
            ))
        }
        // Stroked into a fillable path so the caller fills it like any other
        // shape, rather than having to know this one is made of lines.
        return path.strokedPath(StrokeStyle(lineWidth: radius * 0.17, lineCap: .round))
    }
}

/// A four-pointed star with its sides pulled in towards the centre.
struct SparkShape: Shape {
    /// How far the curve between two points comes in. At 0.5 it is a diamond;
    /// low is what makes the points read as a spark rather than a rhombus.
    var waist: CGFloat = 0.26

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let pull = radius * waist
        var path = Path()
        path.move(to: CGPoint(x: centre.x, y: centre.y - radius))
        path.addQuadCurve(
            to: CGPoint(x: centre.x + radius, y: centre.y),
            control: CGPoint(x: centre.x + pull, y: centre.y - pull)
        )
        path.addQuadCurve(
            to: CGPoint(x: centre.x, y: centre.y + radius),
            control: CGPoint(x: centre.x + pull, y: centre.y + pull)
        )
        path.addQuadCurve(
            to: CGPoint(x: centre.x - radius, y: centre.y),
            control: CGPoint(x: centre.x - pull, y: centre.y + pull)
        )
        path.addQuadCurve(
            to: CGPoint(x: centre.x, y: centre.y - radius),
            control: CGPoint(x: centre.x - pull, y: centre.y - pull)
        )
        path.closeSubpath()
        return path
    }
}

/// A hexagonal ring, flat sides left and right, point up.
struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for corner in 0..<6 {
            let angle = Double(corner) / 6 * 2 * .pi - .pi / 2
            let point = CGPoint(
                x: centre.x + cos(angle) * radius,
                y: centre.y + sin(angle) * radius
            )
            if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path.strokedPath(StrokeStyle(lineWidth: radius * 0.18, lineJoin: .round))
    }
}

/// The one mark that is not a logo: what you press for everything else.
struct PlusShape: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let arm = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: CGPoint(x: centre.x - arm, y: centre.y))
        path.addLine(to: CGPoint(x: centre.x + arm, y: centre.y))
        path.move(to: CGPoint(x: centre.x, y: centre.y - arm))
        path.addLine(to: CGPoint(x: centre.x, y: centre.y + arm))
        return path.strokedPath(StrokeStyle(lineWidth: arm * 0.2, lineCap: .round))
    }
}
