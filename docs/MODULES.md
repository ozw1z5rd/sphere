# Modules

Sphere extends its functionality through **modules** using the **standard MCP
protocol over stdio**. A module is a self-describing file: it contains
everything needed to be configured and started. The end user never writes or
edits any manifest.

## Accepted formats

| Format | Description |
|---|---|
| `.spheremodule` | Single-file ZIP archive (recommended). Finder treats it as a single file. |
| `.zip` | ZIP with `module.json` inside; converted on installation. |
| `.sphereplug` | A single executable script with metadata in the header. |
| Folder | Folder containing `module.json` (useful during development). |

Installation extracts/copies the module into
`~/Library/Application Support/Sphere/Plugins/<id>/` and keeps the original
archive in `Store/`. **Installed ≠ enabled**: after installation the module is
disabled until the user enables it.

## The `module.json` manifest

Written by the module author. Complete example:

```json
{
  "schemaVersion": 1,
  "id": "com.example.filesystem",
  "name": "Filesystem",
  "version": "1.2.0",
  "author": "Example",
  "description": "Filesystem read/write with policy",
  "icon": "resources/icon.png",
  "kind": "mcp",
  "transport": {
    "type": "stdio",
    "command": ["node", "${MODULE_DIR}/bin/server.js"],
    "cwd": "${MODULE_DIR}",
    "env": { "LOG_LEVEL": "info" },
    "healthCheck": { "method": "tools/list", "timeoutMs": 15000 }
  },
  "capabilities": ["tools", "resources", "prompts"],
  "permissions": {
    "filesystem": { "paths": ["~/Projects"], "mode": "ro", "reason": "Index the code" },
    "screen": { "windows": [], "reason": "Screenshots on request" },
    "network": false,
    "process": false
  },
  "ui": { "category": "Files", "settings": [] },
  "autoStart": false
}
```

### Fields

| Field | Required | Notes |
|---|---|---|
| `schemaVersion` | no (default 1) | Only version 1 is supported today. |
| `id` | yes | Must match `^[A-Za-z0-9._-]+$` and be unique. |
| `name` | yes | Name shown in the UI. |
| `version` | yes | Used for updates and archiving. |
| `author`, `description`, `icon` | no | UI metadata. |
| `kind` | no (default `mcp`) | `mcp`, `knowledge` or `tool`. |
| `transport` | yes for `mcp`/`tool` | Only `type: "stdio"` is supported. |
| `capabilities` | no | `tools`, `resources`, `prompts`. |
| `permissions` | no | Declaration of required permissions. |
| `ui` | no | Category and settings fields. |
| `autoStart` | no (default false) | Not used for auto-start at installation. |

### `${MODULE_DIR}`

The app replaces `${MODULE_DIR}` with the absolute path of the installed folder
in `command`, `cwd` and in the values of `env`. This makes the module portable:
no hard-coded user paths.

### Declared permissions

```json
"permissions": {
  "filesystem": { "paths": ["~/Projects"], "mode": "ro", "reason": "…" },
  "screen": { "windows": [], "reason": "…" },
  "network": false,
  "process": false
}
```

They are **author declarations**, shown to the user as a consent request. They
are not a sandbox mechanism (see [PERMISSIONS.md](PERMISSIONS.md)).

## Required MCP protocol

Sphere is an MCP client over the **stdio** transport with JSON-RPC 2.0 messages
**delimited by newlines** (one JSON object per line). The client:

1. starts the process;
2. sends `initialize` and then `notifications/initialized`;
3. calls `tools/list` to build the catalog;
4. uses `tools/call` to run tools.

The server must respond on stdout and must not write logs to stdout (use
stderr). No dependencies are needed: see the example in `examples/hello-module`.

## Complete example

`examples/hello-module/` contains:

```
module.json
server.py
```

Try:

```bash
swift run sphere-cli modules install examples/hello-module
swift run sphere-cli modules tools com.sphere.examples.hello
swift run sphere-cli modules enable com.sphere.examples.hello
swift run sphere-cli modules remove com.sphere.examples.hello
```

## Packaging a module

```bash
./scripts/package-module.sh examples/hello-module
# creates examples/hello-module.spheremodule
```

The script uses `ditto` to create a ZIP archive with the `.spheremodule`
extension, which Sphere extracts automatically.

## Header for `.sphereplug`

A single script can embed the manifest:

```python
#!/usr/bin/env python3
# --- sphere-module ---
# { "id": "com.example.ping", "name": "Ping", "version": "0.1.0",
#   "kind": "mcp", "permissions": { "network": false, "process": false } }
# --- end sphere-module ---
```

If `transport` is omitted, Sphere uses the script itself as the command. The
file must have the execute bit set or be interpretable (shebang).

## Security and Gatekeeper

- Modules with **compiled binaries** downloaded from the internet must be
  signed/notarized to pass Gatekeeper. To start with, prefer script-based
  modules (`node`, `python3`, `sh`).
- Sphere handles the `com.apple.quarantine` attribute and does not execute
  anything automatically at installation.
- Validation: `module.json` must conform to the schema; `id` and `version` are
  required; `transport` is required for MCP modules.
- Ed25519 package signing and a remote catalog with `sha256` are planned for a
  later phase.

## Updating and removal

- Reinstalling the same `id` replaces the folder while keeping the state in the
  registry; it compares `version` in the manifest.
- `modules remove <id>` stops the process, deletes the record and the installed
  folder. The archive in `Store/` remains for manual reinstallations.
