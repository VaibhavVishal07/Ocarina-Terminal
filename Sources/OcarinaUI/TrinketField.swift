import SwiftUI

/// Draws a theme's trinket across the landing screen.
///
/// One `Canvas` under a `TimelineView`, not a view per particle. Twenty-two
/// SwiftUI views each with their own animation is twenty-two things for the
/// layout system to think about sixty times a second; a canvas is one, and the
/// particles are paths in it.
///
/// Nothing here is stored. Every particle's position is a function of the clock
/// and its own index, so there is no simulation to keep running, nothing to
/// reset when the view comes back, and no drift between one appearance and the
/// next. It also means the field is honest about being decoration: it cannot
/// accumulate state, so it cannot go wrong in a way that outlives the screen.
struct TrinketField: View {
    let trinket: Trinket
    let colour: Color
    /// When the flurry ends. The Easter egg: press the wordmark and everything
    /// on screen quickens and brightens for a moment, then settles back.
    let flurryUntil: Date?

    /// Long enough to be a moment and not an event.
    static let flurry: TimeInterval = 2.6

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date
                let clock = now.timeIntervalSinceReferenceDate
                // 0 at the peak of a flurry, 1 once it has worn off. Squared,
                // so it comes on hard and lets go gently.
                let surge = surge(at: now)

                for index in 0..<trinket.count {
                    draw(index, in: &context, size: size, clock: clock, surge: surge)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func surge(at now: Date) -> Double {
        guard let flurryUntil else { return 0 }
        let left = flurryUntil.timeIntervalSince(now)
        guard left > 0 else { return 0 }
        let fraction = min(1, left / Self.flurry)
        return fraction * fraction
    }

    private func draw(
        _ index: Int,
        in context: inout GraphicsContext,
        size: CGSize,
        clock: Double,
        surge: Double
    ) {
        let phase = random(index, 1)
        let across = random(index, 2)
        let scale = 0.7 + random(index, 3) * 0.6
        let spin = random(index, 4) * 2 * .pi

        // A flurry runs everything faster and further, and the sizes hold —
        // more of the same thing, harder, rather than a different effect.
        let speed = 1 + surge * 1.9
        let length = trinket.size * scale
        let alpha = trinket.strength * (0.55 + random(index, 5) * 0.45) * (1 + surge * 1.4)

        var point: CGPoint
        var fade = 1.0

        switch trinket.motion {
        case .falling, .streaking:
            let travel = (clock / trinket.crossing * speed + phase).truncatingRemainder(dividingBy: 1)
            point = CGPoint(
                x: across * size.width
                    + sin(travel * 2 * .pi + spin) * trinket.sway,
                // Started and finished off the edges, so nothing appears or
                // vanishes anywhere you can see it happen.
                y: -length + travel * (size.height + length * 2)
            )
        case .rising:
            let travel = (clock / trinket.crossing * speed + phase).truncatingRemainder(dividingBy: 1)
            point = CGPoint(
                x: across * size.width + sin(travel * 3 * .pi + spin) * trinket.sway,
                y: size.height + length - travel * (size.height + length * 2)
            )
            // An ember goes out on the way up rather than reaching the top and
            // being switched off there.
            fade = 1 - travel * travel
        case .still:
            point = CGPoint(x: across * size.width, y: random(index, 6) * size.height)
            // Each on its own clock, or twenty-two of them blink together and
            // the screen reads as flickering rather than as twinkling.
            let rate = 0.35 + random(index, 7) * 0.5
            fade = (sin(clock * rate * speed + spin) + 1) / 2
            fade = 0.25 + fade * 0.75
        }

        var shape = context
        shape.translateBy(x: point.x, y: point.y)
        // Still things do not turn, and a rain streak that turns is not rain.
        if trinket.motion == .falling, trinket != .rain {
            shape.rotate(by: .radians(spin + clock * 0.35 * speed))
        }
        shape.opacity = min(1, alpha * fade)
        shape.fill(trinket.path(size: length), with: .color(colour))
    }

    /// A deterministic value in 0..<1 for a particle and a purpose.
    ///
    /// Deterministic because the canvas redraws for reasons that have nothing
    /// to do with the trinket — a window resize, a theme change — and a field
    /// that reseeded on each of those would visibly jump.
    private func random(_ index: Int, _ salt: Int) -> Double {
        var value = UInt64(bitPattern: Int64(index &* 73_856_093 ^ salt &* 19_349_663))
        value = value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        value ^= value >> 33
        value = value &* 0xFF51_AFD7_ED55_8CCD
        value ^= value >> 33
        return Double(value & 0xFF_FFFF) / Double(0xFF_FFFF)
    }
}
