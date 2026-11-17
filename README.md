# Unreal Engine setup for Linux + VS Code (agent skill)

English | [简体中文](README.zh-CN.md)

A skill that teaches an AI coding agent how to bring up — or repair — an Unreal
Engine 5 project on Linux: declare platform support, build from the CLI, give
VS Code a working clangd setup, wire the editor to the agent over MCP, and make
PIE own mouse and keyboard with a custom HUD on screen.

Nothing here is specific to one project. The lessons were distilled from real
UE 5.8 work, but every path, module and task is a placeholder you fill in once
per project.

## What it covers

| Topic | Reference |
| --- | --- |
| Engine pinning, CLI builds, editor launch with a usable display | `SKILL.md` steps 1–4 |
| VS Code: extensions, `settings.json`, `tasks.json`, `scripts/ue.sh` | [references/vscode-linux.md](references/vscode-linux.md) |
| clangd: compile database, staleness detection, `.clangd`, false positives | [references/vscode-linux.md](references/vscode-linux.md) |
| UE MCP server + client config + handshake verification | `SKILL.md` step 7 |
| PIE mouse/keyboard capture, HUD Slate pass-through | [references/pie-input-and-hud.md](references/pie-input-and-hud.md) |
| `.uproject` platform declarations, porting Windows-only native plugins | [references/plugins-and-vcs.md](references/plugins-and-vcs.md) |
| Ignore rules, per-machine files, optional `.props` overrides | [references/plugins-and-vcs.md](references/plugins-and-vcs.md) |

## Copy-paste files

[`examples/`](examples/) holds a working `.clangd`, `.vscode/settings.json`,
`.vscode/tasks.json` and `scripts/ue.sh`. Copy them in, set `PROJECT_NAME` and the
engine path, then run `bash scripts/ue.sh Check`.

## Install

Clone straight into your skills directory — the repository root *is* the skill
directory, so nothing needs moving:

```bash
# Codex
git clone https://github.com/Aceared0829/ue-project-setup-skill.git \
  ~/.codex/skills/ue-project-setup

# Claude Code
git clone https://github.com/Aceared0829/ue-project-setup-skill.git \
  ~/.claude/skills/ue-project-setup
```

The agent loads `SKILL.md` and pulls in a reference only when the step needs it,
so the long material costs no context until it is relevant.

## Layout

```
SKILL.md                        # ordered checklist: build -> VS Code -> agent -> input
references/
  vscode-linux.md               # clangd, compile database, tasks.json, ue.sh
  pie-input-and-hud.md          # symptom -> cause -> fix, Slate capture code
  plugins-and-vcs.md            # platforms, native plugin porting, ignore rules
examples/                       # working .clangd, .vscode/*, scripts/ue.sh
```

## Notes

- Written against UE 5.8; the material applies to 5.3+ unless a step says
  otherwise. MCP needs 5.6+ (`Engine/Plugins/Experimental/ModelContextProtocol`).
- It is opinionated on purpose: it tells the agent what *not* to do (delete an
  include clangd flags, commit absolute engine paths, guard platforms by
  throwing) because each of those costs a debugging session.
- Verification is part of the instructions: a build command, a curl handshake, a
  logged `HasMouseCapture`. "It looks fine" is not a step.

## License

MIT — see [LICENSE](LICENSE).
