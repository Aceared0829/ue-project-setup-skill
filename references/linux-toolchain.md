# Linux toolchain and repo hygiene

## RmlUi / Slate native bridge

The plugin ships a Windows-only CMake project. For Linux:

- CMake: allow `UNIX AND NOT APPLE` with 64-bit pointers; set
  `CMAKE_POSITION_INDEPENDENT_CODE ON` (static vendor libs go into a `.so`).
- Rust grid lib is `librmlui_grid.a` on Linux, `rmlui_grid.lib` on Windows.
- Link `pthread dl m` instead of `ws2_32 userenv bcrypt ntdll`.
- Drop the DX11 backend sources on Linux; the Slate command renderer is the only
  output path (`bUseSlateRenderer = true`, and clamp it in `SetUseSlateRenderer`).
- Shared objects are `LIBRARY` artifacts: set `LIBRARY_OUTPUT_DIRECTORY`, the
  per-config `RUNTIME_OUTPUT_DIRECTORY_<CONFIG>` trick only applies to DLL
  platforms.
- Output to `<Plugin>/Binaries/Linux/libRmlUiBridge.so`; UE adds `${ORIGIN}` to
  module RPATH, so no absolute path is needed.
- Wrap Windows-only code (desktop color scheme, reduced motion, DX11 view
  creation) in one platform header instead of scattering `#ifdef`s — a single
  `RMLUE_WINDOWS` macro keeps the fallback behavior greppable.
- Provide a `BuildBridge.sh` next to `BuildBridge.ps1`; the module's load error
  message must name the right script per platform.

## .uproject platform declarations

Modules with no Linux binaries must be excluded, not left to fail at link time:

```json
{ "Name": "Puerts", "Enabled": true, "PlatformAllowList": ["Win64"] }
```

Plugin that does support Linux lists it explicitly:

```json
"SupportedTargetPlatforms": ["Win64", "Linux"]
```

`PlatformAllowList` also works on individual modules inside a `.uplugin`.

## clangd

```bash
Engine/Build/BatchFiles/Linux/Build.sh -Mode=GenerateClangDatabase \
  -Project="<repo>/<Project>.uproject" \
  -Target="<Project>Editor Linux Development" \
  -OutputDir="<repo>/.vscode"
```

`.clangd` should then point `CompilationDatabase: .vscode` and strip
`-resource-dir` / `-Werror` (MSVC/clang-cl flags are invalid locally).

`compile_commands.json` is **not** produced by normal builds or by
`GenerateProjectFiles` — UBT writes it only in the explicit
`-Mode=GenerateClangDatabase` tool mode. After moving, renaming, adding or
deleting source files the old database keeps stale paths and clangd lights up
with phantom errors, so regenerate.

Do not use file mtimes to decide whether to regenerate: version-control sync and
builds both touch timestamps, so a mtime check rebuilds the database on every
build. Compare the **file list** instead:

```sh
find Source -type f \( -name '*.h' -o -name '*.cpp' \) | sort > .vscode/.clangdb-source-list
# before building: diff the current list against that snapshot; regenerate only on mismatch
```

Content edits do not need a regeneration — the compile flags are unchanged.

### Silence IncludeCleaner for UE umbrella headers

clangd's IncludeCleaner reports `Included header CoreMinimal.h is not used
directly (fix available)` as diagnostic `clangd/unused-includes`. It is a false
positive in UE projects: `CoreMinimal.h` and a project's own `<Project>.h` are
PCH-style umbrella headers, and `*.generated.h` relies on definitions pulled in
transitively, so applying the "fix" breaks the build. Turn the diagnostic off in
`.clangd` (never delete the include):

```yaml
Diagnostics:
  UnusedIncludes: None   # None | Strict (default Strict)
```

Two notes when verifying: `clangd --check` does **not** run IncludeCleaner, so it
will look clean even while the editor shows the warning. To reproduce what VS
Code sees, drive clangd over LSP (`initialize` → `initialized` →
`textDocument/didOpen`) and read `textDocument/publishDiagnostics`.
`MissingIncludes` is a separate key — leave it at its default unless it also
turns noisy.

## Repo / VCS hygiene

Ignore build outputs rather than committing them:

```gitignore
/Plugins/*/Binaries/
/Plugins/*/Intermediate/
/Plugins/<X>/Source/ThirdParty/<Bridge>/build/
/Plugins/<X>/Source/ThirdParty/<Bridge>/build-linux/
/Plugins/<X>/Source/ThirdParty/<Bridge>/grid/target/
/Content/Developers/<you>/
/.vscode/
/.aws/
/.codex/
```

Commit vendored sources deliberately (e.g. re-allow
`vendor/` with a negated rule) — they are needed to rebuild the bridge on a
clean clone.

Per-machine absolute paths belong in gitignored files. `D:\UE_5.8\Engine` in a
plugin's `.props` is already machine-specific; replacing it with a Linux path
helps one machine and breaks the other, so leave it out of shared commits.

### Optional import props are local overrides by design

`*.ubtplugin.csproj` is authored source, not generated — UBT only *discovers*
them (`ProjectFileGenerator`) and compiles them through `CsProjBuilder`, which
passes `/p:EngineDir=<engine>` and `/p:EnginePath=<engine>` as global
properties. A sibling props imported as

```xml
<Import Project="X.ubtplugin.csproj.props" Condition="Exists('...')" />
```

therefore only exists to make a bare `dotnet build` work. Treat it as a local
override: commit an `.dvignore` / `.gitignore` rule for it and keep a per-machine
copy, instead of committing either `D:\UE_5.8\Engine` or a Linux path.

Removing it from tracking is safe because the import is conditional; verify with
one incremental `Build.sh` run afterwards.
