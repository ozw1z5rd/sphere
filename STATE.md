# Sphere — Project status

> Last updated: **2026-11-15**
> Purpose of this file: make it possible to resume work exactly where it stopped.
> It contains status, decisions, commands, known limits and next steps.

---

## 1. Goal

**Native** macOS app (SwiftPM + SwiftUI/AppKit) that emulates the main features
of opencode locally:

- chat with LLM (provider-agnostic + local);
- tools/MCP installable as draggable **files** (`.spheremodule`,
  `.sphereplug`, `.zip`, folder);
- permission-mediated file access with RO/RW counters;
- screen access with **per-window** consent;
- knowledge base as a plugin;
- Internet access with a URL/domain/IP **ban list**;
- Multilingual UI (Italian + English, system default or in-app override),
  Console-style macOS logs.

---

## 2. Verified environment

| Item | Value |
|---|---|
| macOS | 13.7.8 |
| Xcode | 15.2 |
| Swift | 5.9.2 |
| Deployment target | macOS 13.0 |
| External dependency | `MarkdownUI 2.4.1` (SPM, + `swift-cmark`, `NetworkImage`) |
| Storage | all per-user in `~/Library/Application Support/Sphere/` |

Important note: the official MCP SDK requires Swift 6 / Xcode 16, so an
**in-house MCP stdio client** was implemented (newline-delimited JSON-RPC).

---

## 3. Current status

- `swift build` → **OK**
- `swift test` → **59 tests, 0 failures**
- App bundle: `dist/Sphere.app` (valid ad-hoc signature)
- Launch: `./scripts/build-app.sh release --open`
- At the time of the last update the app is running.

### Completed features

**Chat / LLM**
- OpenAI-compatible provider (OpenAI, Ollama, LM Studio, OpenRouter, DeepSeek…)
  and Anthropic.
- SSE streaming, tool calling, multi-step agent loop.
- Provider and **model** selection (list from `/models` or `/v1/models`) with
  generation parameters: temperature, max tokens, top_p, top_k,
  frequency/presence penalty, seed, stop sequences.
- API keys in `secrets.json` (0600); one-time import from the Keychain.
- HTTP/Keychain logs in `Logs/http.log` and `Logs/keychain.log`; diagnosable
  401 errors.
- **Markdown** rendering of AI responses with MarkdownUI; remote images
  disabled (`markdownImageProvider(.asset)`) to respect network bans.
- Separate fonts for user/AI messages (Settings → Aspetto (Appearance)).
- Text-to-speech with `AVSpeechSynthesizer`: toggle in Settings and **Voce**
  (Voice) checkbox in the chat header; pause/resume/stop; optional automatic
  reading.

**Sessions**
- Creation, selection, persistence in SQLite.
- **Swipe-to-delete** and context menu.
- **Finder-style inline rename** (click on the session, then click on the name;
  or double click/context menu — text preselected, Enter confirms,
  Esc cancels).
- **Multilingual UI**: Italian and English, following the system language or
  overridden in **Settings → General → Language**.
- Status bar: tokens, estimated cost, session time, FS access counters.

**Modules**
- `.spheremodule` (single-file ZIP), `.sphereplug` (script with header), `.zip`,
  folder.
- Self-describing `module.json` manifest (written by the author, not the user).
- Drag&drop, install in Plugins, enable/disable, MCP startup.
- Working example: `examples/hello-module` (zero-dependency Python server).
- Packaging: `scripts/package-module.sh`.

**File access**
- Built-in filesystem broker (`sphere.filesystem`): `fs_read` (line range),
  `fs_write`, `fs_list`, `fs_glob`, `fs_grep` (binary report, context, counts,
  `.gitignore`), `fs_stat` (magic-byte type), `fs_read_bytes`, `fs_edit`
  (replace/unified patch), `fs_select` (JSON/YAML/plist selector or line range),
  `image_inspect` (metadata + optional thumbnail).
- Recursive RO/RW grants with read/write counters and audit.
- UI: **File Access** tab, 1/3 (grants) – 2/3 (log) split.

**Screen**
- ScreenCaptureKit: enumeration and capture of windows/displays.
- Internal allowlist per window/app (default deny) + capture counters.
- TCC Screen Recording is per-app: per-window granularity is application-level.

**Network**
- Built-in `web_fetch` and `web_search` (DuckDuckGo HTML) tools (`sphere.web`),
  HTML→text, size limits.
- Read-only git tools (`sphere.git`): status/diff/log/show/blame.
- System tools (`sphere.system`): `system_info`, clipboard read/write.
- **Sandboxed exec** (`sphere.exec`, opt-in from Settings → Tools): argv
  allowlist, no shell, granted cwd, timeout, no network, writes limited to the
  granted root via `sandbox-exec`.
