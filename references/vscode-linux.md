# VS Code on Linux

Target setup: clangd is the only C++ language server, tasks build through UBT's
own `Build.sh`, and the compile database is kept fresh automatically.

Working copies of every file below live in [`../examples/`](../examples/) —
copy them in rather than retyping.

## Extensions

| Purpose | Extension |
| --- | --- |
| C++ language server | `llvm-vs-code-extensions.vscode-clangd` |
| Support files (`.uproject` JSON, `.rml`/`.rcss` if used) | any JSON/CSS grammar; set associations instead of installing more |
| Tasks / terminal | built in, no extension needed |

Turn the Microsoft C++ extension's IntelliSense **off** if it is installed.
Two language servers analyzing the same UE file produce two contradictory sets
of diagnostics, and the MS one cannot read UBT's flags.

```jsonc
"C_Cpp.intelliSenseEngine": "disabled",
"C_Cpp.errorSquiggles": "disabled"
```

## settings.json

```jsonc
{
  // Do NOT pass --compile-commands-dir. See "One database per source tree".
  "clangd.arguments": [
    "--background-index",
    "--header-insertion=never",
    "--completion-style=detailed",
    "--inlay-hints",
    // UE builds with its own clang from Engine/Extras/ThirdPartyNotUE/...;
    // without --query-driver clangd guesses the wrong builtin target/sysroot.
    "--query-driver=/path/to/UE_5.8/Engine/Extras/ThirdPartyNotUE/SDKs/HostLinux/Linux_x64/*/x86_64-unknown-linux-gnu/bin/clang++"
  ],
  "clangd.onConfigChanged": "restart",

  "[cpp]": { "editor.insertSpaces": false, "editor.tabSize": 4 },

  "files.associations": { "*.inl": "cpp" },

  // These trees dwarf Source/ and change constantly during builds.
  "search.exclude": {
    "**/Binaries": true,
    "**/Intermediate": true,
    "**/Saved": true,
    "**/DerivedDataCache": true,
    "**/Plugins/**/ThirdParty/**": true,
    "**/node_modules": true
  },
  "files.watcherExclude": {
    "**/Binaries/**": true,
    "**/Intermediate/**": true,
    "**/Saved/**": true,
    "**/DerivedDataCache/**": true,
    "**/node_modules/**": true
  }
}
```

`--query-driver` accepts a glob. If the path is wrong clangd just skips it, so a
stale value degrades quietly — re-check it after upgrading the engine.

### One database per source tree

`--compile-commands-dir` takes **one** value. LLVM's command-line parser keeps
the last occurrence, so a settings list like

```jsonc
"clangd.arguments": [
  "--compile-commands-dir=${workspaceFolder}/ProjectA/.vscode",
  "--compile-commands-dir=${workspaceFolder}/plugins-mirror"
]
```

points clangd at the mirror only. If that directory has no
`compile_commands.json`, clangd falls back to a generic command without any
`-I` flags — and every file in the *working* project reports
`'Game/Foo.h' file not found`, on headers that exist and compile fine.
Nothing in the log says the first directory was dropped.

Select the database from config instead, one `.clangd` per tree:

```yaml
# ProjectA/.clangd            -> ProjectA/.vscode/compile_commands.json
CompileFlags:
  CompilationDatabase: .vscode

# plugins-mirror/.clangd      -> plugins-mirror/compile_commands.json
CompileFlags:
  CompilationDatabase: .
```

clangd resolves `.clangd` per source file, walking up from the file, so each
tree uses its own database with no global flag. Verify the choice per file:

```bash
clangd --check=ProjectA/Source/Game/Foo.cpp 2>&1 \
  | grep -E 'Loaded compilation database|file not found'
```

### Restart clangd after changing `clangd.arguments`

The server reads its arguments once, when it is spawned. Saving
`settings.json` — in the editor or from a script — does **not** restart it,
and `clangd.onConfigChanged` only covers changed config files, not VS Code
settings. Until the server is restarted, the editor keeps diagging with the old
argv and the fix appears not to work.

Check what is actually running, then restart:

```bash
ps -eo args | grep '[c]langd'
# clangd --compile-commands-dir=... --compile-commands-dir=...   <- stale
```

Run `clangd: Restart language server` from the command palette, or reload the
window. Re-run the `ps` line and confirm the flags are the new ones.

## tasks.json

Uses the helper below, so task definitions stay one line each.

