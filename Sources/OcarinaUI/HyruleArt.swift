import SwiftUI

/// The artwork for Ocarina's empty state: the ocarina held over Hyrule at dusk,
/// with the castle lit on the far side of the field.
///
/// Every piece is generated block art rather than an image, so it stays crisp
/// at any scale and ships as text.
enum HyruleArt {
    /// The ocarina itself: a round vessel body with the mouthpiece stub low on
    /// its right. 36 columns.
    static let ocarina: [String] = [
        "         ▓▓▓▓▓▓▓▓▓▓▓                ",
        "     ▓▓▓▓███████████▓▓▓▓            ",
        "   ▓▓███████████████████▓▓          ",
        "  ▓███████████████████████▓         ",
        " ▓█████████████████████████▓        ",
        " ▓█████████████████████████▓        ",
        " ▓█████████████████████████▓        ",
        " ▓█████████████████████████▓        ",
        " ▓██████████████████████████▓▓▓▓    ",
        "  ▓█████████████████████████████▓▓  ",
        "   ▓▓███████████████████▓▓▓▓▓▓▓▓▓▓  ",
        "     ▓▓▓▓███████████▓▓▓▓            ",
        "         ▓▓▓▓▓▓▓▓▓▓▓                "
    ]

    /// The finger holes, in the same grid as `ocarina`. They are a layer rather
    /// than gaps in the body, because a gap would let the halo behind the art
    /// shine through and read as a window instead of a hole.
    static let ocarinaHoles: [String] = [
        "                                    ",
        "                                    ",
        "                                    ",
        "     ███  ███  ███  ███             ",
        "                                    ",
        "                                    ",
        "                                    ",
        "                                    ",
        "                                    ",
        "        ███    ███                  ",
        "                                    ",
        "                                    ",
        "                                    "
    ]

    /// Hyrule in silhouette: Death Mountain west, the castle across the field,
    /// its spire at the centre. 73 columns.
    static let skyline: [String] = [
        "                                                      ███                ",
        "                                                      ███                ",
        "                                                      ███                ",
        "           ▄ ▄▄▄ ▄                                    ███                ",
        "          ▄█▄███▄█▄                               ▄▄▄▄███▄▄▄▄            ",
        "       ▄▄▄█████████▄▄▄                        ▄▄▄▄███████████▄▄▄▄        ",
        "    ▄▄▄███████████████▄▄▄                     ███████████████████        ",
        "  ▄▄█████████████████████▄▄               ▄▄▄▄███████████████████▄▄▄▄    ",
        "▄▄█████████████████████████▄▄         ▄▄▄▄███████████████████████████▄▄▄▄",
        "█████████████████████████████▄▄▄▄▄▄▄▄▄███████████████████████████████████",
        "█████████████████████████████████████████████████████████████████████████"
    ]

    /// Only the lit windows, in the same grid as `skyline`, so drawing one over
    /// the other registers exactly.
    static let castleLights: [String] = [
        "                                                                         ",
        "                                                                         ",
        "                                                       ▒                 ",
        "                                                                         ",
        "                                                                         ",
        "                                                                         ",
        "                                               ▒▒   ▒▒   ▒▒   ▒▒         ",
        "                                                                         ",
        "                                           ▒▒                     ▒▒     ",
        "                                                                         ",
        "                                                                         "
    ]

    /// OCARINA.
    static let wordmark: [String] = [
        " ██████╗  ██████╗  █████╗ ██████╗ ██╗███╗   ██╗ █████╗ ",
        "██╔═══██╗██╔════╝ ██╔══██╗██╔══██╗██║████╗  ██║██╔══██╗",
        "██║   ██║██║      ███████║██████╔╝██║██╔██╗ ██║███████║",
        "██║   ██║██║      ██╔══██║██╔══██╗██║██║╚██╗██║██╔══██║",
        "╚██████╔╝╚██████╗ ██║  ██║██║  ██║██║██║ ╚████║██║  ██║",
        " ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝"
    ]
}
