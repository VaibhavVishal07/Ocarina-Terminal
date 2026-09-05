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
  EmptyStateView         no tabs open: the departure board
  DotMatrix              5x7 dot-matrix panel, the board is built from it
  OcarinaIcon            the bundled app mark, trimmed of its plate
  SleepGuard             holds the Mac awake while Ocarina is open
  MainMenu               the menu bar; where ⌘T / ⌘W / ⇧⌘P actually live
  ToolTip                AppKit tool tips, because .help draws none here
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

## Icons and glass

The mark comes from the dot-matrix icon pack. `Icons/AppIcon.iconset` is the
canonical source; the `.icns` a packager wants is one command away and is not
checked in, nor is the Xcode `.appiconset`, which was a byte-for-byte duplicate
of the same PNGs:

```
iconutil -c icns Icons/AppIcon.iconset
```
 Two PNGs are bundled as target resources:
512px for the dock, 64px for the tab strip. A bare SwiftPM executable has no
bundle for macOS to read an icon from, so the dock is told directly with
`applicationIconImage`.

The exports are an opaque black plate with the tile drawn inside, so used as-is
the mark puts a black square on every tab and makes the dock icon read as a
small tile inside a dark square. `OcarinaIcon` trims to the drawn content at
load — and for the dock also clips the tile's corners to transparency and lays
it on a clear canvas at the ~80% the macOS icon grid expects. Trimming at load
rather than shipping cropped assets keeps this from drifting the next time the
pack is regenerated.

The dock image is cut from the 1024px export rather than a smaller one: cutting
the tile out of the plate discards most of the canvas, and from 512 the result
came out at 424px, under what the dock wants at 2x.

Glass needs something behind it to blur. An `NSVisualEffectView` sits behind the
hosting view and the window is non-opaque, so the materials in the chrome have
the desktop to work with; without it they resolve to flat grey. The terminal
view's own background is cleared and a 72% black bed sits behind it — the glass
reads through, and the text stays legible.

## Keyboard shortcuts

⌘T, ⌘W and ⇧⌘P come from the menu bar in `MainMenu`, not from SwiftUI
`.keyboardShortcut`. AppKit offers a key equivalent to the main menu before the
event reaches the window or the responder chain, so a menu item always gets it;
a hidden SwiftUI button only sees what makes it as far as the view hierarchy,
which a terminal view holding first responder can swallow. Ocarina had no main
menu at all for a while, which is why ⌘W did nothing — and why ⌘Q didn't either.

The Edit menu's cut/copy/paste have no target, so they travel the responder
chain to SwiftTerm, which implements them.

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

Close every tab and the window is given over to a dot-matrix panel: a wordmark,
one lit call to action, and the two shortcuts that still mean something with no
terminal open.

It borrows the look of an airport departures board but not its furniture. A
clock, gate numbers and an ON TIME column are what such a board carries because
a flight has a time and a status; a terminal that does not exist yet has
neither, so drawing them was decoration dressed up as information. What earns
its place is the matrix itself.

`DotMatrix` carries a 5x7 font and paints **every** cell of the grid, dark when
it is off. That is the whole character of the thing: the unlit dots stay visible
behind the words, so the text reads as lamps that happen to be on rather than as
glyphs floating on black. Characters are five cells wide with one blank column
between them, so padding two strings to the same length is all it takes to make
their columns line up — no layout code is involved, and it is why the shortcut
rows are padded to a common width rather than centred independently.

One catch: a `Spacer` inside the call to action stretches it across the whole
window, since the stack it sits in is full width. Fixed spacing lets the row
size to its own content.