```jsonc
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "UE: Build editor (Linux Development)",
      "type": "process",
      "command": "bash",
      "args": ["${workspaceFolder}/scripts/ue.sh", "BuildEditor"],
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": ["$gcc"]
    },
    {
      "label": "UE: Regenerate clang database",
      "type": "process",
      "command": "bash",
      "args": ["${workspaceFolder}/scripts/ue.sh", "GenerateClangDatabase"],
      "problemMatcher": []
    },
    {
      "label": "UE: Watch clang database",
      "type": "process",
      "command": "bash",
      "args": ["${workspaceFolder}/scripts/ue.sh", "WatchClangDatabase"],
      "isBackground": true,
      "runOptions": { "runOn": "folderOpen" },
      "problemMatcher": [],
      "presentation": { "reveal": "silent", "panel": "dedicated" }
    },
    {
      "label": "UE: Launch editor",
      "type": "process",
      "command": "bash",
      "args": ["${workspaceFolder}/scripts/ue.sh", "LaunchEditor"],
      "problemMatcher": []
    }
  ]
}
```

## scripts/ue.sh

Portable version of the helper: engine path from `$UE_ROOT`, else from a
gitignored `.vscode/ue-root` file, else a clear error. Nothing here is
project-specific except the three variables at the top.

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="<Project>"
TARGET="${PROJECT_NAME}Editor"
PLATFORM="Linux"
CONFIGURATION="Development"

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UE_ROOT="${UE_ROOT:-$(cat "$REPO_ROOT/.vscode/ue-root" 2>/dev/null || true)}"
if [[ -z "${UE_ROOT}" || ! -f "$UE_ROOT/Engine/Build/Build.version" ]]; then
    echo "Set UE_ROOT or write the engine path to .vscode/ue-root" >&2
    exit 1
fi

PROJECT="$REPO_ROOT/$PROJECT_NAME.uproject"
BUILD_SH="$UE_ROOT/Engine/Build/BatchFiles/Linux/Build.sh"
GENERATE_PROJECTS_SH="$UE_ROOT/Engine/Build/BatchFiles/Linux/GenerateProjectFiles.sh"
EDITOR="$UE_ROOT/Engine/Binaries/Linux/UnrealEditor"

CLANG_DB="$REPO_ROOT/.vscode/compile_commands.json"
CLANG_DB_SNAPSHOT="$REPO_ROOT/.vscode/.clangdb-source-list"

# UBT writes compile_commands.json only in -Mode=GenerateClangDatabase.
# Stale entries point at files that moved, and clangd then reports phantom
# errors across the whole project. Compare the FILE LIST, not mtimes: sync
# tools and builds both touch timestamps, so mtime checks rebuild every build.
# Build.cs is included because module dependencies change the flags too.
source_file_list() {
    local roots=("$REPO_ROOT/Source")
    if [[ -d "$REPO_ROOT/Plugins" ]]; then
        roots+=("$REPO_ROOT/Plugins")
    fi
    find "${roots[@]}" \
        -type d -name Intermediate -prune -o \
        -type f \( -name '*.h' -o -name '*.cpp' -o -name '*.cs' \) -print \
        | sort
}

refresh_clang_database_if_stale() {
    local current
    current="$(source_file_list)"
    if [[ -f "$CLANG_DB" && -f "$CLANG_DB_SNAPSHOT" ]] \
        && diff -q <(printf '%s\n' "$current") "$CLANG_DB_SNAPSHOT" >/dev/null 2>&1; then
        return
    fi
    echo "Source list changed; regenerating compile_commands.json..." >&2
    "$BUILD_SH" -Mode=GenerateClangDatabase \
        "-Project=$PROJECT" "-Target=$TARGET $PLATFORM $CONFIGURATION" \
        "-OutputDir=$REPO_ROOT/.vscode" -WaitMutex
    printf '%s\n' "$current" > "$CLANG_DB_SNAPSHOT"
}

case "${1:-}" in
    BuildEditor)
        refresh_clang_database_if_stale
        "$BUILD_SH" "$TARGET" "$PLATFORM" "$CONFIGURATION" \
            "-Project=$PROJECT" -WaitMutex -NoHotReloadFromIDE -Progress
        ;;
    GenerateClangDatabase)
        "$BUILD_SH" -Mode=GenerateClangDatabase \
            "-Project=$PROJECT" "-Target=$TARGET $PLATFORM $CONFIGURATION" \
            "-OutputDir=$REPO_ROOT/.vscode" -WaitMutex
        source_file_list > "$CLANG_DB_SNAPSHOT"
        ;;
    WatchClangDatabase)
        refresh_clang_database_if_stale || true
        echo "watching $REPO_ROOT for source files (Ctrl+C to stop)..." >&2
        while true; do
            sleep 5
            refresh_clang_database_if_stale \
                || echo "warn: database refresh failed; retrying" >&2
        done
        ;;
    GenerateProjectFiles)
        "$GENERATE_PROJECTS_SH" "-project=$PROJECT" -game -engine -progress
        ;;
    LaunchEditor)
        DISPLAY="${DISPLAY:-:0}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
            "$EDITOR" "$PROJECT" -log
        ;;
    *)
        echo "usage: $0 {BuildEditor|GenerateClangDatabase|WatchClangDatabase|GenerateProjectFiles|LaunchEditor}" >&2
        exit 2
        ;;
