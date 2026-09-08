import SwiftUI

/// A faint geometric lattice drawn behind the app's panels.
///
/// The point is personality, not decoration you notice. At the opacities these
/// run at you should not be able to say what the pattern is without looking
/// for it — the panel just stops reading as a flat rectangle, and Sakura feels
/// unlike Matcha for a reason you cannot immediately name.
///
/// Geometry, and not the petals, leaves, notes and shields this used to draw.
/// A picture scattered behind a list is a picture: the eye finds a blossom,
/// resolves it, and has spent attention that belonged to the tab you were
/// reading. A lattice has nothing to resolve — it is regular, it has no
/// subject, and it reads as the surface the panel is made of rather than as
/// things lying on top of it. That is also why these are ruled rather than
/// jittered: the scatter existed to stop nine repeated blossoms looking like
/// wallpaper, and a grid of lines has no such problem.
///
/// Drawn, never shipped as artwork: a bitmap would need one set per theme at
/// three scales, and would be wrong the moment a colour changed. A path costs
/// nothing and takes the theme's own colour.
public struct Motif: Codable, Sendable, Equatable {
    public let shape: Shape
    /// How much of the panel it takes. Above about 0.07 it stops being texture
    /// and starts being wallpaper.
    public let opacity: Double
    /// The lattice's period in points — the distance from one mark to the next,
    /// or between one rule and the next.
    public let scale: Double
    public let color: ThemeColor

    /// Eighteen lattices, one per theme that has one.
    ///
    /// No two themes share one. The pattern is the only part of a theme you
    /// can still tell apart at a glance once the window is mostly terminal, so
    /// a repeat would cost the pair of themes the one thing separating them.
    public enum Shape: String, Codable, Sendable, CaseIterable {
        /// Ruled surfaces: the whole panel, in one direction or two.
        case grid        // blueprint — an engineering grid
        case scanlines   // matrix — a phosphor screen
        case brushed     // steel — rolled metal, the one uneven ruling
        case stripes     // superman — a single diagonal family
        case crosshatch  // matcha — two diagonal families

        /// Marks on a lattice: a small shape repeated on a regular pitch.
        case dots        // mono
        case rings       // lavender
        case crosses     // midnight
        case diamonds    // sakura
        case triangles   // ember
        case weave       // mocha — a basket weave of dashes
        case chevrons    // ocean
        case hexagons    // ocarina — a honeycomb
        case columns     // phosphor — an aperture grille, ruled the other way
        case squares     // big-blue — the character cell, drawn
        case waves       // shibuya — rain running down glass
        case ticks       // calibrated — a rule, with its marks
        case rules       // preprint — lines of text, seen from too far to read
    }
}

/// Rules a lattice across whatever it is put behind.
struct PatternView: View {
    let motif: Motif

    /// Hairline, everywhere. A pattern at these opacities is carried by where
    /// the lines fall and not by how heavy they are — much above this and the
    /// panel reads as ruled paper.
    static let hairline: CGFloat = 0.6

    var body: some View {
        Canvas { context, size in
            let step = max(2, motif.scale)
            let ink = motif.color.color.opacity(motif.opacity)

            // Brushed is the one pattern whose character is that its lines are
            // *not* even, so it needs a weight per line and draws itself.
            guard motif.shape != .brushed else {
                Self.brush(&context, size: size, step: step, motif: motif)
                return
            }

            let (stroked, filled) = Self.paths(for: motif.shape, size: size, step: step)
            if !stroked.isEmpty {
                context.stroke(stroked, with: .color(ink), lineWidth: Self.hairline)
            }
            if !filled.isEmpty {
                context.fill(filled, with: .color(ink))
            }
        }
        .allowsHitTesting(false)
        .drawingGroup()
    }

