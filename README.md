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
```

```
swift build
swift test
```
