# Architecture

## Goal

Native macOS app that emulates the main opencode features locally:
chat with LLM, tools/MCP, explicit permissions on files and screen, plug-in
knowledge base. No external dependencies, only system SDKs.

## SwiftPM target

```
SphereCore        models, SQLite, migrations, grants, network rules, manifest, installer
SphereLLM         OpenAI-compatible and Anthropic providers, SSE streaming
SphereMCP         stdio MCP client (JSON-RPC), module process host
SphereTools       filesystem, web, git, system and exec providers, ToolRouter
SphereScreen      ScreenCaptureKit, window allowlist
SphereKnowledge   KnowledgeProvider contract + stub
SphereSpeech      text-to-speech (AVSpeechSynthesizer)
SphereRuntime     shared app/CLI wiring + AgentRunner
SphereApp         SwiftUI GUI (executable "Sphere")
SphereCLI         CLI (executable "sphere-cli")
```

Dependencies:

```
SphereApp ─┬─ SphereRuntime ─┬─ SphereCore
           │                 ├─ SphereLLM ──── SphereCore
           │                 ├─ SphereMCP ──── SphereCore
           │                 ├─ SphereTools ── SphereCore, SphereMCP
           │                 ├─ SphereScreen ─ SphereCore
           │                 ├─ SphereKnowledge
           │                 └─ SphereSpeech ─ SphereCore
           ├─ MarkdownUI (SPM)
           └─ (runtime targets)
SphereCLI ─┘
```

## Wiring

`SphereRuntime` builds and owns all subsystems:

```
Database (SQLite) ─ Migrations
   ├─ SessionStore
   ├─ ModuleRegistry
   ├─ PermissionStore ── PermissionEngine ── FilesystemBroker
   ├─ NetworkStore ── NetworkPolicy ── WebToolProvider
   └─ SettingsStore

ConfigStore + SecretStore (Keychain import only) ── LLMProviderFactory
MCPModuleHost ── MCPClient (one per module) ── StdioMCPTransport
ToolRouter (filesystem + web + git + system + exec + MCP catalog) ── AgentRunner
ScreenCaptureService + ScreenAllowlist
SpeechService (AVSpeechSynthesizer)
KnowledgeProvider (stub)
```

App and CLI share the same `SphereRuntime`, so database, grants and modules
are always consistent.

### UI log

`SystemLogView` shows logs in the style of macOS Console: `TIME` column
(`yyyy-MM-dd HH:mm:ss.SSS`), colored `STATUS` column (`ALLOW`/`DENY`/
`BLOCK`), then `DETAILS` in monospaced with alternating background rows. It is used
both for the Access log and for network requests. In addition, `AuditLog` mirrors every
event into the unified log via `os.Logger` (subsystem `com.sphere.app`,
category `audit`).

### Markdown rendering

Assistant responses are rendered with **MarkdownUI** (SPM,
`gonzalezreal/swift-markdown-ui`), based on cmark-gfm. It supports headings, lists,
tables, task lists and code blocks. The AI message font (family and
size) is applied via `markdownTextStyle`. Remote images are
disabled with `markdownImageProvider(.asset)`, so rendering does not bypass
the network ban list: only local assets are shown.

## Turn flow

```
UI/CLI
  → AgentRunner.run()
      ├─ persists the user message
      ├─ builds LLMRequest (history + system prompt + tool catalog)
      ├─ LLMProvider.stream()  ── SSE ──▶ text delta / tool call
      ├─ if there are tool calls:
      │    ToolRouter.invoke(module_tool, args)
      │       ├─ policy allow/ask/deny
      │       ├─ built-in provider  or  MCPClient.callTool()
      │       └─ result → role=tool message
      └─ repeats until the model stops calling tools (max 12 steps)
```

Sessions receive a stable progressive `#N`; `AgentRunner` passes the session id
to every tool invocation, and file/network/clipboard/tool logs persist both the
session id and number for display. All log queries return the newest 200 rows.

Tool names: normalized `<module>_<tool>`. The catalog is aggregated by
`ToolRouter.definitions()`, which filters tools that are disabled
(`config.disabledTools`) **and** tools whose policy is `deny` (or `ask` without
an approval handler), so the model is never advertised a tool that `invoke`
would reject. `AgentRunner` refreshes the catalog at every step, so mid-run
changes take effect on the next model call; `invoke` re-checks before executing.
Duplicate namespaced names are detected: the first provider wins, the collision
is written to the audit log, and dispatch uses the winning tool's provider
(ownership by tool name, not only by module id).

