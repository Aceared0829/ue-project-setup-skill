---
name: ue-project-setup
description: Set up an Unreal Engine 5 project on Linux for VS Code and AI agents — declare platform support, build the editor from the CLI, generate compile_commands.json and configure clangd (including UE umbrella-header false positives), wire the built-in UE MCP server so an assistant can drive the running editor, and fix PIE mouse/keyboard capture plus HUD Slate pass-through. Use when setting up or repairing a UE project on Linux, when VS Code shows phantom errors or no IntelliSense, when the editor is running but the assistant cannot reach it, or when PIE input is broken. Not for gameplay feature work.
---

# Unreal Engine project setup (Linux + VS Code + AI agent)

End state: `bash` can build the editor, VS Code resolves C++ with no phantom
squiggles, the running editor is reachable over MCP, and PIE owns mouse and
keyboard even with a full-screen HUD.

Do the steps in order. Each one is verifiable on its own, and every later step
depends on the previous one succeeding — a broken build makes clangd and MCP
look broken too.

## 1. Pin the engine once

Everything below needs one absolute engine path. Export it for the session and
keep the per-machine value out of version control:

```bash
export UE_ROOT=/path/to/UE_5.8
test -f "$UE_ROOT/Engine/Build/Build.version" && echo ok
```

For an installed (launcher) build, `Engine/Binaries/Linux/UnrealEditor` already
exists. For a source build it does not until you compile it once — see step 3.

## 2. Declare platform support

Linux must be declared, not assumed. Modules whose binary ships Windows-only
must be excluded instead of failing at link time:

```jsonc
// <Project>.uproject -> Modules
{ "Name": "SomeWinOnlyPlugin", "Enabled": true, "PlatformAllowList": ["Win64"] }
```

```json
// <Plugin>.uplugin
"SupportedTargetPlatforms": ["Win64", "Linux"]
```

Details and the failure modes: [references/plugins-and-vcs.md](references/plugins-and-vcs.md).

## 3. Build from the CLI before touching VS Code

```bash
"$UE_ROOT/Engine/Build/BatchFiles/Linux/Build.sh" \
  <Project>Editor Linux Development \
  -Project="$PWD/<Project>.uproject" -WaitMutex -NoHotReloadFromIDE -Progress
```

Target name is `<Project>Editor` for the editor, `<Project>` for the game.
`-WaitMutex` keeps concurrent invocations from corrupting the build;
`-NoHotReloadFromIDE` avoids waiting on a live editor. If this fails, stop —
fixing the toolchain is cheaper than debugging IntelliSense against a broken
build.

## 4. Launch the editor with a usable display

```bash
DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/$(id -u) \
  "$UE_ROOT/Engine/Binaries/Linux/UnrealEditor" "$PWD/<Project>.uproject" -log
```

`XDG_RUNTIME_DIR` unset is the usual reason a window appears but input dies.
Add `-log` so the log file exists to grep later. When launching from an agent or
SSH session, these two variables are the difference between "editor runs" and
"editor starts but PIE never gets focus".

## 5. Wire VS Code

Ready-to-copy files: [examples/](examples/) (`.clangd`, `.vscode/settings.json`,
`.vscode/tasks.json`, `scripts/ue.sh`). Rationale and the full walkthrough:
[references/vscode-linux.md](references/vscode-linux.md).

Minimum:

- C++ language server: clangd extension, with `C_Cpp.intelliSenseEngine` off so
  you do not get two sets of contradictory diagnostics.
- `clangd.arguments`: `--background-index`, `--header-insertion=never`, and
  `--query-driver=` the engine's Linux `clang++`. **Do not** add
  `--compile-commands-dir` — see step 6 for why it breaks multi-tree repos.
- Tasks for build / generate project files / generate compile database / watch
  the database / launch editor, so the terminal recipe lives in the workspace
  instead of your history.
- Exclude `Binaries/`, `Intermediate/`, `Saved/`, `DerivedDataCache/` from
  search and the file watcher.

## 6. clangd needs a compile database that UBT does not make by default

`compile_commands.json` is **not** produced by `GenerateProjectFiles` or by a
normal build — only by the explicit tool mode:

```bash
"$UE_ROOT/Engine/Build/BatchFiles/Linux/Build.sh" \
  -Mode=GenerateClangDatabase \
  "-Project=$PWD/<Project>.uproject" \
  "-Target=<Project>Editor Linux Development" \
  "-OutputDir=$PWD/.vscode"
```

