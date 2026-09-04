import Foundation

/// Extracts titles a program sets for itself: `ESC ] 0 ; title BEL`.
///
/// Codes 0, 1 and 2 are icon-name/window-title. The parser is a streaming state
/// machine because pty reads split wherever they like — an escape sequence
/// routinely straddles two chunks.
///
/// It looks only for these sequences. It does not retain, buffer or interpret
/// the surrounding terminal output.
public struct OSCTitleParser: Sendable {
    private enum State: Sendable, Equatable {
        case text
        case sawEscape
        /// Collecting the numeric code before the `;`.
        case code
        case payload
        /// Inside a payload, having just seen ESC — a `\` here ends it (ST).
        case payloadEscape
    }

    /// Titles are short. Anything longer is not a title, so the parser bails
    /// rather than growing a buffer on hostile output.
    public static let maximumTitleLength = 512

    private var state: State = .text
    private var code: String = ""
    private var payload: [UInt8] = []

    public init() {}

    private static let escape: UInt8 = 0x1B
    private static let bell: UInt8 = 0x07
    private static let bracket: UInt8 = 0x5D      // ]
    private static let semicolon: UInt8 = 0x3B    // ;
    private static let backslash: UInt8 = 0x5C    // \

    /// Feed a chunk of pty output; returns any titles completed by it.
    public mutating func consume(_ bytes: some Sequence<UInt8>) -> [String] {
        var titles: [String] = []

        for byte in bytes {
            switch state {
            case .text:
                if byte == Self.escape { state = .sawEscape }

            case .sawEscape:
                if byte == Self.bracket {
                    state = .code
                    code = ""
                    payload = []
                } else {
                    // Some other escape sequence; not our business.
                    state = byte == Self.escape ? .sawEscape : .text
                }

            case .code:
                if byte == Self.semicolon {
                    state = isTitleCode(code) ? .payload : .text
                } else if let digit = Unicode.Scalar(UInt32(byte)).map(Character.init), digit.isNumber {
                    code.append(digit)
                    if code.count > 3 { state = .text }
                } else {
                    state = .text
                }

            case .payload:
                if byte == Self.bell {
                    if let title = finishPayload() { titles.append(title) }
                } else if byte == Self.escape {
                    state = .payloadEscape
                } else {
                    payload.append(byte)
                    if payload.count > Self.maximumTitleLength { reset() }
                }

            case .payloadEscape:
                if byte == Self.backslash {
                    if let title = finishPayload() { titles.append(title) }
                } else {
                    // A stray ESC inside a title: treat the sequence as junk.
                    reset()
                    if byte == Self.escape { state = .sawEscape }
                }
            }
        }
        return titles
    }

    private func isTitleCode(_ code: String) -> Bool {
        ["0", "1", "2"].contains(code)
    }

    private mutating func finishPayload() -> String? {
        let title = String(decoding: payload, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        reset()
        return title.isEmpty ? nil : title
    }

    private mutating func reset() {
        state = .text
        code = ""
        payload = []
    }
}
