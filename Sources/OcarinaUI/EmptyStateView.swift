import SwiftUI

/// Shown when every tab has been closed: the ocarina over Hyrule at dusk.
///
/// With no tabs there is no strip either, so this owns the whole window.
struct EmptyStateView: View {
    let onNewTab: () -> Void

    @State private var isBreathing = false
    @State private var isGlowing = false
    @State private var isCTAHovered = false

    // Dusk, from the last light at the horizon up into night.
    private static let skyHigh = Color(red: 0.08, green: 0.08, blue: 0.20)
    private static let skyMid = Color(red: 0.31, green: 0.16, blue: 0.30)
    private static let skyLow = Color(red: 0.72, green: 0.38, blue: 0.22)
    // The ocarina: blue ceramic, lit from above.
    private static let clayPale = Color(red: 0.66, green: 0.88, blue: 0.95)
    private static let clayBlue = Color(red: 0.25, green: 0.56, blue: 0.83)
    private static let clayDeep = Color(red: 0.09, green: 0.24, blue: 0.50)
    // Gold, for the wordmark and everything that has to be read.
    private static let goldPale = Color(red: 1.00, green: 0.93, blue: 0.74)
    private static let goldWarm = Color(red: 0.97, green: 0.72, blue: 0.33)
    private static let lampAmber = Color(red: 1.00, green: 0.80, blue: 0.42)
    private static let holeShadow = Color(red: 0.04, green: 0.11, blue: 0.27)
    private static let silhouette = Color(red: 0.07, green: 0.04, blue: 0.10)

    var body: some View {
        ZStack(alignment: .bottom) {
            sky
            NightSky()
            hyrule
            content
        }
        .clipped()
        .onAppear {
            // A held note, not a still image.
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) {
                isGlowing = true
            }
        }
    }

    // MARK: - Scene

    private var sky: some View {
        LinearGradient(
            colors: [Self.skyHigh, Self.skyMid, Self.skyLow],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var ocarina: some View {
        ZStack {
            GlyphArt(
                rows: HyruleArt.ocarina,
                size: 11,
                rowSpacing: -3.2,
                // The pale stop is pulled in tight, so the highlight reads as
                // glaze on one shoulder rather than washing out half the body.
                fill: LinearGradient(
                    stops: [
                        .init(color: Self.clayPale, location: 0),
                        .init(color: Self.clayBlue, location: 0.3),
                        .init(color: Self.clayDeep, location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            // Same grid, so the holes land exactly on the body.
            GlyphArt(
                rows: HyruleArt.ocarinaHoles,
                size: 11,
                rowSpacing: -3.2,
                fill: Self.holeShadow
            )
        }
        // Held, not floating level.
        .rotationEffect(.degrees(-11))
        // The halo is a background rather than a sibling, so it can overflow
        // without claiming layout space and shoving the wordmark down.
        .background {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Self.clayPale.opacity(0.22), Self.clayBlue.opacity(0.10), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: isGlowing ? 240 : 190
                    )
                )
                .frame(width: 560, height: 320)
        }
        .shadow(color: Self.clayPale.opacity(0.3), radius: isGlowing ? 18 : 10)
        // A held note, not a still image.
        .offset(y: isBreathing ? -7 : 0)
        .allowsHitTesting(false)
    }

    private var hyrule: some View {
        ZStack(alignment: .bottom) {
            // The art is a fixed width; this carries the ground to the edges.
            Rectangle()
                .fill(Self.silhouette)
                .frame(height: 26)

            ZStack {
                GlyphArt(
                    rows: HyruleArt.skyline,
                    size: 11,
                    rowSpacing: -3,
                    fill: Self.silhouette
                )
                // Same grid, so the lit windows land exactly in the castle.
                GlyphArt(
                    rows: HyruleArt.castleLights,
                    size: 11,
                    rowSpacing: -3,
                    fill: Self.lampAmber
                )
                .shadow(color: Self.lampAmber.opacity(0.9), radius: 7)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            ocarina

            Spacer(minLength: 24)

            GlyphArt(
                rows: HyruleArt.wordmark,
                size: 11,
                rowSpacing: -3,
                fill: LinearGradient(
                    colors: [Self.goldPale, Self.goldWarm],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .shadow(color: Self.goldWarm.opacity(0.35), radius: 12)

            Text("Song of a new terminal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Self.goldPale.opacity(0.6))
                .padding(.top, 12)

            callToAction
                .padding(.top, 26)

            hints
                .padding(.top, 18)
        }
        .padding(.bottom, 132)
    }

    private var callToAction: some View {
        Button(action: onNewTab) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                Text("New Terminal")
                    .font(.system(size: 17, weight: .semibold))
                Text("⌘T")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background {
                        RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.28))
                    }
            }
            .foregroundStyle(Color(red: 0.16, green: 0.09, blue: 0.05))
            .padding(.horizontal, 26)
            .padding(.vertical, 15)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [Self.goldPale, Self.goldWarm],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: Self.goldWarm.opacity(isCTAHovered ? 0.75 : 0.4),
                        radius: isCTAHovered ? 22 : 12,
                        y: 4
                    )
            }
            .scaleEffect(isCTAHovered ? 1.04 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                isCTAHovered = hovering
            }
        }
    }

    private var hints: some View {
        HStack(spacing: 18) {
            hint("⇧⌘P", "jump between terminals")
            hint("⌘W", "close a tab")
        }
    }

    private func hint(_ key: String, _ description: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.09))
                }
            Text(description)
                .font(.system(size: 11))
        }
        .foregroundStyle(Self.goldPale.opacity(0.45))
    }
}
