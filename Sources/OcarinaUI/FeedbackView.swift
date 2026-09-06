import AppKit
import SwiftUI

/// Says what is wrong, without asking who you are.
///
/// It used to compose a `mailto:`, which quietly demanded two things: a mail
/// app that is set up, and the reporter's own address attached to the
/// complaint. Neither is fair to ask of somebody whose entire contribution is
/// telling you a button is broken.
///
/// So there are two ways out and neither needs an account you have to give up
/// something for. Opening an issue takes the report to the repository with the
/// text already in it; copying puts the same report on the clipboard for
/// whatever channel the person actually uses. Both are still one deliberate
/// press, because that is where this app keeps the last act.
struct FeedbackView: View {
    @Environment(\.theme) private var theme
    let openIssue: (String) -> Void
    let copy: (String) -> Void
    let cancel: () -> Void

    @State private var text = ""
    @State private var didCopy = false
    @FocusState private var isFocused: Bool

    /// Shared by the editor and the placeholder, so the hint sits exactly where
    /// the first character will.
    private static let editorInset: CGFloat = 14
    private static let editorLead: CGFloat = 12

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            editor
            divider
            footer
        }
        .frame(width: 460)
        // Half the system sheet's rounding. The window's own corner is taken
        // out of the picture with a clear presentation background, so the only
        // radius on screen is this one.
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.chrome.panelTop.color)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .presentationBackground(.clear)
        .onAppear { isFocused = true }
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.chrome.border.color.opacity(0.12))
            .frame(height: 1)
    }

    /// The board's alphabet, because this sheet is the one place the app asks
    /// for something rather than doing something, and the mark is what it has
    /// instead of a personality.
    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            DotMatrixText(
                text: "FEEDBACK",
                // Small: it is a mark on a sheet, not the sheet's headline.
                cell: 1.7,
                gap: 0.85,
                lit: theme.board.lit.color,
                unlit: theme.board.unlit.color
            )
            .accessibilityLabel("Feedback")

            Text("Something in here annoyed you. Good \u{2014} that is the useful kind.")
                .font(theme.uiFont(11.5))
                .foregroundStyle(theme.chrome.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 15)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .focused($isFocused)
                .font(theme.uiFont(12.5))
                .foregroundStyle(theme.chrome.textPrimary.color)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Self.editorInset)
                .padding(.vertical, Self.editorLead)

            // A hint inside the box rather than a label above it: the box is the
            // whole control, and the sheet is short enough already.
            if trimmed.isEmpty {
                Text("It called the tab zsh for twenty minutes and I believed it\u{2026}")
                    .font(theme.uiFont(12.5))
                    .foregroundStyle(theme.chrome.textTertiary.color)
                    // The editor's own padding, plus the 5pt of line-fragment
                    // padding `NSTextView` adds inside it and SwiftUI does not
                    // expose. Guessed at 20 vertical before, so the first
                    // keystroke jumped the text 8pt up the box.
                    .padding(.leading, Self.editorInset + 5)
                    .padding(.trailing, Self.editorInset)
                    .padding(.vertical, Self.editorLead)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 168)
        .background(theme.terminal.background.color.opacity(0.5))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            // Said before the buttons, not after: somebody typing a complaint is
            // entitled to know what is attached to it.
            Label("Your build and macOS version ride along. Nothing else does.",
                  systemImage: "info.circle")
                .font(theme.uiFont(10.5))
                .foregroundStyle(theme.chrome.textTertiary.color)
                .labelStyle(.titleAndIcon)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(didCopy ? "Copied" : "Copy") {
                copy(trimmed)
                didCopy = true
            }
            .controlSize(.regular)
            .disabled(trimmed.isEmpty)

            Button("Open an Issue") { openIssue(trimmed) }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(theme.chrome.accent.color)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .onChange(of: text) { _, _ in didCopy = false }
        .overlay(alignment: .topLeading) {
            // Escape closes the sheet; the button is not drawn because the
            // sheet already has two and a third would crowd them.
            Button("", action: cancel)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
    }
}

/// Builds the report. Separated from the view so what gets sent can be tested
/// without opening a browser.
enum FeedbackReport {
    /// Where an issue is opened. The repository is public, so this needs no key
    /// in the app and no server behind it.
    static let repository = "VaibhavVishal07/Ocarina-Terminal"

    /// The report, then the two facts every report needs and nobody remembers
    /// to include.
    static func body(_ message: String, version: String, system: String) -> String {
        """
        \(message)

        ---
        \(AppIdentity.name) \(version) · macOS \(system)
        """
    }

    static func issueURL(for message: String,
                         version: String = Self.version,
                         system: String = Self.system) -> URL? {
        guard var components = URLComponents(
            string: "https://github.com/\(repository)/issues/new"
        ) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "title", value: Self.title(from: message)),
            URLQueryItem(name: "body", value: body(message, version: version, system: system)),
        ]
        // A `+` in a query is a space to most readers, which would eat the plus
        // out of anything the reporter wrote.
        let encoded = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        components.percentEncodedQuery = encoded
        return components.url
    }

    /// The first line, capped — an issue list of forty-word titles is unusable.
    static func title(from message: String) -> String {
        let firstLine = message
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? message
        guard firstLine.count > 72 else { return firstLine }
        return String(firstLine.prefix(71)).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    static var system: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}
