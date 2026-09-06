import AppKit
import SwiftUI

/// Says what is wrong, to the person who can fix it.
///
/// It composes the mail rather than sending it. There is no server behind
/// Ocarina and no key in the app, so anything that "just sent" would either be
/// posting to a third party the user never agreed to or shipping a credential
/// inside a binary anyone can download. Handing a filled-in draft to the mail
/// client the user already has keeps the send where the rest of this app keeps
/// it: the last act is theirs, the same reason the recipe drawer types a command
/// instead of running it.
struct FeedbackView: View {
    @Environment(\.theme) private var theme
    let send: (String) -> Void
    let cancel: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Share feedback")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.chrome.textPrimary.color)

            Text("What is broken, missing, or in the way? This opens your mail app with the message ready to send.")
                .font(theme.uiFont(11.5))
                .foregroundStyle(theme.chrome.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $text)
                .focused($isFocused)
                .font(theme.uiFont(12))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 150)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(theme.terminal.background.color)
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(theme.chrome.border.color.opacity(0.14), lineWidth: 1)
                        }
                }
                .overlay(alignment: .topLeading) {
                    // A placeholder rather than a label above the box: the box
                    // is the whole control and a hint inside it is one less
                    // line of chrome.
                    if trimmed.isEmpty {
                        Text("Ocarina does this, and I expected it to do that…")
                            .font(theme.uiFont(12))
                            .foregroundStyle(theme.chrome.textTertiary.color)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

            // Said plainly, before the button rather than after it. Someone
            // typing a complaint is entitled to know where it is going and that
            // their own address goes with it.
            Text("Goes to \(FeedbackMail.recipient) from your mail app, with your build and macOS version attached.")
                .font(theme.uiFont(10.5))
                .foregroundStyle(theme.chrome.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: cancel)
                    .controlSize(.regular)
                Button("Compose Email") { send(trimmed) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(theme.chrome.accent.color)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 420)
        .background(theme.chrome.panelTop.color)
        .onAppear { isFocused = true }
    }
}

/// Builds the draft. Separated from the view so the composed message can be
/// tested without opening anyone's mail client.
enum FeedbackMail {
    static let recipient = "vaibhavvishalece@gmail.com"

    static func subject() -> String {
        "\(AppIdentity.product) feedback"
    }

    /// The report, then the two facts every bug report needs and nobody
    /// remembers to include.
    static func body(_ message: String, version: String, system: String) -> String {
        """
        \(message)

        —
        \(AppIdentity.name) \(version)
        macOS \(system)
        """
    }

    static func url(for message: String,
                    version: String = Self.version,
                    system: String = Self.system) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject()),
            URLQueryItem(name: "body", value: body(message, version: version, system: system)),
        ]
        // `mailto` bodies are percent-encoded, and a `+` in a query is a space
        // to most mail clients — which would eat the plus out of anything the
        // user wrote.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    static var system: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}
