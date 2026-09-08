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

    /// The menu bar card: all four states, and the turn frame by frame.
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["OCARINA_RENDER"] != nil,
        "A look, not a check. Set OCARINA_RENDER=1 to draw it."
    ))
    func menuBar() throws {
        // The three still cards, then every frame of the turn.
        let sheet = HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array([ActivityCard.ready, .backToYou, .stopped].enumerated()),
                        id: \.offset) { _, card in
                    // Tinted the way a dark menu bar tints a template image.
                    Image(nsImage: ActivityStatusItem.glyph(card))
                        .renderingMode(.template)
                        .foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(ActivityCard.turn.indices), id: \.self) { index in
                    Image(nsImage: ActivityStatusItem.glyph(.working, turn: index))
                        .renderingMode(.template)
                        .foregroundStyle(.white)
                }
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
        let shelf = SkillShelf()

        // The rows and the headings directly, not the whole view:
        // `ImageRenderer` lays out no `ScrollView`'s content, and the shelf
        // lives in one. This is the "Start here" page as it is drawn.
        let picks = SkillCatalog.starting(from: SkillCatalog.load())
        let sheet = HStack(alignment: .top, spacing: 16) {
            ForEach(themes) { theme in
                let view = SkillsView(
                    home: home, shelf: shelf, startClaude: {}, close: {}
                )
                VStack(alignment: .leading, spacing: 0) {
                    Text("Skills")
                        .font(theme.uiFont(15.5, weight: .semibold))
                        .foregroundStyle(theme.chrome.textPrimary.color)
                    Text("Written instructions your agent reads when a task calls for it.")
                        .font(theme.uiFont(11.5))
                        .foregroundStyle(theme.chrome.textTertiary.color)
                        .padding(.bottom, 16)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(theme.uiFont(11.5, weight: .medium))
                            .foregroundStyle(theme.chrome.textTertiary.color)
                        Text("Search 216 skills")
                            .font(theme.uiFont(12.5))
                            .foregroundStyle(theme.chrome.textTertiary.color)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(theme.chrome.rowHover.color.opacity(0.07))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(theme.chrome.border.color.opacity(0.14), lineWidth: 1)
                            }
                    }
                    .padding(.bottom, 18)

                    // The tab row, sitting on its rule.
                    HStack(spacing: 20) {
                        ForEach(Array(["Start here", "Browse all", "Installed"].enumerated()),
                                id: \.offset) { index, label in
                            Text(label)
                                .font(theme.uiFont(12, weight: index == 0 ? .semibold : .medium))
                                .foregroundStyle(index == 0 ? theme.chrome.textPrimary.color
                                                            : theme.chrome.textTertiary.color)
                                .padding(.top, 2)
                                .padding(.bottom, 11)
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(theme.chrome.textPrimary.color.opacity(index == 0 ? 0.6 : 0))
                                        .frame(height: 1.5)
                                }
                        }
                        Spacer(minLength: 0)
                    }
                    .background(alignment: .bottom) {
                        Rectangle()
                            .fill(theme.chrome.border.color.opacity(0.13))
                            .frame(height: 1)
                    }
                    .padding(.bottom, 20)

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 14),
                                  GridItem(.flexible(), spacing: 14)],
                        spacing: 14
                    ) {
                        ForEach(picks, id: \.skill.id) { pick in
                            view.card(pick.skill)
                        }
                    }
                    .padding(.bottom, 22)

                    HStack(spacing: 6) {
                        view.pill("All", isOn: false) {}
                        view.pill("Design", isOn: true) {}
                        view.pill("Workflow", isOn: false) {}
                        view.pill("Testing", isOn: false) {}
                    }
                }
                .padding(22)
                .frame(width: 600, alignment: .leading)
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

    /// The column's fall, at both depths.
    ///
    /// The one thing the assertions cannot answer: three cards now carry the
    /// gradient the sidebar used to cut in two, and the question is whether
    /// the column still reads as one light falling once — or as a stack that
    /// steps. The two-card column beside it is the control.
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["OCARINA_RENDER"] != nil,
        "A look, not a check. Set OCARINA_RENDER=1 to draw it."
    ))
    func columns() throws {
        BundledFonts.register()
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Themes") ?? []
        let decoder = JSONDecoder()
        let themes = urls
            .compactMap { try? decoder.decode(Theme.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name < $1.name }
            .prefix(6)

        func card(_ theme: Theme, _ place: OcarinaWindowView.PanelPlace,
                  _ height: CGFloat, _ label: String) -> some View {
            ZStack(alignment: .topLeading) {
                OcarinaWindowView.panelSurface(theme, at: place)
                Text(label)
                    .font(theme.uiFont(10, weight: .medium))
                    .foregroundStyle(theme.chrome.textTertiary.color)
                    .padding(8)
            }
            .frame(height: height)
            .panel()
            .environment(\.theme, theme)
        }

        let sheet = HStack(alignment: .top, spacing: 16) {
            ForEach(Array(themes)) { theme in
                VStack(alignment: .leading, spacing: 8) {
                    Text(theme.name)
                        .font(theme.uiFont(12, weight: .semibold))
                        .foregroundStyle(theme.chrome.textPrimary.color)
                    HStack(alignment: .top, spacing: 10) {
                        // The sidebar: three cards now.
                        VStack(spacing: OcarinaWindowView.panelGap) {
                            card(theme, .top, 300, "tabs")
                            card(theme, .middle, 71, "state")
                            card(theme, .foot, 71, "doors")
                        }
                        // The right-hand column: still two.
                        VStack(spacing: OcarinaWindowView.panelGap) {
                            card(theme, .top, 330, "tasks")
                            card(theme, .bottom, 122, "window")
                        }
                    }
                }
                .frame(width: 230)
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
            .appendingPathComponent("Ocarina-Terminal/build/columns.png")
        try png.write(to: out)
        print("wrote \(out.path)")
    }

    /// The whole window, as close as a renderer can get to it.
    ///
    /// Every panel here is the app's own view drawn from a real `OcarinaModel`
    /// — the sidebar, the task list, the token card, the terminal's bed. The
    /// one part that is not is the terminal *text*: SwiftTerm's view is an
    /// `NSView`, and `ImageRenderer` walks the SwiftUI tree, so an AppKit view
    /// comes back blank. The lines are set here in the theme's own terminal
    /// font and ANSI palette, which is what the emulator would have drawn
    /// them in. The same limit is why the two switches in the sidebar render
    /// as placeholders: `NSSwitch` is AppKit too.
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["OCARINA_RENDER"] != nil,
        "A look, not a check. Set OCARINA_RENDER=1 to draw it."
    ))
    func window() throws {
        BundledFonts.register()
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Themes") ?? []
        let decoder = JSONDecoder()
        let all = urls.compactMap { try? decoder.decode(Theme.self, from: Data(contentsOf: $0)) }
        let theme = try #require(all.first { $0.id == "ocarina" })

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-window-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let model = OcarinaModel()
        let names = [
            "Wire the status item to the poll",
            "Take the marks off the tabs",
            "Cut 0.8.0",
            "npm run build"
        ]
        var made: [TabItem] = []
        for name in names {
            let tab = model.newTab(workingDirectory: root)
            model.rename(tab.id, to: name)
            made.append(tab)
        }
        defer { made.forEach { model.closeTab($0.id) } }
        if let first = made.first { model.selectTab(first.id) }
        model.noteForegroundForTesting("claude")

        let now = Date()
        func ask(_ title: String, _ state: AgentTask.State, _ minutesAgo: Int) -> AgentTask {
            AgentTask(id: title, title: title, prompt: title,
                      askedAt: now.addingTimeInterval(TimeInterval(-60 * minutesAgo)),
                      state: state)
        }
        let tasks = [
            ask("Read the transcript once", .finished, 34),
            ask("Drop the notch banner", .finished, 26),
            ask("Rename the tab on the prompt", .finished, 19),
            ask("Take the marks off the tabs", .finished, 11),
            ask("Wire the status item to the poll", .working, 3)
        ]
        let usage = UsageWindow(
            tokens: 1_432_000,
            startedAt: now.addingTimeInterval(-3600 * 1.6),
            resetsAt: now.addingTimeInterval(3600 * 3.4)
        )

        // What the emulator would be showing. Set in the theme's terminal font
        // and its own ANSI colours, at the inset the real terminal sits at.
        let mono = Font.custom(theme.terminal.fontName, size: theme.terminal.fontSize)
        func line(_ text: String, _ colour: ThemeColor) -> some View {
            Text(text).font(mono).foregroundStyle(colour.color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        let ink = theme.terminal.foreground
        let prompt = theme.terminal.ansi.count > 6 ? theme.terminal.ansi[6] : ink
        let quiet = theme.terminal.ansi.count > 8 ? theme.terminal.ansi[8] : ink
        let ok = theme.terminal.ansi.count > 2 ? theme.terminal.ansi[2] : ink

        let screen = VStack(alignment: .leading, spacing: 3) {
            line("› claude", prompt)
            line("", ink)
            line("› wire the status item to the poll so the list is never stale", ink)
            line("", ink)
            line("  Read  Sources/OcarinaUI/ActivityStatusItem.swift", quiet)
            line("  Edit  Sources/OcarinaUI/ActivityStatusItem.swift  +97 −8", quiet)
            line("  Edit  Sources/OcarinaUI/OcarinaModel.swift  +27 −6", quiet)
            line("  Bash  swift test", quiet)
            line("        ✔ Test run with 275 tests in 40 suites passed", ok)
            line("", ink)
            line("  The menu bar's menu carries the last five asks now, marked", ink)
            line("  the way the panel marks them. The single task row above", ink)
            line("  them is gone — it named the newest open ask, which is the", ink)
            line("  first row of the list under another name.", ink)
            line("", ink)
            line("› ▌", prompt)
            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 14)

        let window = HStack(spacing: OcarinaWindowView.panelGap) {
            TabSidebarView(model: model)

            ZStack {
                TerminalBed(activity: .running)
                screen
            }
            .panel()

            VStack(spacing: OcarinaWindowView.panelGap) {
                TaskPanelView(tasks: tasks) {}
                    .frame(maxHeight: .infinity)
                    .panel()
                UsageCardView(usage: usage, now: now, place: .bottom)
                    .panel()
            }
            .frame(width: OcarinaWindowView.panelWidth)
        }
        .padding(OcarinaWindowView.panelGap)
        // The size `docs/images/window.png` is checked in at, so the README's
        // hero can be regenerated by running this rather than by finding a Mac
        // with screen recording granted to whatever the shell is attributed to.
        .frame(width: 1180, height: 720)
        .background(theme.ground.color)
        .environment(\.theme, theme)

        // Hosted and asked to draw itself, rather than run through
        // `ImageRenderer`.
        //
        // The renderer walks the SwiftUI tree, and two things in this window
        // are not in it: a `LazyVStack` only builds its rows when a real
        // scroll view asks for them, so the tab list and the task list both
        // came back as empty cards; and `NSSwitch` is AppKit, so the two
        // switches came back as placeholder squares. An `NSHostingView` in an
        // offscreen window has both — it lays out for real and `cacheDisplay`
        // draws the layer tree the app would put on screen.
        //
        // No screen recording permission is involved. This is the app drawing
        // itself into a bitmap, not anything reading the display.
        let png = try Self.shoot(window, size: CGSize(width: 1180, height: 720))
        let out = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Ocarina-Terminal/build/window.png")
        try png.write(to: out)
        print("wrote \(out.path)")
    }

    /// Draws a view the way the app would, at 2×.
    static func shoot<V: View>(_ view: V, size: CGSize) throws -> Data {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        // Laid out before it is asked for a picture: without this the hosting
        // view hands back its bounds with nothing arranged inside them.
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        // A turn of the run loop, so the scroll views the lazy stacks live in
        // have actually asked for their rows.
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        host.layoutSubtreeIfNeeded()

        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }
}
