import SwiftUI

/// A faint motif drawn behind the app's panels.
///
/// The point is personality, not decoration you notice. At the opacities these
/// run at you should not be able to say what the shape is without looking for
/// it — the panel just stops reading as a flat rectangle, and Sakura feels
/// unlike Matcha for a reason you cannot immediately name.
///
/// Drawn, never shipped as artwork: a bitmap would need six sets at three
/// scales, and would be wrong the moment a theme changed colour. A path costs
/// nothing and takes the theme's own colour.
public struct Motif: Codable, Sendable, Equatable {
    public let shape: Shape
    /// How much of the panel it takes. Above about 0.07 it stops being texture
    /// and starts being wallpaper.
    public let opacity: Double
    /// The motif's size in points.
    public let scale: Double
    public let color: ThemeColor

    public enum Shape: String, Codable, Sendable {
        // Scattered motifs.
        case petals     // sakura — a five-petalled cherry blossom
        case leaves     // matcha
        case notes      // ocarina — it is an instrument
        case sprigs     // lavender
        case dots       // mono
        case embers     // ember
        case waves      // ocean
        case rain       // matrix — falling glyph trails
        case crest      // superman — a shield

        // Surface textures. These cover the panel rather than sitting on it,
        // so a theme can read as a material instead of a pattern.
        case brushed    // fine horizontal grain: rolled metal
        case grid       // a faint engineering grid

        /// Whether the shape is a texture drawn across the whole surface.
        var isTexture: Bool { self == .brushed || self == .grid }
    }
}

/// Scatters a motif across whatever it is put behind.
///
/// Placement is a jittered grid rather than true randomness: an even scatter
/// leaves visible clumps and bald patches, and a strict grid reads as a
/// pattern swatch. The jitter is seeded, so the layout is identical on every
/// redraw — a motif that reshuffles when the window resizes is a distraction
/// rather than a texture.
struct PatternView: View {
    let motif: Motif

    /// Distance between grid cells, in multiples of the motif's own size.
    private static let spacing: Double = 3.4

    var body: some View {
        Group {
            if motif.shape.isTexture { texture } else { scatter }
        }
        .allowsHitTesting(false)
        .drawingGroup()
    }