esac
```

### Keeping the database fresh while you edit

Regenerating is cheap — one UBT tool-mode run measured **1.7–2.2 s** on a
project with a dozen modules — so `WatchClangDatabase` is a background task that
polls the sorted file list every 5 s and rebuilds only when something was added,
renamed or removed. Content saves never trigger it: the flags do not change, and
rewriting the JSON makes clangd reload and re-index for nothing.

`-WaitMutex` on the tool-mode run lets it queue behind a concurrent build
instead of failing, which matters because the watcher can fire while
`BuildEditor` is running.

`runOn: folderOpen` starts it with the workspace; VS Code asks once whether to
allow automatic tasks in the folder. Keep at least the manual
`GenerateClangDatabase` task: it is what you run when the database is missing
entirely, and it is the fallback when the engine path is not configured.

`BuildEditor` also refreshes first, so a build-only workflow does not need the
watcher; without a build, a newly added file still resolves if clangd can
interpolate flags from a neighbouring translation unit, but a new module or a
changed `Build.cs` needs the real regenerate.

## .clangd

```yaml
CompileFlags:
  CompilationDatabase: .vscode
  # clangd only searches cwd and its parents for the database.

  # UBT emits flags for the engine's clang/msvc; the local clangd rejects some.
  Remove: [-resource-dir, -Werror, -WX, /WX, -mwaitpkg, -fms-hotpatch]
  # -ferror-limit=0 keeps UE_LOG token-paste errors from aborting the file.
  Add: [-Wno-unknown-warning-option, -Wno-unused-command-line-argument, -D_MSVC_TRADITIONAL=0, -ferror-limit=0]

Diagnostics:
  Suppress:
    - invalid-token-paste
  # IncludeCleaner cannot model UE's shared PCH or transitive *.generated.h
  # dependencies: it calls CoreMinimal.h "not used directly" and the offered
  # fix breaks the build.
  UnusedIncludes: None
```

Leave `MissingIncludes` at its default; it is a separate key and often useful.

`invalid-token-paste` is a different failure from IncludeCleaner. `UE_LOG`
pastes tokens in a way the engine clang accepts and a newer clangd rejects.
Each call site is one error; clangd's default cap is 20, after which it stops
parsing and every later type looks undefined. Suppress the diagnostic and lift
the cap. Do not "fix" the macros.

If the git root is not the `.uproject`, this file goes next to the `.uproject`.
A plugin tree that is not mounted in any `.uproject` has nothing for
`GenerateClangDatabase` to index. Mount it in a host, build that host, and
point the plugin tree's `.clangd` at the host database. A hand-written compile
database drifts the moment `Build.cs` or a generated header changes.

## Verifying diagnostics without the editor

`clangd --check=<file>` runs syntax and tweaks but **not** IncludeCleaner, so it
looks clean while the editor still shows the warning. To see exactly what VS Code
gets, speak LSP: send `initialize`, `initialized`, `textDocument/didOpen` over
stdio and read `textDocument/publishDiagnostics` for that URI. `--check` failing
with `ExtractFunction ==> FAIL: Cannot extract break/continue` is a code-action
probe failing, not a compile error — ignore it.

Other flags worth knowing:

```bash
clangd --check=Source/.../File.cpp --compile-commands-dir=.vscode   # syntax only
clangd --check=... --log=verbose                                    # why a header is unresolved
```

## Symptom → cause

| Symptom | Cause |
| --- | --- |
| Whole project red, `file not found` on your own headers | stale `compile_commands.json` after files moved |
| Whole project red right after adding a second source tree | two `--compile-commands-dir` values; the last one replaced the real database |
| Settings fixed, diagnostics unchanged | clangd still running with the old argv — restart the server |
| Works in terminal, red in VS Code | clangd never picked up `.clangd` / wrong `--compile-commands-dir` |
| Phantom errors on engine types | `--query-driver` missing → wrong builtin target |
| Every UE header "not used directly" | IncludeCleaner; `UnusedIncludes: None` |
| `invalid-token-paste` on `UE_LOG`, then a cascade of bogus errors | clangd hit its 20-error cap; suppress `invalid-token-paste` and add `-ferror-limit=0` |
| Handshake works, `list_toolsets` is empty | `ToolsetRegistry` is not the catalog; enable `AllToolsets` or the specific toolset plugin |
| MCP ini looks right, server never starts | 5.8 and 5.9 use different `/Script/` sections; the other engine's section is ignored. Also check `Saved/Config/LinuxEditor/EditorPerProjectUserSettings.ini` |
| Duplicate, contradictory squiggles | MS C++ IntelliSense still enabled |
| Autocomplete slow / machine pegged | no `--background-index`, or `Binaries/`+`Intermediate/` indexed via search |
