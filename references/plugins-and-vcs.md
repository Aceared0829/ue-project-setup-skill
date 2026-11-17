# Platforms, native plugins, and VCS hygiene

## Declare platform support

Linux has to be declared explicitly. A module with no Linux binary otherwise
fails at link time with an error that reads like a code problem.

```json
// <Project>.uproject -> Modules
{ "Name": "SomeWinOnlyPlugin", "Enabled": true, "PlatformAllowList": ["Win64"] }
```

```json
// <Plugin>.uplugin
"SupportedTargetPlatforms": ["Win64", "Linux"]
```

`PlatformAllowList` also works per module inside a `.uplugin`. Excluding a
module is the correct move when the vendor ships only Windows binaries — you do
not need (and usually cannot get) a Linux build just to open the editor.

## Porting a plugin whose native dependency is Windows-only

Worked example: `RmlUiUnreal` ships a CMake project that only handles Windows,
plus a Rust static lib. The general shape of the fix:

- **CMake**: add `UNIX AND NOT APPLE` next to the Win32 branch; select 64-bit
  pointers per platform instead of assuming MSVC; set
  `CMAKE_POSITION_INDEPENDENT_CODE ON` for static vendor libs that end up in a
  `.so`.
- **Artifact names**: they differ per platform (`foo.lib` vs `libfoo.a`,
  `bar.dll` vs `libbar.so`). Resolve them in one helper, not in five call sites.
- **Link libraries**: swap the Win32 set (`ws2_32 userenv bcrypt ntdll`) for the
  POSIX set (`pthread dl m`).
- **Renderer backends**: drop D3D-only sources on Linux and force the
  platform-neutral path (here: the Slate command renderer), including clamping
  the setting so a saved Windows value cannot re-enable D3D.
- **Shared libraries are `LIBRARY` artifacts**: set `LIBRARY_OUTPUT_DIRECTORY`.
  The per-config `RUNTIME_OUTPUT_DIRECTORY_<CONFIG>` trick is DLL-only and does
  nothing on Linux.
- **RPATH**: UE adds `${ORIGIN}` to module RPATH, so drop the `.so` next to the
  module and never hardcode an absolute path.
- **One platform macro header** (`#if PLATFORM_WINDOWS` style) around
  Windows-only code — desktop color scheme, reduced motion, D3D view creation —
  instead of `#ifdef`s scattered through the plugin.
- **Build script parity**: if the plugin has `Build.ps1`, add `Build.sh`, and
  make the module's load-error message name the right script per platform.

Verify by loading the plugin in the editor and checking the log for the module
load line, not just by a successful compile.

## Absolute engine paths are per-machine

`D:\UE_5.8\Engine` in a committed file helps one machine and breaks every other.
If a file must contain an engine path, keep it gitignored and generate it, e.g.
`.vscode/ue-root` plus a `$UE_ROOT` override.

## Optional import props are local overrides by design

`*.ubtplugin.csproj` is authored source, not generated: UBT only *discovers*
them (`ProjectFileGenerator`) and compiles them via `CsProjBuilder`, which passes
`/p:EngineDir=<engine>` and `/p:EnginePath=<engine>` as global properties. A
sibling props imported as

```xml
<Import Project="X.ubtplugin.csproj.props" Condition="Exists('...')" />
```

therefore exists only to make a bare `dotnet build` work outside UBT. Treat it
as a local override: ignore it in VCS and keep a per-machine copy, rather than
committing either a Windows or a Linux absolute path. Removing it from tracking
is safe because the import is conditional — confirm with one incremental build.

## Ignore list

```gitignore
/Binaries/
/Intermediate/
/Saved/
/DerivedDataCache/
/Plugins/*/Binaries/
/Plugins/*/Intermediate/
/Plugins/*/Source/ThirdParty/*/build/
/Plugins/*/Source/ThirdParty/*/build-linux/
/Plugins/*/Source/ThirdParty/*/grid/target/
/Content/Developers/<user>/
/.vs/
/.vscode/
*.sln
*.suo
*.user
*.vcxproj*
```

Commit vendored sources deliberately — they are what makes a clean clone
rebuildable. Re-allow them with a negated rule (`!/Plugins/X/Source/ThirdParty/Y/`)
instead of dropping the directory from the ignore list.

`.vscode/` is ignored by UE's default rules. If the team should share tasks,
negate exactly that file (`!/.vscode/tasks.json`) and keep `settings.json` out —
it holds machine-specific engine paths.

## Before committing

- Diff the ignore list against what `git status` (or your VCS status command)
  shows: an unexpected `.uasset` or `.props` diff usually means an editor or a
  build touched it, not that you changed it.
- Commit in reviewable units; unrelated binary churn in the same commit hides
  the real change.