- **Tools tab**: per-tool enable/disable (all enabled by default; disabled
  tools are hidden from the model catalog and rejected at invocation) plus the
  global last-200 tool usage log.
- **Clipboard tab**: read/write controls, optional local preview and global
  clipboard log.
- **Session numbers**: stable progressive `#N` badges, also recorded in every
  log (access, network, tools, clipboard).
- **Logs window**: dedicated window with File Access / Network / Tools /
  Clipboard (database) and HTTP / Keychain (file-backed) logs, last 200 rows,
  opened from Settings and the status bar.
- **Status bar**: clickable file/clipboard/network/tool counters.
- **DeepSeek pricing**: official cache-hit/cache-miss input and output rates with
  peak windows; session cost accumulates per request. Historical sessions with
  token totals but no cost are backfilled using the cache-miss rate.
- **Collapsible AI responses**; Markdown is rendered only when an assistant
  message is persisted (no live token rendering, just a “Generating…” row).
- **Default allow** ban list: URL (prefix), domain (+subdomains), IP/CIDR
  (with DNS resolution). Checked before the request and on the final URL.
- Request audit in `network_events`; block counter per rule.
- UI: **Network** tab, 1/3 (rules) – 2/3 (request log) split.

**Logs / diagnostics**
- `SystemLogView` Console-style: `TIME | STATUS | DETAILS`, timestamp
  `yyyy-MM-dd HH:mm:ss.SSS`, colored status, zebra rows, monospaced.
- Events mirrored to the **unified macOS log** via `os.Logger`
  (`subsystem com.sphere.app`, category `audit`).
- Settings → Diagnostica (Diagnostics): full HTTP log, open logs, import keys.

**Info / branding**
- **About Sphere** window (menu Sphere → About Sphere): circuit-brain app icon
  prominently at the top, company logo (`logo.png` →
  `Sources/SphereApp/Resources/CompanyLogo.png`) at the bottom, and the
  **Creative Commons BY-NC-SA 4.0** license notice (non-commercial,
  attribution, share-alike).
- App icon: round green/electric-blue brain with circuit traces,
  generated by `scripts/generate-icon.sh` → `Support/Sphere.icns`.

---

## 4. Useful commands

```bash
cd sphere

# Build / test
swift build
swift test

# App .app
./scripts/build-app.sh release            # creates dist/Sphere.app
./scripts/build-app.sh release --open     # creates and launches
open dist/Sphere.app

# CLI
swift run sphere-cli help
swift run sphere-cli models
swift run sphere-cli chat "ciao"
swift run sphere-cli web https://example.com
swift run sphere-cli ban add domain example.com
swift run sphere-cli ban list
swift run sphere-cli key import-keychain
swift run sphere-cli say "ciao"

# Icon
./scripts/generate-icon.sh

# Module packaging
./scripts/package-module.sh examples/hello-module
```

---

## 5. Architecture and key files

```
Package.swift
Sources/
  SphereCore/       models, SQLite, migrations, grants, network, manifest, installer,
                    SecretStore, Keychain (import only), AuditLog (OSLog)
  SphereLLM/        OpenAI-compatible + Anthropic providers, GenerationOptions
  SphereMCP/        MCPClient, StdioMCPTransport, MCPModuleHost
  SphereTools/      FilesystemBroker, WebToolProvider, GitToolProvider,
                    SystemToolProvider, ExecToolProvider, ToolRouter
  SphereScreen/     ScreenCaptureService, ScreenAllowlist
  SphereKnowledge/  KnowledgeProvider + stub
  SphereSpeech/     SpeechService (AVSpeechSynthesizer)
  SphereRuntime/    SphereRuntime (wiring), AgentRunner
  SphereApp/        SwiftUI GUI
  SphereCLI/        CLI
Tests/SphereCoreTests/SphereCoreTests.swift   (59 tests)
examples/hello-module/                        example MCP module
scripts/                                      build-app, package-module, icon
Support/Info.plist, Support/Sphere.icns
docs/                                          USAGE, MODULES, PERMISSIONS, ARCHITECTURE
```

Main UI files:
- `Sources/SphereApp/AppModel.swift` — application state, actions.
- `Sources/SphereApp/Views/ChatView.swift` — chat, sessions, attachments, Markdown, voice.
- `Sources/SphereApp/Views/SettingsView.swift` — TabView: Provider, Voce (Voice), Aspetto (Appearance),
  Diagnostica (Diagnostics), Knowledge, Storage.
