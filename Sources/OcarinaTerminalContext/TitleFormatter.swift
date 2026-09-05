import Foundation

/// Turns raw text — a prompt, a command, a path — into a scannable tab title.
///
/// Everything here is local string work. No model, no network: the privacy rule
/// in the design doc means titles are earned with heuristics, not inference.
public enum TitleFormatter {
    /// The doc asks for roughly 2–5 words. Four is the working cap: five-word
    /// titles reliably ended in a trailing verb that added nothing.
    public static let defaultWordLimit = 4

    static let acronyms: Set<String> = [
        "api", "ui", "ux", "cli", "ssh", "http", "https", "json", "yaml", "xml",
        "url", "uri", "db", "sql", "css", "html", "js", "ts", "pr", "id", "io",
        "os", "ai", "llm", "pty", "sdk", "cpu", "gpu", "ram", "dns", "tls",
        "ssl", "jwt", "csv", "pdf", "ci", "cd", "qa", "sso", "mfa", "crud",
        "orm", "tv", "grpc", "rpc", "s3", "ftp", "smtp"
    ]

    /// Words with a canonical casing that is neither Title Case nor an acronym.
    /// Checked before `acronyms`.
    static let casedWords: [String: String] = [
        "github": "GitHub", "gitlab": "GitLab", "ios": "iOS", "macos": "macOS",
        "ipados": "iPadOS", "watchos": "watchOS", "tvos": "tvOS",
        "javascript": "JavaScript", "typescript": "TypeScript",
        "nodejs": "Node", "npm": "npm", "graphql": "GraphQL",
        "postgresql": "PostgreSQL", "postgres": "Postgres", "mysql": "MySQL",
        "sqlite": "SQLite", "mongodb": "MongoDB", "openai": "OpenAI",
        "oauth": "OAuth", "youtube": "YouTube", "nginx": "nginx",
        "swiftui": "SwiftUI", "uikit": "UIKit", "appkit": "AppKit",
        "xcode": "Xcode", "webgl": "WebGL", "websocket": "WebSocket",
        "dotfiles": "Dotfiles", "iphone": "iPhone", "ipad": "iPad"
    ]

    /// Words that carry no meaning in a four-word title.
    static let stopWords: Set<String> = [
        "the", "a", "an", "this", "that", "these", "those", "its", "is", "was",
        "are", "were", "be", "been", "being", "some", "any", "my", "our",
        "your", "their", "just", "really", "actually", "currently", "properly",
        "correctly", "again", "why", "what", "how", "whether", "it"
    ]

    /// Conversational lead-ins, stripped before the title is cut.
    static let leadingFiller: [[String]] = [
        ["i", "need", "you", "to"], ["i", "want", "you", "to"],
        ["i", "would", "like", "you", "to"], ["go", "ahead", "and"],
        ["we", "need", "to"], ["i", "need", "to"], ["can", "you"],
        ["could", "you"], ["would", "you"], ["help", "me"], ["let", "us"],
        ["lets"], ["please"], ["now"], ["next"], ["then"], ["also"], ["ok"],
        ["okay"], ["hey"], ["hi"], ["so"]
    ]

    /// A title ends where its first prepositional tail begins — as long as
    /// enough of a title already exists to stand on its own.
    static let tailMarkers: Set<String> = [
        "on", "for", "in", "at", "with", "from", "to", "of", "into", "across",
        "because", "after", "before", "while", "using", "via", "about",
        "under", "over", "during", "when", "so", "and", "but", "then", "that"
    ]

    // MARK: - Natural language

    /// Build a title from something a person typed at an agent.
    public static func title(fromNaturalLanguage text: String, wordLimit: Int = defaultWordLimit) -> String? {
        let sentence = firstSentence(of: text)
        let words = stripLeadingFiller(tokenize(sentence))
        guard !words.isEmpty else { return nil }

        var kept: [String] = []
        for word in words {
            if tailMarkers.contains(word) {
                if kept.count >= 2 { break }
                continue
            }
            if stopWords.contains(word) { continue }
            kept.append(word)
            if kept.count == wordLimit { break }
        }
        guard !kept.isEmpty else { return nil }
        return titleCase(kept)
    }

    // MARK: - Commands

