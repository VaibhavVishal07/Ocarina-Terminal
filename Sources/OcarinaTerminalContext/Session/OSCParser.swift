import Foundation

/// One `ESC ] <code> ; <payload> BEL|ST` sequence.
public struct OSCSequence: Sendable, Equatable {
    public let code: Int
    public let payload: String

    public init(code: Int, payload: String) {
        self.code = code
        self.payload = payload
    }
}

/// Extracts OSC sequences from a pty stream.
///
/// Ocarina reads two kinds: 0/1/2 (the title a program sets for itself) and 133
/// (shell integration — where a command starts, and what it exited with).
/// Everything else is skipped, and no other terminal output is retained.
///
/// The parser is a streaming state machine because pty reads split wherever
/// they like; a sequence routinely straddles two chunks.
public struct OSCParser: Sendable {
    private enum State: Sendable, Equatable {
        case text
        case sawEscape
        case code
        case payload
        /// Inside a payload, having just seen ESC — `\` here ends it (ST).
        case payloadEscape
    }

    /// Payloads of interest are short; beyond this the parser bails rather
    /// than growing a buffer on hostile output.
    public static let maximumPayloadLength = 512

    /// Codes Ocarina acts on. Anything else is discarded as it is parsed.
    static let interestingCodes: Set<Int> = [0, 1, 2, 133]

    private var state: State = .text
    private var code: String = ""
    private var payload: [UInt8] = []

    public init() {}

    private static let escape: UInt8 = 0x1B
    private static let bell: UInt8 = 0x07
    private static let bracket: UInt8 = 0x5D      // ]
    private static let semicolon: UInt8 = 0x3B    // ;
    private static let backslash: UInt8 = 0x5C    // \

    /// Feed a chunk of pty output; returns the sequences it completed.
    public mutating func consume(_ bytes: some Sequence<UInt8>) -> [OSCSequence] {
        var sequences: [OSCSequence] = []

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
                    state = byte == Self.escape ? .sawEscape : .text
                }

            case .code:
                if byte == Self.semicolon {
                    state = Int(code).map(Self.interestingCodes.contains) == true ? .payload : .text
                } else if let scalar = Unicode.Scalar(UInt32(byte)).map(Character.init), scalar.isNumber {
                    code.append(scalar)
                    if code.count > 3 { state = .text }
                } else {
                    state = .text
                }

            case .payload:
                if byte == Self.bell {
                    if let sequence = finish() { sequences.append(sequence) }
                } else if byte == Self.escape {
                    state = .payloadEscape
                } else {
                    payload.append(byte)
                    if payload.count > Self.maximumPayloadLength { reset() }
                }

            case .payloadEscape:
                if byte == Self.backslash {
                    if let sequence = finish() { sequences.append(sequence) }
                } else {
                    reset()
                    if byte == Self.escape { state = .sawEscape }
                }
            }
        }
        return sequences
    }

    private mutating func finish() -> OSCSequence? {
        let value = String(decoding: payload, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedCode = Int(code)
        reset()
        guard let parsedCode, !value.isEmpty else { return nil }
        return OSCSequence(code: parsedCode, payload: value)
    }

    private mutating func reset() {
        state = .text
        code = ""
        payload = []
    }
}

public extension OSCSequence {
    /// A title the program set for itself.
    var title: String? {
        [0, 1, 2].contains(code) ? payload : nil
    }

    /// Shell integration: `C` starts a command, `D;<status>` ends one.
    /// Returns nil for the other 133 markers (prompt start/end), which Ocarina
    /// does not need.
    var commandBoundary: CommandBoundary? {
        guard code == 133 else { return nil }
        let fields = payload.split(separator: ";", omittingEmptySubsequences: false)
        switch fields.first {
        case "C": return .started
        case "D": return .finished(exitCode: fields.count > 1 ? Int(fields[1]) ?? 0 : 0)
        default: return nil
        }
    }

    enum CommandBoundary: Sendable, Equatable {
        case started
        case finished(exitCode: Int)
    }
}
