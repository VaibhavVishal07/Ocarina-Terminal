import SwiftUI

/// Draws block art with a single fill spanning the whole figure.
///
/// Two details matter. Rows are separate `Text`s with negative spacing, because
/// a `Text`'s line height leaves a gap and block glyphs have to meet. And the
/// fill is applied by masking one shape with the entire glyph stack — putting a
/// gradient on each row would restart the colour on every line.
struct GlyphArt<Fill: ShapeStyle>: View {
    let rows: [String]
    var size: CGFloat = 11
    var weight: Font.Weight = .bold
    var rowSpacing: CGFloat = -3
    let fill: Fill

    private var glyphs: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Text(row)
                    .font(.system(size: size, weight: weight, design: .monospaced))
                    .fixedSize()
            }
        }
    }

    var body: some View {
        glyphs
            .hidden()
            .overlay { Rectangle().fill(fill).mask { glyphs } }
            .fixedSize()
    }
}