    /// The lattice, as one path to stroke and one to fill.
    ///
    /// Built whole and drawn in two calls rather than a call per mark: a panel
    /// this size holds a few hundred of them, and stroking each one separately
    /// also compounds the alpha wherever two marks touch — which is what turns
    /// a honeycomb's shared edges into a darker mesh than the cells it joins.
    static func paths(for shape: Motif.Shape, size: CGSize, step: Double) -> (Path, Path) {
        var stroked = Path()
        var filled = Path()
        let width = size.width, height = size.height

        /// The lattice points, one row at a time, running a cell past every
        /// edge so no mark is clipped into a different shape at the border.
        func cells(_ body: (CGPoint) -> Void) {
            var y = 0.0
            while y < height + step {
                var x = 0.0
                while x < width + step {
                    body(CGPoint(x: x, y: y))
                    x += step
                }
                y += step
            }
        }

        /// The same, when a mark has to know whether its cell is odd or even.
        func checkered(_ body: (CGPoint, Bool) -> Void) {
            var row = 0
            var y = 0.0
            while y < height + step {
                var column = 0
                var x = 0.0
                while x < width + step {
                    body(CGPoint(x: x, y: y), (row + column).isMultiple(of: 2))
                    column += 1
                    x += step
                }
                row += 1
                y += step
            }
        }

        func rule(from start: CGPoint, to end: CGPoint) {
            stroked.move(to: start)
            stroked.addLine(to: end)
        }

        switch shape {
        case .brushed:
            break  // Drawn by `brush`, which needs a weight per line.

        case .grid:
            var x = 0.0
            while x < width { rule(from: CGPoint(x: x, y: 0), to: CGPoint(x: x, y: height)); x += step }
            var y = 0.0
            while y < height { rule(from: CGPoint(x: 0, y: y), to: CGPoint(x: width, y: y)); y += step }

        case .scanlines:
            var y = 0.0
            while y < height { rule(from: CGPoint(x: 0, y: y), to: CGPoint(x: width, y: y)); y += step }

        case .stripes:
            // Started a panel's height off the left edge and run a panel's
            // height past the right, so the family covers the corners rather
            // than leaving two bare triangles.
            var x = -height
            while x < width {
                rule(from: CGPoint(x: x, y: 0), to: CGPoint(x: x + height, y: height))
                x += step
            }

        case .crosshatch:
            var x = -height
            while x < width {
                rule(from: CGPoint(x: x, y: 0), to: CGPoint(x: x + height, y: height))
                rule(from: CGPoint(x: x + height, y: 0), to: CGPoint(x: x, y: height))
                x += step
            }

        case .dots:
            let radius = max(0.5, step * 0.07)
            cells { point in
                filled.addEllipse(in: CGRect(
                    x: point.x - radius, y: point.y - radius,
                    width: radius * 2, height: radius * 2
                ))
            }

        case .rings:
            let radius = step * 0.26
            cells { point in
                stroked.addEllipse(in: CGRect(
                    x: point.x - radius, y: point.y - radius,
                    width: radius * 2, height: radius * 2
                ))
            }

        case .crosses:
            let arm = step * 0.15
            cells { point in
                rule(from: CGPoint(x: point.x - arm, y: point.y),
                     to: CGPoint(x: point.x + arm, y: point.y))
                rule(from: CGPoint(x: point.x, y: point.y - arm),
                     to: CGPoint(x: point.x, y: point.y + arm))
            }

        case .diamonds:
            let radius = step * 0.17
            cells { point in
                filled.move(to: CGPoint(x: point.x, y: point.y - radius))
                filled.addLine(to: CGPoint(x: point.x + radius, y: point.y))
                filled.addLine(to: CGPoint(x: point.x, y: point.y + radius))
                filled.addLine(to: CGPoint(x: point.x - radius, y: point.y))
                filled.closeSubpath()
            }

        case .triangles:
            // Every other one inverted, so the field reads as a tiling rather
            // than as a page of arrowheads all pointing the same way.
            let radius = step * 0.19
            checkered { point, up in
                let sign: Double = up ? -1 : 1
                filled.move(to: CGPoint(x: point.x, y: point.y + radius * sign))
                filled.addLine(to: CGPoint(x: point.x + radius * 0.92, y: point.y - radius * sign))
                filled.addLine(to: CGPoint(x: point.x - radius * 0.92, y: point.y - radius * sign))
                filled.closeSubpath()
            }

        case .weave:
            // One dash lying across, the next standing up, checkered — which
            // is a basket weave with the over-and-under left out, and at this
            // opacity the over-and-under was never going to be visible.
            let arm = step * 0.28
            checkered { point, across in
                if across {
                    rule(from: CGPoint(x: point.x - arm, y: point.y),
                         to: CGPoint(x: point.x + arm, y: point.y))
                } else {
                    rule(from: CGPoint(x: point.x, y: point.y - arm),
                         to: CGPoint(x: point.x, y: point.y + arm))
                }
            }

        case .chevrons:
            // Rows of shallow Vs, every other row half a step along, so the
            // column of points does not line up into a vertical rule.
            let rise = step * 0.26
            var row = 0
            var y = 0.0
            while y < height + step {
                var x = -step + (row.isMultiple(of: 2) ? 0 : step / 2)
                while x < width + step {
                    stroked.move(to: CGPoint(x: x, y: y))
                    stroked.addLine(to: CGPoint(x: x + step / 2, y: y + rise))
                    stroked.addLine(to: CGPoint(x: x + step, y: y))
                    x += step
                }
                row += 1
                y += step
            }

        case .columns:
            // Scanlines' opposite number. A shadow-mask tube is ruled across;
            // an aperture grille is ruled down, and the two themes that wear a
            // phosphor should not be wearing the same one.
            var x = 0.0
            while x < width { rule(from: CGPoint(x: x, y: 0), to: CGPoint(x: x, y: height)); x += step }

        case .squares:
            // The character cell itself, which is the only lattice a text-mode
            // screen ever really had. Outlined rather than filled: filled at
            // this pitch is a grid of blocks, and a grid of blocks is a wall.
            let inset = step * 0.22
            cells { point in
                stroked.addRect(CGRect(
                    x: point.x - inset, y: point.y - inset,
                    width: inset * 2, height: inset * 2
                ))
            }

        case .waves:
            // Rows of shallow curves, each row offset half a step, so the
            // crests never stack into a vertical rule. Chevrons with the
            // corner taken off — which is the difference between a folded
            // thing and a running one.
            let rise = step * 0.22
            var waveRow = 0
            var waveY = 0.0
            while waveY < height + step {
                var x = -step + (waveRow.isMultiple(of: 2) ? 0 : step / 2)
                stroked.move(to: CGPoint(x: x, y: waveY))
                while x < width + step {
                    stroked.addQuadCurve(
                        to: CGPoint(x: x + step / 2, y: waveY),
                        control: CGPoint(x: x + step / 4, y: waveY + rise)
                    )
                    stroked.addQuadCurve(
                        to: CGPoint(x: x + step, y: waveY),
                        control: CGPoint(x: x + step * 0.75, y: waveY - rise)
                    )
                    x += step
                }
                waveRow += 1
                waveY += step
            }

        case .ticks:
            // A ruler's face: a long mark every fifth cell and a short one
            // between, which is the only pattern here that is a measurement
            // rather than a decoration.
            var tickColumn = 0
            var x = 0.0
            while x < width + step {
                let long = tickColumn.isMultiple(of: 5)
                let arm = step * (long ? 0.42 : 0.2)
                var y = 0.0
                while y < height + step {
                    rule(from: CGPoint(x: x, y: y - arm), to: CGPoint(x: x, y: y + arm))
                    y += step
                }
                tickColumn += 1
                x += step
            }

        case .rules:
            // Lines of set text at the size where the words have gone and only
            // the measure is left. Every fourth line is short, because that is
            // where a paragraph ended.
            var ruleRow = 0
            var y = 0.0
            while y < height + step {
                let short = (ruleRow % 4) == 3
                let end = short ? width * 0.58 : width
                rule(from: CGPoint(x: 0, y: y), to: CGPoint(x: end, y: y))
                ruleRow += 1
                y += step
            }

        case .hexagons:
            // Pointy-top cells: a cell is `radius * sqrt(3)` across and two
            // radii tall, rows sit one and a half radii apart, and every other
            // row is offset by half a cell. Shared edges are drawn twice and
            // stroked once — see the note on this function.
            let radius = step * 0.5
            let cellWidth = radius * sqrt(3.0)
            var row = 0
            var y = 0.0
            while y < height + radius * 2 {
                var x = -cellWidth + (row.isMultiple(of: 2) ? 0 : cellWidth / 2)
                while x < width + cellWidth {
                    stroked.addPath(hexagon(at: CGPoint(x: x, y: y), radius: radius))
                    x += cellWidth
                }
                row += 1
                y += radius * 1.5
            }
        }

        return (stroked, filled)
    }