Regenerate whenever source files are added, renamed or deleted; content edits do
not need it. Detect staleness by comparing a **sorted file list**, never mtimes
(sync tools and builds both touch timestamps). `.clangd` should point at the
database and strip MSVC-only flags. UE's umbrella headers also need
`Diagnostics.UnusedIncludes: None` — otherwise clangd offers a "fix" that deletes
`CoreMinimal.h` and breaks the build. All of this, with verification steps, is in
[references/vscode-linux.md](references/vscode-linux.md).

Two traps that cost the most time:

- `--compile-commands-dir` is single-valued. Pass it twice (host project plus a
  plugin mirror) and the **last** one wins; if that directory has no database,
  clangd silently falls back to flags with no `-I` paths and the whole project
  reports `'Foo.h' file not found`. Select the database from `.clangd`
  (`CompileFlags.CompilationDatabase`) per source tree instead, and keep
  `clangd.arguments` free of that flag.
- clangd reads `clangd.arguments` once at spawn. Saving `settings.json` does not
  restart it, so a fixed configuration keeps producing old diagnostics until
  `clangd: Restart language server` (or a window reload). Confirm with
  `ps -eo args | grep '[c]langd'`.

Regenerating is only ~2 s, so make it automatic rather than a chore: a
background task that polls the file list every 5 s, rebuilds only on
add/rename/remove, and runs the tool mode with `-WaitMutex` so it can queue
behind a build. `examples/scripts/ue.sh WatchClangDatabase` plus the
`UE: Watch clang database` task do this; `runOn: folderOpen` starts it with the
workspace.

## 7. Let the AI agent drive the editor

UE 5.6+ ships the server at
`Engine/Plugins/Experimental/ModelContextProtocol`:

```jsonc
// <Project>.uproject
{ "Name": "ModelContextProtocol", "Enabled": true }
```

```ini
; Config/DefaultEditorPerProjectUserSettings.ini
[/Script/ModelContextProtocolEngine.ModelContextProtocolSettings]
bAutoStartServer=True
ServerPortNumber=8000
ServerUrlPath=/mcp
```

Clients disagree on the wrapper key, so keep both files:

| Client | File | Shape |
| --- | --- | --- |
| VS Code | `.vscode/mcp.json` | `{ "servers": { ... } }` |
| Codex / Claude | `.mcp.json` | `{ "mcpServers": { ... } }` |

```json
{ "type": "http", "url": "http://127.0.0.1:8000/mcp" }
```

Verify before blaming the client:

```bash
curl -sS -X POST http://127.0.0.1:8000/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}}'
```

A JSON-RPC result means the server is up. Connection refused means: editor not
running, plugin disabled or not compiled for Linux, port taken, or — the common
one — `Saved/Config/LinuxEditor/EditorPerProjectUserSettings.ini` overriding the
`Default...` file, since per-user settings already materialized there win.

## 8. Make PIE own mouse and keyboard

```ini
[/Script/UnrealEd.LevelEditorPlaySettings]
GameGetsMouseControl=True
```

That is necessary but not sufficient in embedded PIE. Controller-side capture,
the retry ladder, and the HUD `HitTestInvisible` rule are in
[references/pie-input-and-hud.md](references/pie-input-and-hud.md). Verify with
logged state (`HasMouseCapture`, `HasKeyboardFocus`, non-zero Move/Look), not by
feel.

## 9. Third-party plugins with native dependencies

A plugin that only builds on Windows, or vendors a CMake/Rust project, needs a
Linux build path before the editor will load it. Worked pattern (CMake branches,
artifact naming, `$ORIGIN` RPATH, one `PLATFORM_WINDOWS`-style macro header):
[references/plugins-and-vcs.md](references/plugins-and-vcs.md).

## 10. Keep the repo clean

Ignore `Binaries/`, `Intermediate/`, `Saved/`, `DerivedDataCache/`, generated
project files, and anything holding an absolute engine path. `.vscode/` is
ignored by UE's default `.gitignore` — if you want to share tasks, negate just
that file (`!/.vscode/tasks.json`) and keep the machine-specific bits out.
Rules and the `.props`-override case: [references/plugins-and-vcs.md](references/plugins-and-vcs.md).

## Don't

- Don't guard a platform by throwing (`BuildException("... supports Win64")`) —
  branch on `Target.Platform` and pick the native library per platform.
- Don't delete an include clangd calls unused in UE code; check whether the
  header is a PCH/umbrella header first.
- Don't pass `--compile-commands-dir` twice, and don't pass it at all when each
  source tree ships a `.clangd` — the last value wins and the other tree's
  includes stop resolving.
- Don't assume editing `settings.json` restarted clangd; the server keeps its
  original argv until it is restarted.
- Don't commit absolute engine paths (`D:\UE_5.8\Engine`,
  `/path/to/UE_5.8/Engine`) into shared files.
- Don't reach for private engine APIs when public ones reproduce the behavior;
  they break on minor upgrades.
