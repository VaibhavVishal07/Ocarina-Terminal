import AppKit
import SwiftUI

/// What the notch drops when an agent finishes something.
///
/// Small on purpose, and the size is the argument. A notification centre banner
/// is a card with a title, a body, an app icon and a dismiss button, and it
/// arrives to tell you six words. This is those six words: the app's mark so
/// you know who is talking, the thing you asked for, and a dot saying it is
/// over. Anything more and it is a window that happens to be near the notch.
///
/// It carries the wordmark rather than an app icon because the wordmark is what
/// Ocarina actually looks like — the same dot matrix as the landing screen and
/// the sidebar, lit from the same three board colours, so a Sakura machine
/// drops a pink one.
struct NotchDrop: View {
    @Environment(\.theme) private var theme

    /// What was asked for, already trimmed to a readable length.
    let title: String
    /// How far out it has come, 0 to 1. Driven by the presenter rather than by
    /// a transition here: the window is a fixed size and the content slides
    /// inside it, so nothing has to resize a window sixty times a second.
    let progress: Double

    /// The visible part, under the notch.
    static let height: CGFloat = 46
    static let width: CGFloat = 320
    /// Square at the top, round at the bottom. The top edge is meant to read as
    /// continuous with the black bar above it rather than as an object that
    /// happens to be near one — a fully rounded pill floating under the notch
    /// is a notification, and this is supposed to be the notch itself moving.
    static let corner: CGFloat = 17

    var body: some View {
        HStack(spacing: 11) {
            DotMatrixText(
                text: "OCARINA",
                cell: 1.5,
                gap: 0.7,
                lit: theme.board.lit.color,
                unlit: theme.board.unlit.color
            )

            Rectangle()
                .fill(theme.chrome.border.color.opacity(0.22))
                .frame(width: 1, height: 16)

            Text(title)
                .font(theme.uiFont(12, weight: .medium))
                .foregroundStyle(theme.chrome.textPrimary.color)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            // "Finished", not "done". The signal underneath is that the agent
            // stopped talking, which does not mean the work succeeded — so the
            // dot is the succeeded colour but nothing here claims a result.
            Circle()
                .fill(theme.status.succeeded.color)
                .frame(width: 6, height: 6)
                .shadow(color: theme.status.succeeded.color.opacity(0.8), radius: 3)
        }
        .padding(.horizontal, 15)
        .frame(width: Self.width, height: Self.height)
        .background {
            NotchShape(corner: Self.corner)
                .fill(.black)
                .overlay {
                    NotchShape(corner: Self.corner)
                        .fill(OcarinaWindowView.panelFill(theme, at: .top))
                        .opacity(0.9)
                }
                .overlay {
                    NotchShape(corner: Self.corner)
                        .stroke(theme.chrome.border.color.opacity(0.18), lineWidth: 1)
                }
        }
        // Out from behind the bar rather than fading in place: it is the notch
        // that is moving, and a notch that dissolves is a notification.
        .offset(y: (progress - 1) * Self.height)
        .opacity(progress)
    }
}

/// Square across the top, rounded across the bottom.
struct NotchShape: Shape {
    let corner: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - corner, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - corner),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}
