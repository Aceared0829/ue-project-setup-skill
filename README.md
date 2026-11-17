# UE Project Setup (agent skill)

English | [简体中文](README.zh-CN.md)

An agent skill that gets an Unreal Engine project to a state where an AI coding
agent can actually work in it: the running editor is reachable over MCP, PIE
owns the mouse and keyboard, a full-screen HUD stops eating Slate input, and
clangd/IDE diagnostics are not drowned in false positives.

Written from a real UE 5.8 project on Linux (Windows notes included). Every step
was verified against the engine rather than guessed — including the parts that
look like engine bugs but aren't.

## What it covers

| Area | Highlights |
| --- | --- |
| UE MCP server | Enabling `ModelContextProtocol`, auto-start on port 8000, client config for VS Code / Codex / Claude, curl handshake to verify |
| PIE input | `FInputModeGameOnly`, Slate mouse capture reply, native window activation for embedded PIE, capture retry ladder, `UseHighPrecisionMouseMovement` |
| HUD pass-through | `HitTestInvisible` on the widget *and* on `TakeWidget()`, why `pointer-events: none` in RmlUi `.rcss` is not enough |
| clangd | `GenerateClangDatabase` mode, stale-database detection by file list (not mtime), suppressing `clangd/unused-includes` for UE umbrella headers |
| Build / hygiene | RmlUi/Slate bridge on Linux, `.uproject` `PlatformAllowList`, what belongs in `.gitignore`, why optional `.props` imports are local overrides |

## Install

Clone straight into your skills directory — the repository root *is* the skill
directory:

```bash
# Codex
git clone https://github.com/Aceared0829/ue-project-setup-skill.git \
  ~/.codex/skills/ue-project-setup

# Claude Code
git clone https://github.com/Aceared0829/ue-project-setup-skill.git \
  ~/.claude/skills/ue-project-setup
```

The agent loads `SKILL.md` and pulls in `references/*.md` on demand, so the
detailed material costs nothing until it is relevant.

## Layout

```
SKILL.md                 # ordered checklist, the entry point
references/
  pie-input-and-hud.md   # symptom -> cause -> fix table + Slate capture code
  linux-toolchain.md     # RmlUi bridge, clangd, .uproject platforms, VCS hygiene
```

## Notes

- Defaults target UE 5.8; most of it applies to 5.3+ unchanged. Anything
  version-specific says so explicitly.
- The skill is opinionated on purpose: it tells the agent what *not* to do
  (delete `CoreMinimal.h`, commit absolute engine paths, guard platforms by
  throwing) because those failures cost real debugging time.

## License

MIT — see [LICENSE](LICENSE).
