<div align="center">

<img src="docs/images/icon.png" width="104" alt="Ocarina">

# Ocarina Terminal

**A macOS terminal for people who were never taught one.**

</div>

<img src="docs/images/window.png" alt="The Ocarina window: tab sidebar, terminal, task panel">

A terminal assumes you already know. It opens a blank rectangle, prints a `%`,
and waits. If you know what to type, it is the fastest tool on the machine. If
you do not, it is a locked door with no sign on it — and every instruction you
find for getting through it was written by someone who forgot they ever had to
ask.

Ocarina is the same terminal, built the other way round. It says what it is
doing, keeps the list of what you asked for, offers the command instead of
expecting it, explains the error instead of printing it, and never runs anything
you did not trigger yourself.

That turns out to matter twice over. The person who has never opened a terminal
needs it because nothing else tells them anything. The person running five
agents at once needs it because five terminals called `zsh` is not a list, it is
a guessing game.

Nothing leaves the machine. Every title, task and explanation is derived
locally, from files the tools already write.

New to this entirely? [Start here](docs/first-terminal.md).

---

## Download

**[Ocarina for macOS](https://github.com/VaibhavVishal07/Ocarina-Terminal/releases/latest)**
— one universal build for Apple Silicon and Intel. macOS 14 or later.

Unzip it and drag `Ocarina.app` into Applications.

**The first launch needs one extra step.** The app is signed ad-hoc rather than
notarised — notarising requires a paid Apple Developer account — so macOS will
refuse to open it and say it cannot check it for malicious software. That is
Gatekeeper telling you the truth: nobody has vouched for this binary but the
person who built it. To open it anyway:

1. Right-click (or Control-click) `Ocarina.app` and choose **Open**.
2. Click **Open** again in the dialog.
3. If macOS still refuses, go to **System Settings → Privacy & Security**, scroll
   to the message about Ocarina, and click **Open Anyway**.

Only the first launch asks. If you would rather do it in one line — in whatever
terminal you have now, since this is the one you are trying to install:

```
xattr -dr com.apple.quarantine /Applications/Ocarina.app
```

Or build it yourself, which needs no permission from anyone:
[Running it](#running-it).

---

## The tabs name themselves

The tab is not called `zsh`. It is called what the terminal is *doing*: the
prompt you gave an agent, the command that is running, the project you are in.

Ocarina reads that from three places, in order of how much they know — the
transcript an agent is already writing, the foreground process on the pty, and
the directory the shell is sitting in. A stability layer decides when a new
answer is good enough to replace the one on screen, so a title does not flicker
every time a command finishes.

A dot on each row says idle, running, succeeded or failed, so a column of twenty
can be read down the edge without stopping at any of the names.

[How the naming works](docs/context-aware-tab-naming.md) — the provider chain,
the priorities and the stability rules.

## It remembers what you asked the agent

You give an agent five things across twenty minutes and cannot remember which of
them it actually got to. The panel down the right is that list, read from the
transcript the agent writes anyway — so it costs the session nothing and it
survives scrollback.

`TaskSummariser` asks Claude to rewrite the local titles, because it is better
at it: "Toggle option near right-hand" becomes "Move toggle to right side".
Three rules follow from where that work happens.

- The local condenser runs first, so a title is on screen immediately and a
  machine with no agent installed loses nothing it had.
- Every prompt is asked about once, ever, cached on disk by the transcript's own
  uuid. This spends your Claude allowance.
- **It waits for a keystroke.** Running the `claude` binary means a subprocess,
  and a subprocess inherits the app's TCC identity — every protected thing it
  reads is asked about in Ocarina's name. Doing it at startup put "Ocarina would
  like to access your Photo Library" in front of someone who had done nothing
  but open a terminal. The first keystroke cannot happen at launch, and it means
  the session is genuinely in use.

## It tells you what to type

<img src="docs/images/quick-actions.png" alt="The quick actions drawer: install an agent, and the things agents need">

⌘K opens a drawer of recipes — install an agent, install the things agents
assume you already have. Each one says what it does before you choose it.

It does not run anything. Choosing a recipe **types** its command at the prompt
and leaves the cursor after it, so the last act is always yours. That is
deliberate on two counts: nothing executes that you did not trigger, and you see
the command each time, which is how you eventually stop needing the drawer at
all.

Recipes live in `Sources/OcarinaUI/Resources/Recipes/`, extended from
`~/.ocarina/recipes/`.

## It reads a paste before the shell does

The most dangerous thing a beginner does in a terminal is paste something from
the internet. ⌘V goes through `PasteInspector` rather than straight to the
emulator.

Anything unremarkable is pasted with no ceremony, because a terminal that
interrupts every paste is one people learn to click through. Only multi-command
or risky text stops for review, with a line on each part saying what it will do.

## It explains what just broke

A command fails and prints something the person who ran it cannot read. For the
user this app is for, that is not an inconvenience — it is where the session
ends, because there is nothing they can do next.

Ocarina already knows the command failed and what is on the screen, and an agent
is usually installed a tab away. A banner offers to hand the exit code and the
visible screen to whichever of `claude`, `gemini` or `codex` is present.
Dismissing it means "I have read this one", not "stop telling me when things
break" — the next failure brings it back.

## It looks like something you chose

<img src="docs/images/themes.png" alt="The theme picker, fourteen themes">

Fourteen bundled themes, applied as you pick. Each is a JSON file carrying the
chrome colours, the terminal bed, a sixteen-colour ANSI palette and an optional
background motif. Drop your own in `~/.ocarina/themes/` and they appear beside
the bundled ones.

The picker is not a sheet. A sheet on macOS is modal and will not dismiss on a
click outside it, and picking a theme is a thing you do by trying three and then
getting on with your work.

Choosing a theme also sets `NSApp.appearance`. System controls — the keep-awake
switch, the menus, the window's own furniture — draw themselves and take their
cue from `NSAppearance`, not from us; without this a light theme kept a dark
switch and dark scrollbars, which reads as a half-finished theme rather than a
choice.

Text is Geist and Geist Mono, bundled under the OFL and registered before the
first frame draws, so nothing flashes through a fallback face on its way to the
right one.

## It stays awake while you wait

Ocarina holds a `PreventUserIdleDisplaySleep` assertion — the same one
`caffeinate -d` takes — for as long as it is open. It is **on by default**: a
terminal is usually waiting on something long, and a display that sleeps through
the build is never what was wanted. The point is to stop needing a `caffeinate`
parked in a spare tab.

The switch in the sidebar says whether the assertion is actually held, and
toggles it. `isHolding` is tracked separately from `isEnabled` because the
system can refuse an assertion, and the switch must not claim the Mac is being
kept awake when it is not.

The assertion is named, so it is never a mystery which app is doing this:

```
$ pmset -g assertions
   pid 62530(Ocarina): [0x0001ec3a00058822] PreventUserIdleDisplaySleep named: "Ocarina is open"
```

The kernel drops a process's assertions when it exits, so quitting Ocarina
always gives it back, including on a crash.

## And when there is nothing open

<img src="docs/images/empty.png" alt="The departure board with no tabs open, and the empty task panel">

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
their columns line up.

---

## Running it

```
swift build
swift test
swift run Ocarina
```

`swift run` is fine for development, but it runs unbundled: generic icon, no
Finder integration. For the real thing:

```
Scripts/make-app.sh          # release -> build/Ocarina.app
Scripts/make-app.sh debug    # a separate "Ocarina Test Build.app"
open build/Ocarina.app
```

The debug build is a *separate app*, not the same one rebuilt: its own name,
bundle identifier and executable name. Sharing any of the three meant Launch
Services, the Dock and ⌘-Tab could not tell a test build from the installed one.

One behaviour differs between bundled and not. A binary run from a shell
inherits that shell's directory, so tabs opened where you were; an app launched
from Finder inherits `/`, and every new tab opened at the root of the disk and
was named for it. A session with no directory of its own starts at home.

## Keyboard shortcuts

| | |
|---|---|
| ⌘T | New tab |
| ⌘W | Close tab |
| ⌘K | Quick actions |
| ⇧⌘P | Command palette |
| ⌘V | Paste, through the inspector |

They come from the menu bar in `MainMenu`, not from SwiftUI
`.keyboardShortcut`. AppKit offers a key equivalent to the main menu before the
event reaches the window or the responder chain, so a menu item always gets it;
a hidden SwiftUI button only sees what makes it as far as the view hierarchy,
which a terminal view holding first responder can swallow. Ocarina had no main
menu at all for a while, which is why ⌘W did nothing — and why ⌘Q didn't either.

The Edit menu's cut and copy have no target, so they travel the responder chain
to SwiftTerm, which implements them.

---

# How it is built

## Package layout

`OcarinaTerminalContext` is the naming subsystem. It holds no PTY state and does
no rendering — it takes a `TerminalSessionSnapshot`, asks each provider what the
terminal is doing, and folds the strongest answer into a `TabContext`.

```
Sources/OcarinaTerminalContext/
  ContextSource.swift            priority chain: shell < project < command < llm < manual
  ContextObservation.swift       one provider's reading, with a confidence
  TabContext.swift               per-tab naming state; displayTitle / subtitle
  TabActivity.swift              idle / running / succeeded / failed, for the dot
  TabNamingEngine.swift          the stability rules (dwell, margin, no demotion)
  TabContextCoordinator.swift    actor that runs the provider chain per tab
  TitleFormatter.swift           local text -> 2-4 word title. No model, no network.
  Providers/
    LLMSessionContextProvider    shared agent provider: Claude / Codex / Gemini / OpenCode
    ClaudeTranscriptSource       ~/.claude/projects/<slug>/*.jsonl
    CodexTranscriptSource        ~/.codex/sessions/**/rollout-*.jsonl
    AgentTaskSource              the same transcripts, read as a to-do list
    GenericProcessContextProvider foreground argv -> title
  Session/
    ProcessInspector             tcgetpgrp + sysctl: what owns the pty right now
    OSCParser.swift              streaming ESC ] 0;title BEL reader
    PTYProcess.swift             forkpty, resize, and the environment scrub
    ShellIntegration.swift       the env a spawned shell is given
    TerminalSessionMonitor       one pty -> TerminalSessionSnapshot
    TabNamingService             poll loop; publishes tabs whose title changed
```

Wiring a tab:

```swift
let service = TabNamingService()
await service.attach(TerminalSessionMonitor(ptyDescriptor: primaryFD, shellName: "zsh"))
await service.start()

for await tab in await service.updates() {
    sidebar.rename(tab.tabID, to: tab.displayTitle, subtitle: tab.subtitle)
}
```

The renderer can forward the bytes it already reads to `monitor.ingest(_:)` so
programs that set their own title are picked up; nothing else is read from the
terminal.

```
Sources/OcarinaUI/       SwiftUI layer
  OcarinaWindowView      the window: sidebar, terminal, task panel
  OcarinaModel           open tabs, selection, renames, title updates
  TerminalSession        one tab: pty + SwiftTerm view + naming monitor
  TabSidebarView         tabs as tasks, with the theme and keep-awake footer
  TaskPanelView          what you have asked the agent in this tab
  TaskSummariser         better names for those tasks, via the `claude` binary
  ThemeStore / Theme     bundled + user themes, and the colour model
  ThemePickerView        pick by looking, not by remembering names
  CommandPaletteView     jump by what a terminal is doing (⇧⌘P)
  QuickActionsView       recipe drawer (⌘K); types, never runs
  PasteInspector         reads a paste before the terminal does
  ErrorHelp              hand a failure to an installed agent
  EmptyStateView         no tabs open: the departure board
  DotMatrix              5x7 dot-matrix panel, the board is built from it
  OcarinaIcon            the bundled app mark, prepared for the dock
  TabIcon / StatusDot    a symbol and a state for each tab
  SleepGuard             holds the Mac awake while Ocarina is open
  BundledFonts           registers Geist before the first frame
  MainMenu               the menu bar; where ⌘T / ⌘W / ⌘K / ⇧⌘P actually live
  ToolTip                AppKit tool tips, because .help draws none here
Sources/Ocarina/         executable entry point
```

SwiftTerm is used only as the VT parser and screen grid. Ocarina spawns the pty
itself, via `forkpty`, because `login_tty` is what makes the pty the child's
controlling terminal — and without that `tcgetpgrp` reports nothing and the
naming layer is blind.

## The child environment

A terminal inherits the environment of whatever launched it, and passes it to
every shell it spawns. Launched from inside another tool's session that means
handing each shell the identity of that session — nested tools then believe they
are running as a child of their own parent, which is why Claude Code reported
that transcript saving was off. One of the inherited variables is a messaging
token, which has no business reaching an arbitrary shell.

`PTYProcess` drops those markers before the fork. Only session identity goes:
credentials and configuration a user exports for their own use are theirs and
are left alone.

## Icons and glass

The app icon is `Icons/AppIcon.png`. **Run `Scripts/make-app.sh` to get it.**

A bare SwiftPM executable has no bundle, so macOS has nowhere to read an icon
from and falls back to the generic Unix-executable picture. Setting
`applicationIconImage` is the only lever without a bundle and it does not reach
Finder, the app switcher or Get Info — which is why `swift run Ocarina` still
looks generic. The script assembles a real `Ocarina.app`: an `Info.plist`, an
`AppIcon.icns` generated from the PNG, the SwiftPM resource bundles, and an
ad-hoc signature.

`OcarinaIcon` trims the art to its drawn content, clips the corners to
transparency and lays it on a clear canvas at the ~80% the macOS icon grid
expects. That preparation exists because an earlier icon was an opaque black
plate with the tile drawn inside it: used as-is it made the dock icon read as a
small tile in a dark square. The invariant worth keeping is that preparation
adds margin around the art and never eats into it. A 512px plate that came back
as a 424px icon is the regression that invariant was written against; the test
pins the invariant — prepared is wider than the art it was given — not the
number.

Tabs do **not** use the app icon. Every tab carrying the same picture said
nothing; `TabIcon` gives each one a symbol for its foreground process, so Claude
Code reads differently from a shell at a prompt across a sidebar of twenty.

Glass needs something behind it to blur. An `NSVisualEffectView` sits behind the
hosting view and the window is non-opaque, so the materials in the chrome have
the desktop to work with; without it they resolve to flat grey. The terminal
view's own background is cleared and a themed bed sits behind it — the glass
reads through, and the text stays legible.

## Tool tips

Three mechanisms were tried. SwiftUI's `.help` produces nothing in a plain
`NSHostingController` — walk the view tree and there is no tool tip on it at
all. AppKit's `NSView.toolTip` *is* installed, on a view that hit-tests at the
right frame, and still never appears: the tool tip manager needs mouse-moved
events to reach the view under the cursor, and inside a hosting view they do not
arrive. A SwiftUI bubble drawn by the control itself is then clipped away by the
scroll view the tabs sit in.

So a control only reports hover, through a tracking area on the small `NSView`
that already takes its click, and the sidebar draws the bubble in its own
coordinate space — outside the scroller, and above the terminal by `zIndex`.

Tab titles are capped at 24 characters for display, ellipsis included, so one
long name cannot push the sidebar around. The tab keeps its full name for
renaming, for the hover subtitle and for the command palette.
