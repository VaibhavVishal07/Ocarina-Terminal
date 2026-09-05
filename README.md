# Majora

A terminal for macOS, written in Swift.

Tabs are named after what they are *doing*, not after the binary running inside
them — so a strip of twenty terminals reads as a task list instead of a column
of `zsh` and `Claude`.

## Design docs

- [Context-Aware Tab Naming](docs/context-aware-tab-naming.md) — how tab titles
  are derived from terminal activity and from terminal-based LLM sessions.

## Package layout

`MajoraTerminalContext` is the naming subsystem. It holds no PTY state and does
no rendering — it takes a `TerminalSessionSnapshot`, asks each provider what the
terminal is doing, and folds the strongest answer into a `TabContext`.

```
Sources/MajoraTerminalContext/
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
Sources/MajoraUI/       SwiftUI layer
  TerminalSession       one tab: pty + SwiftTerm view + naming monitor
  MajoraModel           open tabs, selection, renames, title updates
  TabStripView          task as the title; process on hover
  CommandPaletteView    jump by what a terminal is doing (⇧⌘P)
Sources/Majora/         executable entry point
```

SwiftTerm is used only as the VT parser and screen grid. Majora spawns the pty
itself, via `forkpty`, because `login_tty` is what makes the pty the child's
controlling terminal — and without that `tcgetpgrp` reports nothing and the
naming layer is blind.

```
swift build
swift test
swift run Majora
```
