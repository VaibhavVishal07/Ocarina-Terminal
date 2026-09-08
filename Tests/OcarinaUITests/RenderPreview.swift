import AppKit
import SwiftTerm
import OcarinaTerminalContext
import SwiftUI
import Testing
@testable import OcarinaUI

/// Not a test — a way to look at the chrome without a screen recorder.
///
/// Off unless it is asked for, so it never runs in the suite. Run it when a
/// change is meant to be visible:
///
///     OCARINA_RENDER=1 swift test --filter RenderPreview
@MainActor
@Suite("Render preview")
struct RenderPreview {

    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["OCARINA_RENDER"] != nil,
        "A look, not a check. Set OCARINA_RENDER=1 to draw it."
    ))
    func sheet() throws {
        BundledFonts.register()
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Themes") ?? []
        let decoder = JSONDecoder()
        let themes = urls
            .compactMap { try? decoder.decode(Theme.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name < $1.name }

        let now = Date()
        let usage = UsageWindow(
            tokens: 1_432_000,
            startedAt: now.addingTimeInterval(-3600 * 1.6),
            resetsAt: now.addingTimeInterval(3600 * 3.4)
        )

        let sheet = HStack(alignment: .top, spacing: 14) {
            ForEach(themes) { theme in
                VStack(alignment: .leading, spacing: 8) {
                    DotMatrixText(
                        text: "OCARINA", cell: 2.2, gap: 1,
                        lit: theme.board.lit.color, unlit: theme.board.unlit.color
                    )
                    Text(theme.name)
                        .font(theme.uiFont(13, weight: .semibold))
                        .foregroundStyle(theme.chrome.textPrimary.color)
                    Text(theme.speech.working)
                        .font(theme.uiFont(11.5, weight: .medium))
                        .foregroundStyle(theme.chrome.textSecondary.color)
                    Text(theme.speech.blurb ?? "")
                        .font(theme.uiFont(10.5, weight: .regular))
                        .foregroundStyle(theme.chrome.textTertiary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    UsageCardView(usage: usage, now: now, place: .top)
                        .panel()
                        .environment(\.theme, theme)
                }
                .frame(width: 190, alignment: .leading)
                .padding(12)
                .background(theme.ground.color)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Shape.houseCorner, style: .continuous))
                .environment(\.theme, theme)
            }
        }
        .padding(18)
        .background(Color.black)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let data = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]))
        let out = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Ocarina-Terminal/build/themes.png")
        try png.write(to: out)
        print("wrote \(out.path)")
    }

    /// Every theme's surface, side by side.
    ///
    /// The one thing about a motif that cannot be checked by assertion: at
    /// 0.05 opacity the question is whether you can tell the panels apart at
    /// all, and whether any of them has tipped over from texture into
    /// wallpaper.
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["OCARINA_RENDER"] != nil,
        "A look, not a check. Set OCARINA_RENDER=1 to draw it."
    ))
    func textures() throws {
        BundledFonts.register()
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Themes") ?? []
        let decoder = JSONDecoder()
        let themes = urls
            .compactMap { try? decoder.decode(Theme.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name < $1.name }

        let sheet = LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(200), spacing: 12), count: 5),
            spacing: 12
        ) {
            ForEach(themes) { theme in
                VStack(alignment: .leading, spacing: 0) {
                    ZStack {
                        OcarinaWindowView.panelSurface(theme, at: .top)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(theme.name)
                                .font(theme.uiFont(12, weight: .semibold))
                                .foregroundStyle(theme.chrome.textPrimary.color)
                            Text(theme.pattern.map { "\($0.shape)" } ?? "no motif")
                                .font(theme.uiFont(10.5, weight: .medium))
                                .foregroundStyle(theme.chrome.textTertiary.color)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 150)
                    .panel()
                    .environment(\.theme, theme)
                }
            }
        }
        .frame(width: 200 * 5 + 12 * 4)
        .padding(16)
        .background(Color.black)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let data = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]))
        let out = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Ocarina-Terminal/build/textures.png")
        try png.write(to: out)
        print("wrote \(out.path)")
    }

    /// The menu bar board, at rest and mid-chase.
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["OCARINA_RENDER"] != nil,
        "A look, not a check. Set OCARINA_RENDER=1 to draw it."
    ))
    func menuBar() throws {
        let lines: [(String, Double?)] = [
            ("READY", nil), ("BACK TO YOU", nil), ("STOPPED 127", nil),
            ("STILL GOING", 4), ("STILL GOING", 14), ("STILL GOING", 26),
            ("STILL GOING", 38), ("STILL GOING", 50),
        ]
        let sheet = VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                // Tinted the way a dark menu bar tints a template image.
                Image(nsImage: ActivityStatusItem.board(line.0, head: line.1))
                    .renderingMode(.template)
                    .foregroundStyle(.white)
            }
        }
        .padding(14)
        .background(Color(white: 0.12))

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 4
        let image = try #require(renderer.nsImage)
        let data = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]))
        let out = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Ocarina-Terminal/build/menubar.png")
        try png.write(to: out)
        print("wrote \(out.path)")
    }

    /// The sidebar, with and without an agent in the tab.
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["OCARINA_RENDER"] != nil,
        "A look, not a check. Set OCARINA_RENDER=1 to draw it."
    ))
    func sidebar() throws {
        BundledFonts.register()
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Themes") ?? []
        let decoder = JSONDecoder()
        let all = urls.compactMap { try? decoder.decode(Theme.self, from: Data(contentsOf: $0)) }
        let theme = try #require(all.first { $0.id == "ocarina" })

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-sidebar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = OcarinaModel()
        let tab = model.newTab(workingDirectory: directory)
        defer { model.closeTab(tab.id) }

        var shots: [NSImage] = []
        for foreground in ["zsh", "claude"] {
            model.noteForegroundForTesting(foreground)
            print("SIDEBAR foreground=\(foreground) skillHome=\(String(describing: model.skillHome?.agent))")
            let view = TabSidebarView(model: model)
                .environment(\.theme, theme)
                .frame(width: OcarinaWindowView.panelWidth, height: 620)
                .background(theme.ground.color)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage { shots.append(image) }
        }

        let sheet = HStack(alignment: .top, spacing: 14) {
            ForEach(Array(shots.enumerated()), id: \.offset) { _, image in
                Image(nsImage: image)
            }
        }
        .padding(14)
        .background(Color.black)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        let data = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]))
        let out = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Ocarina-Terminal/build/sidebar.png")
        try png.write(to: out)
        print("wrote \(out.path)")
    }

    /// Does the terminal actually draw its text?
    ///
    /// SwiftTerm is an `NSView`, so this configures one exactly the way
    /// `TerminalSession.apply` does, feeds it a line, and counts the pixels
    /// that came out different from the background. A count near zero is text
    /// that is not visible, whatever the reason — wrong font, wrong colour,
    /// zero cell size — and it is the one question a screenshot was answering.
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["OCARINA_RENDER"] != nil,
        "A look, not a check. Set OCARINA_RENDER=1 to draw it."
    ))
    func terminalDraws() throws {
        BundledFonts.register()
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Themes") ?? []
        let decoder = JSONDecoder()
        let all = urls.compactMap { try? decoder.decode(Theme.self, from: Data(contentsOf: $0)) }

        for theme in ["ocarina", "matrix", "sakura"].compactMap({ id in all.first { $0.id == id } }) {
            let view = SwiftTerm.TerminalView(
                frame: CGRect(x: 0, y: 0, width: 520, height: 160)
            )
            let terminal = theme.terminal
            view.font = terminal.resolvedFont
            view.nativeForegroundColor = terminal.text.nsColor
            // Opaque here, unlike the app: this is asking whether glyphs are
            // drawn at all, and a clear background over nothing renders
            // nothing to compare them against.
            view.nativeBackgroundColor = terminal.background.nsColor
            view.installColors(terminal.palette.map(\.swiftTermColor))
            view.feed(text: "the quick brown fox 0123456789\r\n")

            view.layoutSubtreeIfNeeded()
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)

            let background = terminal.background
            var different = 0
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                for y in stride(from: 0, to: min(40, rep.pixelsHigh), by: 2) {
                    guard let c = rep.colorAt(x: x, y: y) else { continue }
                    let d = abs(Double(c.redComponent) - background.red)
                        + abs(Double(c.greenComponent) - background.green)
                        + abs(Double(c.blueComponent) - background.blue)
                    if d > 0.10 { different += 1 }
                }
            }
            print("TERMINAL \(theme.id): font=\(view.font.fontName) size=\(view.font.pointSize) inkPixels=\(different)")

            if let png = rep.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent("Ocarina-Terminal/build/terminal-\(theme.id).png"))
            }
        }
    }

    /// The skills browser, across a few themes.
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["OCARINA_RENDER"] != nil,
        "A look, not a check. Set OCARINA_RENDER=1 to draw it."
    ))
    func skills() throws {
        BundledFonts.register()
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Themes") ?? []
        let decoder = JSONDecoder()
        let all = urls.compactMap { try? decoder.decode(Theme.self, from: Data(contentsOf: $0)) }
        let themes = ["ocarina", "sakura", "matrix"].compactMap { id in all.first { $0.id == id } }
        let home = try #require(SkillHome.forProcess("claude"))

        // The rows and chips directly, not the whole view: `ImageRenderer`
        // lays out no `ScrollView`'s content, and both of those live in one.
        let shown = Array(SkillCatalog.load().prefix(8))
        let sheet = HStack(alignment: .top, spacing: 16) {
            ForEach(themes) { theme in
                let view = SkillsView(home: home) {}
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Skills")
                            .font(theme.uiFont(15, weight: .semibold))
                            .foregroundStyle(theme.chrome.textPrimary.color)
                        Text("for \(home.agent)")
                            .font(theme.uiFont(11.5, weight: .medium))
                            .foregroundStyle(theme.chrome.textTertiary.color)
                    }
                    HStack(spacing: 6) {
                        view.chip("All", isOn: true) {}
                        view.chip("Design", isOn: false) {}
                        view.chip("Testing", isOn: false) {}
                        view.chip("Cloud", isOn: false) {}
                    }
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10),
                                  GridItem(.flexible(), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(shown) { view.card($0) }
                    }
                }
                .padding(18)
                .frame(width: 780, alignment: .leading)
                .background { OcarinaWindowView.panelSurface(theme, at: .top) }
                .clipShape(OcarinaWindowView.PanelStyle.shape)
                .environment(\.theme, theme)
            }
        }
        .padding(18)
        .background(Color.black)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let data = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]))
        let out = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Ocarina-Terminal/build/skills.png")
        try png.write(to: out)
        print("wrote \(out.path)")
    }

    /// The landing screen's name lighting up, column by column.
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["OCARINA_RENDER"] != nil,
        "A look, not a check. Set OCARINA_RENDER=1 to draw it."
    ))
    func arrival() throws {
        BundledFonts.register()
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Themes") ?? []
        let decoder = JSONDecoder()
        let all = urls.compactMap { try? decoder.decode(Theme.self, from: Data(contentsOf: $0)) }
        let theme = try #require(all.first { $0.id == "ocarina" })

        let sheet = VStack(alignment: .leading, spacing: 10) {
            ForEach([0.0, 0.2, 0.4, 0.6, 0.8, 1.0], id: \.self) { reveal in
                DotMatrixText(
                    text: "OCARINA", cell: 4.4, gap: 1.6,
                    lit: theme.board.lit.color,
                    unlit: theme.board.unlit.color,
                    reveal: reveal
                )
                .environment(\.theme, theme)
            }
        }
        .padding(20)
        .background(theme.board.backdrop.color)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let data = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]))
        let out = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Ocarina-Terminal/build/arrival.png")
        try png.write(to: out)
        print("wrote \(out.path)")
    }

    /// The mark's chase, as a filmstrip.
    ///
    /// Eight frames a fifth of a second apart, so the head is visibly further
    /// along the word in each — which is the one thing about the chase that a
    /// still cannot show and a compiler cannot check.
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["OCARINA_RENDER"] != nil,
        "A look, not a check. Set OCARINA_RENDER=1 to draw it."
    ))
    func chaseFilmstrip() throws {
        BundledFonts.register()
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Themes") ?? []
        let decoder = JSONDecoder()
        let all = urls.compactMap { try? decoder.decode(Theme.self, from: Data(contentsOf: $0)) }
        let theme = try #require(all.first { $0.id == "ocarina" })

        var frames: [NSImage] = []
        for _ in 0..<8 {
            let mark = DotMatrixText(
                text: "OCARINA", cell: 4, gap: 2,
                lit: theme.board.lit.color, unlit: theme.board.unlit.color,
                chase: true
            )
            .padding(10)
            .background(theme.ground.color)
            .environment(\.theme, theme)

            let renderer = ImageRenderer(content: mark)
            renderer.scale = 2
            frames.append(try #require(renderer.nsImage))
            Thread.sleep(forTimeInterval: 0.2)
        }

        let sheet = VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(frames.enumerated()), id: \.offset) { _, image in
                Image(nsImage: image)
            }
        }
        .padding(8)
        .background(Color.black)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        let data = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]))
        let out = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Ocarina-Terminal/build/chase.png")
        try png.write(to: out)
        print("wrote \(out.path)")
    }

    /// The token card in both states, across a few themes: nothing spent yet,
    /// and a window part-way through.
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["OCARINA_RENDER"] != nil,
        "A look, not a check. Set OCARINA_RENDER=1 to draw it."
    ))
    func usageCard() throws {
        BundledFonts.register()
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Themes") ?? []
        let decoder = JSONDecoder()
        let all = urls.compactMap { try? decoder.decode(Theme.self, from: Data(contentsOf: $0)) }
        let themes = ["ocarina", "steel", "sakura", "matrix", "superman", "high-contrast"]
            .compactMap { id in all.first { $0.id == id } }

        let now = Date()
        // Nothing, a window just opened, one part-way through, one nearly out.
        let states: [(String, UsageWindow?)] = [
            ("no window", nil),
            ("just opened", UsageWindow(tokens: 12_400, startedAt: now.addingTimeInterval(-60), resetsAt: now.addingTimeInterval(3600 * 5 - 60))),
            ("part way", UsageWindow(tokens: 1_432_000, startedAt: now.addingTimeInterval(-3600 * 1.6), resetsAt: now.addingTimeInterval(3600 * 3.4))),
            ("nearly out", UsageWindow(tokens: 4_100_000, startedAt: now.addingTimeInterval(-3600 * 4.7), resetsAt: now.addingTimeInterval(3600 * 0.3))),
        ]

        let sheet = VStack(alignment: .leading, spacing: 10) {
            ForEach(themes) { theme in
                HStack(alignment: .top, spacing: 12) {
                    Text(theme.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 90, alignment: .leading)
                    ForEach(states, id: \.0) { label, usage in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(label)
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.45))
                            UsageCardView(usage: usage, now: now)
                                .frame(width: OcarinaWindowView.panelWidth)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Shape.houseCorner, style: .continuous))
                        }
                    }
                }
                .environment(\.theme, theme)
            }
        }
        .padding(18)
        .background(Color.black)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let data = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]))
        let out = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Ocarina-Terminal/build/usage-card.png")
        try png.write(to: out)
        print("wrote \(out.path)")
    }
}
