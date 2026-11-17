---
name: ue-project-setup
description: Configure an Unreal Engine project for AI-assisted work — enable the built-in UE MCP server and connect VS Code/Codex/Claude to it, fix PIE mouse capture and Enhanced Input (cursor escapes the window, camera won't turn, WASD dead), make full-screen HUD widgets pass Slate input through, and build the RmlUi/Slate native toolchain on Linux. Use when setting up a new UE project, when the editor is open but the assistant can't reach it, or when PIE input is broken. Not for gameplay feature work.
---

# UE Project Setup

Bootstrap checklist for a UE project you want to drive from an AI agent. The
goal is: the running editor is reachable over MCP, and PIE takes mouse/keyboard
properly even with a custom HUD on screen.

Do the steps in order. Each one is verifiable on its own; don't move on with a
failing step. Restart the editor after changing plugin/config files — .uproject
and settings ini are read at startup.

## 1. Enable the MCP plugin

Add to `<Project>.uproject` under `Plugins` (UE 5.8 ships it at
`Engine/Plugins/Experimental/ModelContextProtocol`):

```json
{ "Name": "ModelContextProtocol", "Enabled": true }
```

If the project is Windows-only for other reasons, do **not** limit this plugin
per platform; MCP is editor-side and works wherever the editor runs.

## 2. Auto-start the server

`Config/DefaultEditorPerProjectUserSettings.ini`:

```ini
[/Script/ModelContextProtocolEngine.ModelContextProtocolSettings]
bAutoStartServer=True
ServerPortNumber=8000
ServerUrlPath=/mcp
```

Field names come from `ModelContextProtocolEngine`'s settings class; the other
useful one is `bEnableToolSearch` (default true).

**Gotcha:** this is `Default...` for *per-user* settings. If the machine already
has `Saved/Config/<Platform>Editor/EditorPerProjectUserSettings.ini` with an
explicit value, that wins and the Default file appears to do nothing. Either set
it once through Project Settings, or remove the key from the Saved file.

## 3. Point the AI clients at it

| Client | File | Shape |
| --- | --- | --- |
| VS Code | `.vscode/mcp.json` | `{ "servers": { ... } }` |
| Codex / Claude | `.mcp.json` | `{ "mcpServers": { ... } }` |

Both use the same entry:

```json
{
  "mcpServers": {
    "unreal-mcp": { "type": "http", "url": "http://127.0.0.1:8000/mcp" }
  }
}
```

## 4. Verify before debugging anything else

```bash
curl -sS -X POST http://127.0.0.1:8000/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}}'
```

A JSON-RPC result means the server is up. Connection refused means: editor not
running, plugin not enabled/compiled, port taken, or the Saved-config override
above. Check the editor log for the server startup line before touching client
config.

## 5. Make PIE own the mouse

```ini
[/Script/UnrealEd.LevelEditorPlaySettings]
GameGetsMouseControl=True
```

This alone is not enough in embedded PIE — see
[references/pie-input-and-hud.md](references/pie-input-and-hud.md) for the
controller-side capture code and the symptom→cause table.

## 6. HUD must not eat Slate events

A full-screen Slate/RmlUi/UMG HUD whose widget returns `Handled` for mouse
events will kill camera look and can steal keyboard focus. Set
`HitTestInvisible` on the widget **and** on the `TakeWidget()` result after
adding it to the viewport. Details and the RmlUi-specific reason are in the same
reference.

## 7. Build-side bits (only if the project needs them)

- RmlUi/Slate native bridge on Linux, `.uproject` platform allow lists, clangd
  compile database, and silencing the UE `CoreMinimal.h is not used directly`
  false positive (`Diagnostics.UnusedIncludes: None`):
  [references/linux-toolchain.md](references/linux-toolchain.md).
- Version-control hygiene for generated dirs and per-machine files: same
  reference, last section.

## Ordering for a brand-new project

1. Enable plugins in `.uproject` first — the editor must compile before any MCP
   or input work can be tested.
2. Add ini + client JSON, restart, verify with the curl probe.
3. Only then touch input/HUD code, and verify with logs, not by feel: log
   whether the viewport has mouse capture, keyboard focus, and whether Move/Look
   receive non-zero values.

## Don't

- Don't `throw new BuildException("... currently supports Win64")` as a platform
  guard when adding Linux support; branch on `Target.Platform` and select the
  native library per platform.
- Don't reach for private engine APIs (`FSceneViewport::AcquireFocusAndCapture`
  is private in 5.8) when public Slate APIs reproduce the same reply.
- Don't commit absolute engine paths (`D:\UE_5.8\Engine`,
  `/path/to/UE_5.8.4/Engine`) in plugin `.props` files — they are per-machine.
