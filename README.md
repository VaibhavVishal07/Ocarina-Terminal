# Ocarina Terminal

A terminal for macOS, written in Swift.

Tabs are named after what they are *doing*, not after the binary running inside
them — so a strip of twenty terminals reads as a task list instead of a column
of `zsh` and `Claude`.

## Design docs

- [Context-Aware Tab Naming](docs/context-aware-tab-naming.md) — how tab titles
  are derived from terminal activity and from terminal-based LLM sessions.

## Package layout

`OcarinaTerminalContext` is the naming subsystem. It holds no PTY state and does
no rendering — it takes a `TerminalSessionSnapshot`, asks each provider what the
terminal is doing, and folds the strongest answer into a `TabContext`.

```
Sources/OcarinaTerminalContext/
  ContextSource.swift            priority chain: shell < project < command < llm < manual
  ContextObservation.swift       one provider's reading, with a confidence
  TabContext.swift               per-tab naming state; displayTitle / subtitle
  TabNamingEngine.swift          the stability rules (dwell, margin, no demotion)
  TabContextCoordinator.swift    actor that runs the provider chain per tab
  TitleFormatter.swift           local text -> 2-4 word title. No model, no network.
  Providers/
    LLMSessionContextProvider    shared agent provider; Claude / Codex / Gemini / OpenCode
    ClaudeTranscriptSource       ~/.claude/projects/<slug>/*.jsonl
    CodexTranscriptSource        ~/.codex/sessions/**/rollout-*.jsonl
    GenericProcessContextProvider foreground argv -> title
  Session/
    ProcessInspector             tcgetpgrp + sysctl: what owns the pty right now
    OSCTitleParser               streaming ESC ] 0;title BEL reader
    TerminalSessionMonitor       one pty -> TerminalSessionSnapshot
    TabNamingService             poll loop; publishes tabs whose title changed
```

Wiring a tab:

```swift
let service = TabNamingService()
await service.attach(TerminalSessionMonitor(ptyDescriptor: primaryFD, shellName: "zsh"))
await service.start()

for await tab in await service.updates() {
    tabStrip.rename(tab.tabID, to: tab.displayTitle, subtitle: tab.subtitle)
}
```

The renderer can forward the bytes it already reads to `monitor.ingest(_:)` so
programs that set their own title are picked up; nothing else is read from the
terminal, and nothing leaves the machine.

## The app

```
Sources/OcarinaUI/       SwiftUI layer
  TerminalSession        one tab: pty + SwiftTerm view + naming monitor
  OcarinaModel           open tabs, selection, renames, title updates
  TabStripView           task as the title; process on hover
  CommandPaletteView     jump by what a terminal is doing (⇧⌘P)
  EmptyStateView         no tabs open: the ocarina over Hyrule at dusk
  HyruleArt              the block art, as text rather than image assets
  GlyphArt               draws a glyph stack under a single gradient
  SleepGuard             holds the Mac awake while Ocarina is open
Sources/Ocarina/         executable entry point
```

SwiftTerm is used only as the VT parser and screen grid. Ocarina spawns the pty
itself, via `forkpty`, because `login_tty` is what makes the pty the child's
controlling terminal — and without that `tcgetpgrp` reports nothing and the
naming layer is blind.

```
swift build
swift test
swift run Ocarina
```

## Keeping the Mac awake

Ocarina holds a `PreventUserIdleDisplaySleep` assertion — the same one
`caffeinate -d` takes — for as long as it is open. It is **on by default**: a
terminal is usually waiting on something long, and a display that sleeps through
the build is never what was wanted. The point is to stop needing a `caffeinate`
parked in a spare tab.

The cup in the tab strip says whether the assertion is actually held, and
toggles it. `isHolding` is tracked separately from `isEnabled` because the
system can refuse an assertion, and the cup must not claim the Mac is being kept
awake when it is not.

The assertion is named, so it is never a mystery which app is doing this:

```
$ pmset -g assertions
   pid 62530(Ocarina): [0x0001ec3a00058822] PreventUserIdleDisplaySleep named: "Ocarina is open"
```

The kernel drops a process's assertions when it exits, so quitting Ocarina
always gives it back, including on a crash.

## The empty state

Close every tab and the window is given over to the artwork: the ocarina held
over Hyrule at dusk, Death Mountain west and the castle lit across the field.

Every figure is generated block art rather than a bundled image, so it stays
crisp at any scale and the whole app ships as source. Two details carry it. The
skyline and its lit windows are separate figures on one shared grid, so drawing
the second over the first registers the lamps exactly inside the castle. And the
ocarina's finger holes are a layer *over* the body rather than gaps punched in
it — as gaps, the halo behind the instrument shines through and they read as lit
windows instead of holes.
