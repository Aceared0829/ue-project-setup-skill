# Copy-paste workspace files

Working versions of everything the skill describes. Copy, edit the three
placeholders, run `Check`.

| File | Goes to | Purpose |
| --- | --- | --- |
| `.clangd` | repo root, next to `<Project>.uproject` | point clangd at the UBT database, strip MSVC flags, silence the UE include false positive |
| `.vscode/settings.json` | `.vscode/settings.json` | clangd as the only C++ server, `--query-driver`, search/watcher excludes |
| `.vscode/tasks.json` | `.vscode/tasks.json` | build / database / project files / launch / check, all via `ue.sh` |
| `scripts/ue.sh` | `scripts/ue.sh` (chmod +x) | the actual commands, plus compile-database staleness detection |

## Edit three things

1. `scripts/ue.sh`: `PROJECT_NAME="<Project>"` — must match your `.uproject`
   filename without the extension. `PLATFORM` / `CONFIGURATION` only if you need
   something other than `Linux` / `Development`.
2. `.vscode/settings.json`: the `--query-driver` path — point it at your
   engine's Linux `clang++`:
   `$UE_ROOT/Engine/Extras/ThirdPartyNotUE/SDKs/HostLinux/Linux_x64/*/x86_64-unknown-linux-gnu/bin/clang++`
3. Engine location, one of:
   - `export UE_ROOT=/path/to/UE_5.8`, or
   - `echo /path/to/UE_5.8 > .vscode/ue-root` (keep that file ignored).

Nothing else is project-specific.

## Verify

```bash
bash scripts/ue.sh Check            # resolves engine, finds the project
bash scripts/ue.sh BuildEditor      # first real build; also refreshes the db if sources moved
bash scripts/ue.sh GenerateClangDatabase
```

`Check` prints the resolved repo, engine, project and target, and whether the
editor binary exists yet. If it reports the engine as missing, fix `UE_ROOT` /
`.vscode/ue-root` before anything else.

## Keeping these in version control

UE's default `.gitignore` ignores `.vscode/`. `settings.json` holds an absolute
engine path, so keep it local; share the rest:

```gitignore
/.vscode/*
!/.vscode/tasks.json
```

`scripts/ue.sh` and `.clangd` carry no machine-specific values — commit them.

## Windows

`ue.sh`, `tasks.json` and `--query-driver` are Linux-only. The parts that do
carry over: `.clangd` (same file, same reason), the plugin/MCP/input guidance in
`SKILL.md`, and the ignore rules. Windows builds go through
`Engine/Build/BatchFiles/Build.bat` with `Win64`.