    /// Build a title from a foreground command's argv.
    public static func title(fromCommand argv: [String]) -> String? {
        let args = argv.filter { !$0.isEmpty }
        // Lowercased because argv[0] is whatever the binary is actually called
        // on disk — Xcode's python3 execs as `.../MacOS/Python`, for one.
        guard let executable = args.first.map({ basename($0).lowercased() }) else { return nil }
        let rest = Array(args.dropFirst()).filter { !$0.hasPrefix("-") }

        switch executable {
        case "ssh", "mosh":
            guard let target = rest.first else { break }
            let host = target.split(separator: "@").last.map(String.init) ?? target
            let bare = host.split(separator: ":").first.map(String.init) ?? host
            if let title = humanize(bare) { return title }

        case "npm", "pnpm", "yarn", "bun", "deno":
            // `npm run dev`, `yarn dev`, `pnpm run build`
            var scriptArgs = rest
            if scriptArgs.first == "run" || scriptArgs.first == "run-script" {
                scriptArgs = Array(scriptArgs.dropFirst())
            }
            if let script = scriptArgs.first {
                if let known = scriptTitles[script] { return known }
                if let title = humanize(script) { return title }
            }

        case "python", "python3", "node", "ruby", "perl", "bun-run", "tsx", "ts-node":
            if let file = rest.first, let title = humanize(file) { return title }

        case "make", "just", "task":
            if let target = rest.first, let title = humanize(target) { return title }
            return "Build"

        case "git":
            if let sub = rest.first, let title = humanize(sub) { return "Git \(title)" }

        case "docker", "podman":
            if rest.first == "compose" { return "Docker Compose" }

        case "cargo", "swift", "go":
            if let sub = rest.first {
                if let known = scriptTitles[sub] { return known }
                if let title = humanize(sub) { return title }
            }

        case "vim", "nvim", "nano", "hx", "helix":
            if let file = rest.first, let title = humanize(file) { return "Edit \(title)" }

        case "kubectl", "k9s":
            return "Kubernetes"

        default:
            break
        }

        return humanize(executable)
    }

    static let scriptTitles: [String: String] = [
        "dev": "Dev Server",
        "start": "Dev Server",
        "serve": "Dev Server",
        "build": "Build",
        "test": "Test Suite",
        "lint": "Lint",
        "watch": "Watch",
        "typecheck": "Typecheck",
        "check": "Check"
    ]

    // MARK: - Shared helpers

    /// `generate_report.py` -> `Generate Report`, `production-api` -> `Production API`.
    public static func humanize(_ identifier: String, wordLimit: Int = defaultWordLimit) -> String? {
        var name = basename(identifier)
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            name = String(name[name.startIndex..<dot])
        }
        let words = splitIdentifier(name)
        guard !words.isEmpty else { return nil }
        return titleCase(Array(words.prefix(wordLimit)))
    }

    static func basename(_ path: String) -> String {
        let component = path.split(separator: "/").last.map(String.init) ?? path
        return component.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits on separators and camelCase boundaries.
    static func splitIdentifier(_ name: String) -> [String] {
        var words: [String] = []
        var current = ""

        func flush() {
            if !current.isEmpty { words.append(current.lowercased()) }
            current = ""
        }

        var previous: Character?
        for character in name {
            if character == "_" || character == "-" || character == "." || character == " " {
                flush()
            } else if character.isUppercase, let previous, previous.isLowercase || previous.isNumber {
                flush()
                current.append(character)
            } else if character.isNumber, let previous, previous.isLetter, !current.isEmpty,
                      acronyms.contains(current.lowercased()) == false, current.count > 2 {
                // `report2024` reads better split than glued.
                flush()
                current.append(character)
            } else {
                current.append(character)
            }
            previous = character
        }
        flush()
        return words.filter { !$0.isEmpty }
    }

    static func firstSentence(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Long pastes are almost always context, not the ask.
        let capped = String(trimmed.prefix(600))
        let terminators: Set<Character> = [".", "!", "?", "\n"]
        if let end = capped.firstIndex(where: { terminators.contains($0) }) {
            let sentence = String(capped[capped.startIndex..<end])
            if !sentence.trimmingCharacters(in: .whitespaces).isEmpty { return sentence }
        }
        return capped
    }

    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func stripLeadingFiller(_ words: [String]) -> [String] {
        var words = words
        var changed = true
        while changed {
            changed = false
            for phrase in leadingFiller where words.count > phrase.count {
                if Array(words.prefix(phrase.count)) == phrase {
                    words.removeFirst(phrase.count)
                    changed = true
                    break
                }
            }
        }
        return words
    }

    static func titleCase(_ words: [String]) -> String {
        words.map { word in
            if let cased = casedWords[word] { return cased }
            if acronyms.contains(word) { return word.uppercased() }
            return word.prefix(1).uppercased() + word.dropFirst()
        }
        .joined(separator: " ")
    }

    /// Two titles that differ only in case or spacing are the same title.
    public static func isEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        tokenize(lhs) == tokenize(rhs)
    }
}