    /// One pointy-top hexagon, closed.
    static func hexagon(at centre: CGPoint, radius: Double) -> Path {
        var path = Path()
        for corner in 0..<6 {
            let angle = (Double(corner) * 60 - 90) * .pi / 180
            let point = CGPoint(
                x: centre.x + cos(angle) * radius,
                y: centre.y + sin(angle) * radius
            )
            if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// Rolled metal: horizontal grain, unevenly spaced and unevenly weighted.
    ///
    /// The one lattice that is not regular, because an even one is a printed
    /// rule and this has to read as a material. Seeded rather than random, so
    /// the grain is identical on every redraw — a surface that reshuffles when
    /// the window resizes is a distraction rather than a texture.
    static func brush(_ context: inout GraphicsContext, size: CGSize, step: Double, motif: Motif) {
        var random = Seeded(seed: 0x5CA1E)
        var y = 0.0
        while y < size.height {
            let weight = 0.35 + random.next() * 0.65
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(
                line,
                with: .color(motif.color.color.opacity(motif.opacity * weight)),
                lineWidth: hairline
            )
            y += step * (0.6 + random.next() * 0.9)
        }
    }
}

/// A small deterministic generator, so a pattern is the same every draw.
private struct Seeded {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493 }

    /// The next value in 0..<1.
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}
