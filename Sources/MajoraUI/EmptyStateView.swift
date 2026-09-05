import SwiftUI

/// Shown when every tab has been closed: a night over Termina.
///
/// With no tabs there is no strip either, so this owns the whole window.
struct EmptyStateView: View {
    let onNewTab: () -> Void

    @State private var isDescending = false
    @State private var isGlowing = false
    @State private var isCTAHovered = false

    // Sky
    private static let skyHigh = Color(red: 0.04, green: 0.05, blue: 0.13)
    private static let skyMid = Color(red: 0.09, green: 0.08, blue: 0.22)
    private static let skyLow = Color(red: 0.16, green: 0.11, blue: 0.24)
    // Moonlight
    private static let moonPale = Color(red: 0.99, green: 0.93, blue: 0.79)
    private static let moonWarm = Color(red: 0.96, green: 0.75, blue: 0.44)
    private static let moonDeep = Color(red: 0.85, green: 0.46, blue: 0.29)
    private static let lampAmber = Color(red: 1.00, green: 0.76, blue: 0.36)
    private static let silhouette = Color(red: 0.03, green: 0.03, blue: 0.08)

    var body: some View {
        ZStack(alignment: .bottom) {
            sky
            NightSky()
            town
            content
        }
        .clipped()
        .onAppear {
            // The moon does not hang in Termina. It arrives.
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                isDescending = true
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

    private var moon: some View {
        GlyphArt(
            rows: TerminaArt.moon,
            size: 12,
            rowSpacing: -3.5,
            fill: LinearGradient(
                colors: [Self.moonPale, Self.moonWarm, Self.moonDeep],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        // The halo is a background rather than a sibling, so it can overflow
        // without claiming layout space and shoving the wordmark down.
        .background {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Self.moonWarm.opacity(0.5), Self.moonDeep.opacity(0.11), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: isGlowing ? 200 : 160
                    )
                )
                .frame(width: 420, height: 420)
        }
        .shadow(color: Self.moonWarm.opacity(0.5), radius: isGlowing ? 24 : 14)
        // The moon does not hang in Termina. It arrives.
        .offset(y: isDescending ? 14 : 0)
        .allowsHitTesting(false)
    }

    private var town: some View {
        ZStack(alignment: .bottom) {
            // The art is a fixed width; this carries the ground to the edges.
            Rectangle()
                .fill(Self.silhouette)
                .frame(height: 26)

            ZStack {
                GlyphArt(
                    rows: TerminaArt.skyline,
                    size: 11,
                    rowSpacing: -3,
                    fill: Self.silhouette
                )
                // Same grid, so the lit clock lands exactly in the tower.
                GlyphArt(
                    rows: TerminaArt.clockFace,
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

            moon

            Spacer(minLength: 24)

            GlyphArt(
                rows: TerminaArt.wordmark,
                size: 11,
                rowSpacing: -3,
                fill: LinearGradient(
                    colors: [Self.moonPale, Self.moonWarm],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .shadow(color: Self.moonWarm.opacity(0.35), radius: 12)

            Text("Dawn of a new terminal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Self.moonPale.opacity(0.55))
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
                            colors: [Self.moonPale, Self.moonWarm],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: Self.moonWarm.opacity(isCTAHovered ? 0.75 : 0.4),
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
        .foregroundStyle(Self.moonPale.opacity(0.42))
    }
}