- `Sources/SphereApp/Views/FileAccessView.swift` — grants + access log.
- `Sources/SphereApp/Views/NetworkView.swift` — bans + requests.
- `Sources/SphereApp/Views/SystemLogView.swift` — Console-style log.
- `Sources/SphereApp/Views/ToolsView.swift` — per-tool enable/disable + tool usage log.
- `Sources/SphereApp/Views/ClipboardView.swift` — clipboard controls, preview and log.
- `Sources/SphereApp/Views/LogsView.swift` — dedicated logs window.
- `Sources/SphereApp/Views/AboutView.swift`, `StatusBarView.swift`.

### DB schema (migrations v1–v7)

v1: `sessions`, `messages`, `tool_calls`, `modules`, `path_grants`,
`access_events`, `screen_grants`, `settings`, `schema_migrations`
v2: session tokens/cost (`prompt_tokens`, `completion_tokens`, `cost_usd`)
v3: message attachments (`attachments_json`)
v4: `network_rules`, `network_events`
v5: assistant tool calls (`tool_calls_json`)
v6: `clipboard_events` (operation, detail, allowed, timestamp)
v7: session numbers; session attribution on access/network/clipboard/tool logs

### Data paths

```
~/Library/Application Support/Sphere/
  sphere.sqlite
  config.json
  secrets.json        API keys (0600)
  Plugins/<id>/
  Store/
  Captures/
  Logs/sphere.log
  Logs/http.log
  Logs/keychain.log
Keychain service: com.sphere.app (one-time import only)
```

---

## 6. Decisions made (do not change them without reason)

1. **Per-user storage** in Application Support, no `/Library`, no
   admin. Modules are files with a self-describing manifest.
2. **Not sandboxed + notarization planned** (ad-hoc signing for development).
3. **In-house MCP client** as long as we stay on Swift 5.9/Xcode 15.
4. **Secrets in `0600` files** instead of the Keychain: the ad-hoc signature changes on every
   rebuild and the Keychain ACL causes `errSecUserCanceled (-128)` → 401.
5. **Default allow network ban list**, with audit; MarkdownUI does not load remote
   images so as not to bypass the bans.
6. **Authoritative file access only via the broker**; third-party modules that do IO on their own
   cannot be confined per-path until per-module sandboxing arrives.
7. Build the app with `scripts/build-app.sh`; the icon and logo are copied into
   `Contents/Resources` together with the SPM resource bundle.

---

## 7. Known limits / caveats

- Third-party MCPs that access files directly are not confined per-path:
  audit + permission declaration; per-module sandboxing is on the roadmap.
- Screen: the TCC permission is per-app; per-window granularity is internal only.
- `web_fetch`: GET, no JavaScript, no cookies/cache; redirects checked
  on the final URL.
- Markdown rendering does not load remote images (asset-only).
- The TTS voice selection shows the PostScript names of the installed fonts.
- `Package.resolved` includes MarkdownUI/swift-cmark/NetworkImage: network is needed
  for the first `swift package resolve`.
- The icon is generated; if the drawing is modified, re-run
  `./scripts/generate-icon.sh`.
- App signed ad-hoc: to distribute to others you need a Developer ID + notarization.

---

## 8. Next steps (roadmap)

### Phase 2 (coding agent + knowledge base)
- Broker: `fs_edit` with diff, semantic search, binary/image support.
- `sandbox-exec` per module (or sandboxed helper) for real path enforcement
  (`sphere.exec` already sandboxes its own child processes).
- Knowledge base: FTS5 → local embeddings (`NLEmbedding`/Core ML/MLX) + UI
  for collections/ingest/reindex.
- Editor policy tool (`allow/ask/deny`) in the UI.
- Author CLI `sphere-module` (`init`, `package`, `validate`).

### Phase 3 (distribution)
- Remote module catalog with `sha256`/Ed25519 signature.
- DMG notarization, Sparkle auto-update, opt-in crash reports.
- Full IT/EN localization.

### Ideas / minor TODOs
- Show the ban rule by value in requests (today id + detail).
- Word highlighting during TTS reading.
- Attachment preview (images, PDF) in the message.
- Log filter/search.
- UI tests for rename/swipe (today tests are only on store/DB).

---

## 9. How to resume

1. `cd sphere`
2. `swift test` to confirm 59/59.
3. `./scripts/build-app.sh release --open` to launch the app.
4. Read `docs/USAGE.md` for usage, `docs/ARCHITECTURE.md` for the design.
5. Pick an item from section 8 and proceed.

If starting from a new machine: you need macOS 13+, Xcode 15.2+, a network
connection to resolve the SPM dependencies. The Keychain/`secrets.json` must be reconfigured
(re-enter the API keys or import them).
