import SwiftUI

/// Shown when every tab has been closed.
///
/// With no tabs there is no strip either, so this owns the whole window and
/// can afford to be the loudest thing Majora ever draws.
struct EmptyStateView: View {
    let onNewTab: () -> Void

    @State private var huePhase: Double = 0
    @State private var isBreathing = false
    @State private var isCTAHovered = false

    /// Mirror-symmetric, 40 columns wide.
    private static let mask = """
            ▄▄▄▄▄▄            ▄▄▄▄▄▄        
         ▄▄██████████▄▄▄▄▄▄██████████▄▄     
       ▄████▀▀▀▀▀▀████████████▀▀▀▀▀▀████▄   
      ████    ▄▄▄    ▀████▀    ▄▄▄    ████  
     ████   ▄█████▄   ████   ▄█████▄   ████ 
     ████   ▀█████▀   ████   ▀█████▀   ████ 
      ▀███▄    ▀▀    ██████    ▀▀    ▄███▀  
        ▀████▄▄    ▄████████▄    ▄▄████▀    
           ▀▀████████▀▀▀▀▀▀████████▀▀       
               ▀▀████▄▄▄▄▄▄████▀▀           
                   ▀▀██████▀▀               
                      ▀▀▀▀                  
    """

    private static let palette: [Color] = [
        Color(red: 0.55, green: 0.36, blue: 0.96),
        Color(red: 0.93, green: 0.35, blue: 0.78),
        Color(red: 1.00, green: 0.52, blue: 0.31),
        Color(red: 1.00, green: 0.80, blue: 0.28),
        Color(red: 0.30, green: 0.86, blue: 0.72)
    ]

    var body: some View {
        VStack(spacing: 28) {
            mask
            wordmark
            callToAction
            hints
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: true)) {
                huePhase = 55
            }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }

    /// Rows are laid out individually with negative spacing: a Text's line
    /// height leaves a gap between rows, and block glyphs need to meet.
    private var maskGlyphs: some View {
        VStack(alignment: .leading, spacing: -3) {
            ForEach(Array(Self.mask.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                Text(String(line))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .fixedSize()
            }
        }
    }

    private var mask: some View {
        // The glyphs size the view and then clip a single gradient, so the
        // colour sweeps across the whole mask instead of restarting per row.
        maskGlyphs
            .hidden()
            .overlay {
                LinearGradient(
                    colors: Self.palette,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .mask { maskGlyphs }
            }
            .hueRotation(.degrees(huePhase))
            .shadow(color: Self.palette[1].opacity(0.45), radius: isBreathing ? 26 : 12)
            .scaleEffect(isBreathing ? 1.02 : 1)
            .fixedSize()
            .accessibilityLabel("Majora")
    }

    private var wordmark: some View {
        Text("M A J O R A")
            .font(.system(size: 15, weight: .heavy, design: .monospaced))
            .tracking(6)
            .foregroundStyle(
                LinearGradient(colors: Self.palette, startPoint: .leading, endPoint: .trailing)
            )
            .hueRotation(.degrees(huePhase))
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
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.black.opacity(0.22))
                    }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .padding(.vertical, 15)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [Self.palette[0], Self.palette[1], Self.palette[2]],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .hueRotation(.degrees(huePhase))
                    .shadow(color: Self.palette[1].opacity(isCTAHovered ? 0.6 : 0.3), radius: isCTAHovered ? 20 : 10, y: 4)
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
        .foregroundStyle(.secondary)
    }

    private func hint(_ key: String, _ description: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.white.opacity(0.08))
                }
            Text(description)
                .font(.system(size: 11))
        }
    }
}