### Built-in providers

- `sphere.filesystem`: text/binary reads, writes, glob/grep, stat, edits,
  JSON/YAML/plist selectors, image metadata.
- `sphere.web`: `web_fetch` and `web_search` (DuckDuckGo HTML), behind the
  network ban list.
- `sphere.git`: read-only status/diff/log/show/blame via `/usr/bin/git`.
- `sphere.system`: `system_info` and clipboard read/write (logged directly in
  `clipboard_events` with session attribution, with a per-session counter in the
  status bar and a dedicated Clipboard tab).
- `sphere.exec`: opt-in argv-only sandboxed command execution. Child processes
  run under `sandbox-exec` with network denied and writes limited to the
  granted root; see [PERMISSIONS.md](PERMISSIONS.md).

## MCP client (in-house)

The official MCP SDK requires Swift 6 / Xcode 16; the target is macOS 13 with
Xcode 15.2, so the client is implemented in-house and isolated behind
`MCPTransport` for a future replacement.

- `StdioMCPTransport`: `Process` + `Pipe`, newline-delimited JSON-RPC framing,
  stderr logging, close on EOF/termination.
- `MCPClient`: thread-safe class with `RequestStore` (continuation + watchdog per
  request, per-call timeout), `initialize` /
  `notifications/initialized` handshake, `tools/list`, `tools/call`.
- `MCPModuleHost`: one client per module, cached catalog, restart, logs.
- `MCPTransport` is the seam for switching to the official SDK in the future.

## LLM

`LLMProvider` protocol with `AsyncThrowingStream<LLMEvent, Error>` streaming.

- **OpenAI-compatible**: `/chat/completions`, SSE, accumulation of fragmented
  `tool_calls`, mapping `assistant.tool_calls` → tool call.
- **Anthropic**: `/v1/messages`, SSE (`content_block_*`), accumulation of
  `input_json_delta`, tool results as `tool_result` blocks.

API keys are stored in `secrets.json` (0600); the Keychain is only used for the one-time import. The base URL and model live in `config.json`.

## Database (SQLite, WAL)

Migrations in `SphereCore/Database/Migrations.swift`, dependency-free wrapper
in `Database.swift` (serialized with a lock).

| Table | Content |
|---|---|
| `schema_migrations` | applied schema version |
| `settings` | service key/value |
| `sessions` | chat sessions |
| `messages` | messages (role, content, tool_call_id, tool_calls_json, attachments_json) |
| `tool_calls` | tool calls (status, arguments, result) |
| `modules` | JSON manifest + install path + enabled |
| `path_grants` | path, RO/RW, recursive, scope, read/write counters |
| `access_events` | audit of every allowed/denied access |
| `screen_grants` | window allowlist, capture counters |
| `network_rules` | URL/domain/IP ban, enabled, block counter |
| `network_events` | audit of allowed/blocked internet requests |
| `clipboard_events` | clipboard read/write accesses (session, operation, detail) |

Migrations: v1 base schema, v2 session token/cost, v3 message attachments,
v4 network rules and events, v5 message tool calls, v6 clipboard events,
v7 session numbers + session attribution on access/network/clipboard/tool logs.

## Storage

All per-user, no admin privileges:

```
~/Library/Application Support/Sphere/
  sphere.sqlite
  config.json
  secrets.json          API key (0600)
  Plugins/<id>/
  Store/
  Captures/
  Logs/sphere.log
  Logs/http.log
  Logs/keychain.log
Keychain service: com.sphere.app (one-time import only)
```

## Security

- **Non-sandboxed** app + notarization planned: required for a local agent
  that uses terminal/files/screen.
- File access mediated by the broker for authoritative counters/RO-RW; third-party
  modules cannot be confined per-path until per-module sandboxing arrives.
- Screen: per-app TCC + internal per-window allowlist (default deny).
- Network: default allow, URL/domain/IP ban list; check before the request
  and on the final URL after redirects; every request is logged.
- Modules disabled at install, permission consent, audit.

## Roadmap

- **Phase 2**: edit/glob/grep broker with diff, shell/exec with approval,
  per-module sandbox-exec, FTS5 → embeddings knowledge base, editor policy,
  `sphere-module` CLI.
- **Phase 3**: remote module catalog with `sha256`/signature, notarization,
  auto-update, opt-in crash reports, localization.
