#!/usr/bin/env bash
# Build / database / launch helper for an Unreal Engine project on Linux.
# Copy to <repo>/scripts/ue.sh and set PROJECT_NAME below.
set -euo pipefail

# --- edit these three lines -------------------------------------------------
PROJECT_NAME="<Project>"
PLATFORM="Linux"
CONFIGURATION="Development"
# ---------------------------------------------------------------------------

TARGET="${PROJECT_NAME}Editor"

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/$PROJECT_NAME.uproject"

# Engine path: $UE_ROOT, else the gitignored .vscode/ue-root file.
UE_ROOT="${UE_ROOT:-$(cat "$REPO_ROOT/.vscode/ue-root" 2>/dev/null || true)}"
if [[ -z "$UE_ROOT" || ! -f "$UE_ROOT/Engine/Build/Build.version" ]]; then
    echo "error: set UE_ROOT, or write the absolute engine path to .vscode/ue-root" >&2
    exit 1
fi

BUILD_SH="$UE_ROOT/Engine/Build/BatchFiles/Linux/Build.sh"
GENERATE_PROJECTS_SH="$UE_ROOT/Engine/Build/BatchFiles/Linux/GenerateProjectFiles.sh"
EDITOR="$UE_ROOT/Engine/Binaries/Linux/UnrealEditor"

CLANG_DB="$REPO_ROOT/.vscode/compile_commands.json"
CLANG_DB_SNAPSHOT="$REPO_ROOT/.vscode/.clangdb-source-list"

# UBT writes compile_commands.json only in -Mode=GenerateClangDatabase, and
# stale entries make clangd report phantom errors across the project.
#
# Compare the FILE LIST rather than mtimes: sync tools and builds both touch
# timestamps, so an mtime check would rebuild on every build, while a pure
# content edit never needs a new database (the flags are unchanged). Build.cs
# is in the list because module dependencies change the flags too.
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
    echo "source list changed; regenerating .vscode/compile_commands.json" >&2
    "$BUILD_SH" -Mode=GenerateClangDatabase \
        "-Project=$PROJECT" "-Target=$TARGET $PLATFORM $CONFIGURATION" \
        "-OutputDir=$REPO_ROOT/.vscode" -WaitMutex
    printf '%s\n' "$current" > "$CLANG_DB_SNAPSHOT"
}

case "${1:-}" in
    Check)
        echo "repo:    $REPO_ROOT"
        echo "engine:  $UE_ROOT"
        echo "project: $PROJECT"
        [[ -f "$PROJECT" ]] || { echo "error: project file missing" >&2; exit 1; }
        echo "target:  $TARGET $PLATFORM $CONFIGURATION"
        echo
        if [[ -x "$EDITOR" ]]; then
            echo "editor:  present"
        else
            echo "editor:  not built yet (run BuildEditor)"
        fi
        assoc="$(grep -o '"EngineAssociation"[[:space:]]*:[[:space:]]*"[^"]*"' "$PROJECT" | head -1 || true)"
        major="$(grep -o '"MajorVersion"[[:space:]]*:[[:space:]]*[0-9]*' "$UE_ROOT/Engine/Build/Build.version" | head -1 || true)"
        minor="$(grep -o '"MinorVersion"[[:space:]]*:[[:space:]]*[0-9]*' "$UE_ROOT/Engine/Build/Build.version" | head -1 || true)"
        echo "uproject: ${assoc:-EngineAssociation unknown}"
        echo "tree:     ${major:-MajorVersion unknown} ${minor:-MinorVersion unknown}"
        query_driver="$(find "$UE_ROOT/Engine/Extras/ThirdPartyNotUE/SDKs/HostLinux" -type f -path '*/bin/clang++' -print -quit 2>/dev/null || true)"
        if [[ -n "$query_driver" ]]; then
            echo "query-driver (User settings if settings.json is shared):"
            echo "  --query-driver=$query_driver"
        else
            echo "query-driver: HostLinux clang++ not found under this engine"
        fi
        if grep -n 'compile-commands-dir' "$REPO_ROOT/.vscode/settings.json" >/dev/null 2>&1; then
            echo "warn: .vscode/settings.json sets --compile-commands-dir; remove it and select the database from .clangd" >&2
        fi
        ;;
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
        # Editor-time auto-refresh: poll the file list (a single find) every few
        # seconds; regenerate only when files were added, renamed or removed.
        # One UBT run costs ~2s for a small plugin, so this stays cheap, and
        # content saves never touch the database.
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
        DISPLAY="${DISPLAY:-:0}" \
        XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
            "$EDITOR" "$PROJECT" -log
        ;;
    *)
        echo "usage: $0 {Check|BuildEditor|GenerateClangDatabase|WatchClangDatabase|GenerateProjectFiles|LaunchEditor}" >&2
        exit 2
        ;;
esac
