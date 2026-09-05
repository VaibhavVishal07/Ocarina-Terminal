import SwiftUI

/// The first stars, out before the dusk has finished going.
///
/// Positions come from a fixed seed so the sky is the same sky every launch —
/// a constellation that moved on each redraw would read as noise.
struct NightSky: View {
    private struct Star {
        let x: Double
        let y: Double
        let size: Double
        let brightness: Double
        let period: Double
        let delay: Double
    }

    @State private var isTwinkling = false

    private static let stars: [Star] = {
        var seed: UInt64 = 0x4F434152494E41 // "OCARINA"
        func next() -> Double {
            // xorshift64: small, deterministic, and good enough for stars.
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return Double(seed % 10_000) / 10_000
        }
        return (0..<44).map { _ in
            Star(
                x: next(),
                // Only the high sky is dark enough yet; the horizon still burns.
                y: next() * 0.5,
                size: 1 + next() * 1.8,
                brightness: 0.18 + next() * 0.45,
                period: 1.8 + next() * 3.4,
                delay: next() * 3
            )
        }
    }()

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, star in
                    Circle()
                        .fill(.white)
                        .frame(width: star.size, height: star.size)
                        .opacity(isTwinkling ? star.brightness * 0.35 : star.brightness)
                        .offset(x: star.x * geometry.size.width, y: star.y * geometry.size.height)
                        .animation(
                            .easeInOut(duration: star.period)
                                .repeatForever(autoreverses: true)
                                .delay(star.delay),
                            value: isTwinkling
                        )
                }
            }
        }
        .onAppear { isTwinkling = true }
        .allowsHitTesting(false)
    }
}