    /// Lines rather than objects — the difference between a surface with a
    /// grain and a surface with things on it.
    private var texture: some View {
        Canvas { context, size in
            let gap = max(2, motif.scale)
            var random = Seeded(seed: 0x5CA1E)

            var y = 0.0
            while y < size.height {
                // Uneven weight down the panel, or it reads as a printed rule
                // rather than a material.
                let weight = 0.35 + random.next() * 0.65
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    line,
                    with: .color(motif.color.color.opacity(motif.opacity * weight)),
                    lineWidth: 0.6
                )
                y += gap * (0.6 + random.next() * 0.9)
            }

            guard motif.shape == .grid else { return }
            var x = 0.0
            while x < size.width {
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    line,
                    with: .color(motif.color.color.opacity(motif.opacity * 0.5)),
                    lineWidth: 0.6
                )
                x += gap * 1.6
            }
        }
    }

    private var scatter: some View {
        Canvas { context, size in
            let step = motif.scale * Self.spacing
            guard step > 1 else { return }

            let columns = Int(size.width / step) + 2
            let rows = Int(size.height / step) + 2
            var random = Seeded(seed: 0x0CA21A)

            for row in 0..<rows {
                for column in 0..<columns {
                    let jitterX = (random.next() - 0.5) * step * 0.7
                    let jitterY = (random.next() - 0.5) * step * 0.7
                    let angle = random.next() * 2 * .pi
                    // Some motifs sit further back than others, which is what
                    // stops a scatter looking stamped.
                    let fade = 0.45 + random.next() * 0.55

                    let centre = CGPoint(
                        x: Double(column) * step + jitterX,
                        y: Double(row) * step + jitterY
                    )
                    guard centre.x > -step, centre.x < size.width + step,
                          centre.y > -step, centre.y < size.height + step
                    else { continue }

                    var transform = CGAffineTransform(translationX: centre.x, y: centre.y)
                    transform = transform.rotated(by: angle)
                    transform = transform.scaledBy(x: motif.scale, y: motif.scale)

                    let path = Self.path(for: motif.shape).applying(transform)
                    context.fill(
                        Path(path.cgPath),
                        with: .color(motif.color.color.opacity(motif.opacity * fade))
                    )
                }
            }
        }
    }

    /// Each motif drawn in a unit box centred on the origin, so the transform
    /// above is the only place size and rotation are decided.
    static func path(for shape: Motif.Shape) -> Path {
        var path = Path()
        switch shape {
        case .petals:
            // A cherry blossom, drawn properly.
            //
            // Two earlier attempts were circles: five blobs around a gap (a paw
            // print) and then five overlapping discs (a flower-ish blob). What
            // makes a sakura petal recognisable is not the arrangement, it is
            // the petal — narrow where it joins the centre, widest two-thirds
            // out, and notched at the tip. Five of those and a stamen cluster
            // read as the real thing even at eight points across.
            for index in 0..<5 {
                let rotation = Double(index) / 5 * 2 * .pi
                path.addPath(Self.petal, transform: CGAffineTransform(rotationAngle: rotation))
            }
            path.addEllipse(in: CGRect(x: -0.075, y: -0.075, width: 0.15, height: 0.15))
            // Stamens: five short marks between the petals.
            for index in 0..<5 {
                let angle = (Double(index) + 0.5) / 5 * 2 * .pi
                let tip = CGPoint(x: cos(angle) * 0.20, y: sin(angle) * 0.20)
                path.addEllipse(in: CGRect(
                    x: tip.x - 0.035, y: tip.y - 0.035, width: 0.07, height: 0.07
                ))
            }

        case .rain:
            // A glyph trail: a bright head with a fading tail above it.
            path.addRect(CGRect(x: -0.045, y: 0.10, width: 0.09, height: 0.22))
            path.addRect(CGRect(x: -0.035, y: -0.16, width: 0.07, height: 0.20))
            path.addRect(CGRect(x: -0.025, y: -0.40, width: 0.05, height: 0.16))

        case .crest:
            // A shield: shoulders squared, sides tapering to a point.
            path.move(to: CGPoint(x: -0.34, y: -0.36))
            path.addLine(to: CGPoint(x: 0.34, y: -0.36))
            path.addQuadCurve(to: CGPoint(x: 0, y: 0.44), control: CGPoint(x: 0.30, y: 0.14))
            path.addQuadCurve(to: CGPoint(x: -0.34, y: -0.36), control: CGPoint(x: -0.30, y: 0.14))

        case .brushed, .grid:
            // Drawn by `texture`, not scattered. An empty path here would be a
            // silent no-op, so give it the dot the tests can measure.
            path.addEllipse(in: CGRect(x: -0.12, y: -0.12, width: 0.24, height: 0.24))

        case .leaves:
            // Two arcs meeting at the tips — the simplest thing that is a leaf
            // and not an eye.
            path.move(to: CGPoint(x: -0.45, y: 0))
            path.addQuadCurve(to: CGPoint(x: 0.45, y: 0), control: CGPoint(x: 0, y: -0.42))
            path.addQuadCurve(to: CGPoint(x: -0.45, y: 0), control: CGPoint(x: 0, y: 0.42))

        case .notes:
            path.addEllipse(in: CGRect(x: -0.34, y: 0.06, width: 0.42, height: 0.30))
            path.addRect(CGRect(x: 0.02, y: -0.44, width: 0.07, height: 0.56))
            path.addQuadCurve(to: CGPoint(x: 0.09, y: -0.44), control: CGPoint(x: 0.34, y: -0.30))

        case .sprigs:
            // A stem with buds up it.
            path.addRect(CGRect(x: -0.02, y: -0.42, width: 0.04, height: 0.84))
            for index in 0..<4 {
                let y = -0.34 + Double(index) * 0.22
                let side: Double = index.isMultiple(of: 2) ? 1 : -1
                path.addEllipse(in: CGRect(x: side * 0.06, y: y, width: 0.17, height: 0.11))
            }

        case .dots:
            path.addEllipse(in: CGRect(x: -0.16, y: -0.16, width: 0.32, height: 0.32))

        case .embers:
            // A rising spark: teardrop, point up.
            path.move(to: CGPoint(x: 0, y: -0.45))
            path.addQuadCurve(to: CGPoint(x: 0.22, y: 0.28), control: CGPoint(x: 0.26, y: -0.10))
            path.addQuadCurve(to: CGPoint(x: -0.22, y: 0.28), control: CGPoint(x: 0, y: 0.50))
            path.addQuadCurve(to: CGPoint(x: 0, y: -0.45), control: CGPoint(x: -0.26, y: -0.10))

        case .waves:
            // A crest, thickened so it fills rather than needing a stroke.
            path.move(to: CGPoint(x: -0.50, y: 0.06))
            path.addCurve(
                to: CGPoint(x: 0.50, y: 0.06),
                control1: CGPoint(x: -0.18, y: -0.30),
                control2: CGPoint(x: 0.18, y: 0.34)
            )
            path.addCurve(
                to: CGPoint(x: -0.50, y: 0.06),
                control1: CGPoint(x: 0.18, y: 0.20),
                control2: CGPoint(x: -0.18, y: -0.16)
            )
        }
        return path
    }
}

extension PatternView {
    /// One petal, pointing up from the origin: narrow at the base, widest
    /// two-thirds out, notched at the tip.
    static let petal: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -0.06))
        path.addCurve(
            to: CGPoint(x: 0.10, y: -0.44),
            control1: CGPoint(x: 0.13, y: -0.14),
            control2: CGPoint(x: 0.19, y: -0.34)
        )
        // The notch.
        path.addQuadCurve(to: CGPoint(x: 0, y: -0.38), control: CGPoint(x: 0.05, y: -0.40))
        path.addQuadCurve(to: CGPoint(x: -0.10, y: -0.44), control: CGPoint(x: -0.05, y: -0.40))
        path.addCurve(
            to: CGPoint(x: 0, y: -0.06),
            control1: CGPoint(x: -0.19, y: -0.34),
            control2: CGPoint(x: -0.13, y: -0.14)
        )
        return path
    }()
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
