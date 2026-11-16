# Usage guide

This guide covers everyday use of Sphere: LLM providers, chat, modules,
file access, screen access and the CLI.

## 1. Starting up

```bash
./scripts/build-app.sh release --open   # builds and launches dist/Sphere.app
```

Or, in development:

```bash
swift run Sphere
```

Alternatively, for automation and testing, use the CLI:

```bash
swift run sphere-cli help
```

Both share the same database and the same configuration, so grants and
modules created from the CLI are visible in the GUI and vice versa.

## 2. Configuring an LLM provider

Open **Sphere → Settings…** (`Cmd+,`). Settings are organized into
tabs: **General**, **Tools**, **Provider**, **Voce** (Voice), **Aspetto**
(Appearance), **Diagnostica** (Diagnostics), **Knowledge**, **Storage**.

The **General** tab sets the interface **Language**: *System (default)*,
*Italiano* or *English*. The change applies immediately to the whole UI (the
menu bar follows the macOS application language).

Preconfigured providers:

| Provider | Base URL | Example model | API key |
|---|---|---|---|
| Ollama | `http://localhost:11434/v1` | `llama3.1` | not required |
| OpenAI | `https://api.openai.com/v1` | `gpt-4o-mini` | required |
| Anthropic | `https://api.anthropic.com` | `claude-3-5-sonnet-latest` | required |
| DeepSeek | `https://api.deepseek.com/v1` | `deepseek-chat` | required |

Steps:

1. Click the circle next to the provider to make it **active**.
2. Edit **Base URL** and **Model** if needed.
3. For cloud providers, paste the **API key** and press **Save key** (it is
   saved in the Keychain, not in the config file).
4. Press **Save configuration** to persist the base URL and model.

For LM Studio, OpenRouter and other OpenAI-compatible endpoints, simply set
the correct base URL and the same `/chat/completions` scheme. DeepSeek is already
included among the preconfigured providers (`deepseek-chat`, or
`deepseek-reasoner` as the model).

### Selecting the model

- In **Settings**, press the refresh icon next to the *Model* field:
  Sphere queries `/models` (OpenAI-compatible) or `/v1/models` (Anthropic) and
  populates the **Modelli disponibili** (Available models) menu.
- Choose the model from the menu, or type an ID manually in the *Model* field.
- The choice is saved immediately in `config.json` and used by the session.
- In **Chat**, the top header lets you quickly switch model among
  the loaded ones.
- From the terminal: `swift run sphere-cli models`.

### Generation parameters

In **Settings** open **Parametri di generazione** (Generation parameters). An empty field means
"use the provider default". Supported parameters:

| Parameter | Provider |
|---|---|
| temperature, max tokens | all |
| top_p | all |
| top_k | Anthropic |
| frequency penalty, presence penalty, seed | OpenAI-compatible |
| stop sequences | all |

Press **Save configuration** to apply. Parameters not supported by a
provider are ignored (e.g. `top_k` on OpenAI).

## 3. Chat

- **New session** creates a session.
- **Rinomina** (Rename): click the session to select it, then click its name
  to enable inline editing (double click and the context
  menu → *Rinomina* also work). The text is selected; `Invio` (Enter) confirms,
  `Esc` cancels.
- **Elimina** (Delete): swipe left on the row (or context menu → *Elimina*).
  The session and its messages are removed from the database.
- Write in the field at the bottom and press `Cmd+Invio` or the send button.
- While the model is generating, the chat shows only a **Generating…**
  indicator. The response is rendered in **Markdown** (headings, lists, tables,
  code blocks) only once the assistant message is persisted, avoiding a full
  Markdown re-layout for every token.
- Each AI response can be **collapsed** with the chevron in its header; a
  one-line preview remains visible. Remote images are not loaded: the
  renderer uses only local assets, so the network ban list remains effective.
- Messages remain stored in SQLite.
- Tool calls are executed automatically according to the policy
  (`allow`/`ask`/`deny`) and the results are sent back to the model.
- The **Voce** checkbox in the header toggles speech synthesis on the fly.
- You can **drag files** into the chat window or use the paperclip.
  Attachments are shown as chips formatted with **only name and type**
  (icon, bold, colored background), not as a full path. The path remains
  available to the model/tool, not in the interface.

The agent receives a system prompt that tells it to:
- use only the paths granted through the filesystem broker;
- be able to capture only the allowed windows;
- request the minimum necessary access.

### Status bar

At the bottom of the main window the status bar is always visible with:

| Indicator | Meaning |
|---|---|
| `tok` | tokens consumed in the current session (prompt + completion; tooltip for details) |
| `$` | session cost, accumulated from prompt/completion tokens; DeepSeek uses cache-hit/cache-miss input rates and peak windows. Shows `—` for models without a price entry. |
| `clock` | time elapsed since the start of the session (updated every second) |
| `folder` | number of filesystem accesses in the session (tooltip: read/write/denied) |
| `clipboard` | clipboard accesses by the AI in the session (click: clipboard log) |
| `globe` | network requests in the session (click: network log) |
| `wrench` | tool calls in the session (click: tool usage log) |

The folder icon also opens the file-access log. All four clickable counters open
the Logs window on the matching section.

On the right, the active provider and model are shown.

### Attachments

- Drag one or more files (or folders) into the chat window, or press the
  **paperclip** next to the send button.
- Each attachment appears as a chip with an icon, **file name in bold** and
  **type** (e.g. `report.pdf` · `PDF document`), on a colored background; the `x`
  removes the attachment before sending.
- When sending, Sphere passes the model metadata with the full
  path, but in the interface and in the saved message you see only name and type.
- You can send attachments only, without text.

### Voce (text-to-speech)

- **Settings → Voce**: *Abilita sintesi vocale* (Enable speech synthesis), *Leggi automaticamente le
  risposte dell'AI* (Automatically read the AI responses), voice selection and speed.
- The same synthesis can be toggled on the fly with the **Voce** checkbox
  in the chat header.
- In **Chat** you find the speaker button on the last response and on every
  assistant message; during playback pause/resume and stop appear.
- API used: **`AVSpeechSynthesizer`** (AVFoundation), the same engine as
  `/usr/bin/say`. No microphone permission is needed (it is output only).
- Enhanced/Premium voices: *System Settings → Accessibility → Spoken Content → System voices*.
- From the terminal: `swift run sphere-cli say "ciao"` (uses `/usr/bin/say`).

### Aspetto (fonts)

In **Settings → Aspetto** choose **font and size** separately for user
and AI messages. "Sistema (default)" uses the system font; the
other entries are the installed fonts (PostScript names). The preview shows the
result immediately and the font is applied to the chat.

## 4. Installing and enabling modules

### From the GUI

1. **Modules** tab.
2. Drag a `.spheremodule` file (or `.sphereplug`, `.zip`) into the window,
   or press **Install module…** and select a file/folder.
3. The module appears in the list, **disabled**.
4. Turn on the **Enabled** switch: Sphere validates, starts the MCP process,
   performs the handshake and loads the tools.
5. Startup errors are shown in the banner and written to
   `~/Library/Application Support/Sphere/Logs/sphere.log`.

**Reveal plugins folder** opens the modules folder in Finder. You can also
manually copy a `.spheremodule` file there: it will be shown after *Refresh*.

### From the CLI

```bash
swift run sphere-cli modules install examples/hello-module
swift run sphere-cli modules tools com.sphere.examples.hello
swift run sphere-cli modules enable com.sphere.examples.hello
swift run sphere-cli modules disable com.sphere.examples.hello
swift run sphere-cli modules remove com.sphere.examples.hello
```

## 5. File access

The GUI has the **File Access** tab; the CLI has `grant`.

### Granting a path

- GUI: **Grant folder (RO)** or **Grant folder (RW)** and choose the folder.
- CLI: `swift run sphere-cli grant add ~/Projects rw`

### What a grant does

- `RO`: reading, listing, glob and grep allowed; writing denied.
- `RW`: writing/editing also allowed.
- `recursive`: covers the folder and all subfolders.
- Every allowed operation increments the grant's `read_count` or `write_count`.
- Every attempt (allowed or denied) is recorded in `access_events` and in the
  log. The **Access log** is in macOS Console style: `TIME | STATUS | DETAILS`,
  with `ALLOW`/`DENY` status, monospaced font and alternating colored rows.

### Revoking

- GUI: trash can next to the grant.
- CLI: `swift run sphere-cli grant remove <id>` (the id is shown by `grant list`).

### Built-in tools

The broker exposes more than plain read/write:

| Tool | Purpose |
|---|---|
| `fs_read` | Read text; optional `start_line`/`end_line`. |
| `fs_write` | Write text. |
| `fs_list` / `fs_glob` | List a folder / match globs. |
| `fs_grep` | Regex search with binary awareness, context lines, counts and `.gitignore` support (best-effort). |
| `fs_stat` | Size, mtime, mode and type sniffed from magic bytes. |
| `fs_read_bytes` | Hex/base64 slice of a binary file (max 4 KB). |
| `fs_edit` | Search/replace or unified diff (`apply-patch`) edit. |
| `fs_select` | JSON/YAML/plist path selector, or `lines:START-END` for text such as `Package.swift`. |
| `image_inspect` | Image format, dimensions, DPI, minimal EXIF and optional PNG thumbnail. |
| `git` | Read-only `status`, `diff`, `log`, `show`, `blame` in a granted path. |
| `system_info` | Date, OS, host, user and granted roots. |
| `clipboard_read` / `clipboard_write` | System clipboard as text. |
| `web_search` | DuckDuckGo HTML search results (subject to the ban list). |
| `exec` | Opt-in sandboxed command (argv allowlist, no shell, timeout, no network). |

`exec` is disabled by default. Enable it and edit the command allowlist in
**Settings → Tools**. Commands that can write require an `RW` grant; read-only
inspections work with `RO`. The child process runs under `sandbox-exec`, with
network denied and writes limited to the granted root; see
[PERMISSIONS.md](PERMISSIONS.md).

### Important note

The built-in filesystem broker (`sphere.filesystem`) is the only way to have
**authoritative** counters and RO/RW. A third-party MCP module that reads files
on its own cannot be confined per-path in a non-sandboxed app: for these modules the
grant is declarative/audit. See [PERMISSIONS.md](PERMISSIONS.md).

## Session numbers

Each session gets a stable progressive number shown as `#N` under its name.
The number is also shown in the file-access, network, tool and clipboard logs,
so every operation can be traced back to the session that produced it. Deleting
a session does not reuse its number; older log rows without session attribution
show `—`.

## Logs window

The **Logs** window is opened with:

- **Settings → Diagnostica → Apri log HTTP / Keychain / accessi file / rete /
  uso tool / clipboard**;
- the status-bar icons: folder, clipboard, globe and wrench.

It has a selector for **File Access / Network / Tools / Clipboard / HTTP /
Keychain** and shows the last 200 rows in the same console style. Database logs
include the session column; HTTP and Keychain are read from their log files.
The raw files remain available from **Apri cartella Logs**.

## Tools tab

The **Tools** tab lists every tool the AI can use, grouped by module/provider.
Every tool is **enabled by default**; use the switch to disable individual
tools, or the **Enable all** / **Disable all** buttons. Disabled tools are
removed from the catalog sent to the model and rejected if called anyway.
The list refreshes automatically and with the refresh button (useful after
installing or enabling a module).

`exec` also requires enabling sandboxed execution in **Settings → Tools**;
the note in its row reminds you.

The right pane of the **Tools** tab shows the global **tool usage log**
(`tool_calls`, last 200) with session number, status and a compact argument
preview.

## Clipboard

The **Clipboard** tab works like File Access:

- left: switches to allow/deny `clipboard_read` and `clipboard_write`, session
  read/write counters, and an optional local **preview** (default off, capped at
  2,000 characters; refreshing the preview is local and is not logged as an AI
  access);
- right: the global clipboard log (last 200, with `#N`).

## 6. Screen access

**Screen** tab.

1. **Request Screen Recording**: enables the macOS TCC permission. If the
   prompt does not appear, check *System Settings → Privacy & Security →
   Screen Recording*.
2. **Refresh windows**: lists the shareable windows.
3. **Allow** on a window: adds an internal consent for that
   window/app.
4. **Capture**: captures a PNG (saved in `Captures/` and shown in preview).

The equivalent CLI:

```bash
swift run sphere-cli screens list
swift run sphere-cli screens allow <windowId>
swift run sphere-cli screens capture <windowId>
```

**Why an internal allowlist?** macOS grants Screen Recording at the app
level, not per window. Sphere therefore applies a second check of its own:
default deny, explicit consent per window/bundle, revocation and
counters.

## 7. Internet access and bans

Sphere exposes a built-in tool to download http/https URLs. HTML content
is converted to text by default.

### Tool

- Name for the model: `sphere_web_web_fetch` (module `sphere.web`, tool
  `web_fetch`).
- Arguments: `url`, `format` (`text` or `raw`), `max_bytes`.
- `web_search` (query, `max_results`) uses DuckDuckGo's HTML endpoint and
  returns titles, URLs and snippets. Search requests are checked against the
  same ban list and recorded in the Network tab.
- Every request is recorded in the **Network** tab.
- Ban rules are checked **before** the request and again
  on the final URL after any redirects.

### Ban list

Default: allowed, unless rules are active. Rule types:

| Type | Example | Effect |
|---|---|---|
| URL | `https://example.com/api` | blocks URLs that start with the value |
| Domain | `example.com` | blocks the domain and its subdomains |
| IP/CIDR | `8.8.8.8`, `10.0.0.0/8` | blocks the literal or DNS-resolved IP |

### GUI

**Network** tab:

- field + type (URL / Domain / IP) + **Aggiungi** (Add) to create a rule;
- list of rules with enable/disable switch, block counter, delete;
- list of recent requests (allowed/blocked) in Console style:
  `TIME | STATUS | DETAILS`, `ALLOW`/`BLOCK` status, alternating rows.

The same events are mirrored in the **macOS unified log**
(subsystem `com.sphere.app`, category `audit`) and are visible in Console.app.

### CLI

```bash
swift run sphere-cli web https://example.com
swift run sphere-cli ban add domain example.com
swift run sphere-cli ban add ip 10.0.0.0/8
swift run sphere-cli ban list
swift run sphere-cli ban events
swift run sphere-cli ban remove <id>
```

## 8. Knowledge base

At this stage the `KnowledgeProvider` contract is defined and an in-memory
stub is active. The UI shows the active provider. The local RAG
implementation (FTS5 + embeddings) arrives in Phase 2.

## 9. CLI reference

| Command | Description |
|---|---|
| `sphere-cli init` | Initializes storage and prints the paths |
| `sphere-cli modules list` | Lists the installed modules |
| `sphere-cli modules install <path>` | Installs `.spheremodule`/`.sphereplug`/`.zip`/folder |
| `sphere-cli modules enable <id>` | Enables and starts a module |
| `sphere-cli modules disable <id>` | Stops and disables a module |
| `sphere-cli modules remove <id>` | Uninstalls a module |
| `sphere-cli modules tools <id>` | Lists the exposed tools |
| `sphere-cli grant list` | Grants with read/write counters |
| `sphere-cli grant add <path> [ro\|rw]` | Grants a path |
| `sphere-cli grant remove <id>` | Revokes a grant |
| `sphere-cli grant events` | Shows the latest access events |
| `sphere-cli screens list` | Lists the windows |
| `sphere-cli screens allow <windowId>` | Allows a window |
| `sphere-cli screens capture <windowId>` | Captures an allowed window |
| `sphere-cli key list` | Lists the saved API keys (without values) |
| `sphere-cli key set <provider> <key>` | Saves an API key |
| `sphere-cli key delete <provider>` | Removes an API key |
| `sphere-cli key import-keychain` | Imports the keys from the Keychain |
| `sphere-cli web <url>` | Downloads a URL through the web tool |
| `sphere-cli ban list` | Lists the ban rules |
| `sphere-cli ban add <url\|domain\|ip> <v>` | Adds a ban rule |
| `sphere-cli ban remove <id>` | Removes a ban rule |
| `sphere-cli ban events` | Shows the recent network requests |
| `sphere-cli models` | Lists the models of the active provider |
| `sphere-cli chat <prompt>` | Runs one agent turn with the active provider |

## 10. Where the data lives

```
~/Library/Application Support/Sphere/
  sphere.sqlite     sessions, messages, tool calls, modules, grants, audit
  config.json       provider, policy, additional module folders
  secrets.json      API keys (permissions 0600)
  Plugins/<id>/     installed modules
  Store/            original archives
  Captures/         PNG screenshots
  Logs/sphere.log   application audit log
  Logs/http.log     requests/responses to the providers (masked headers)
  Logs/keychain.log Keychain and secret store accesses
```

### API keys and Keychain

API keys are saved in `secrets.json` with `0600` permissions. The macOS
Keychain is used only for an optional **one-time import**.

Reason: the app is ad-hoc signed and the signature changes on every rebuild; the
Keychain ACL is tied to the signature, so reads begin to fail with
`errSecUserCanceled (-128)` and the provider responds 401. The file store avoids
the problem.

- Import: **Settings → Diagnostica → Importa chiavi dal Keychain** (Import keys from the Keychain) (it may ask for
  authorization once) or `sphere-cli key import-keychain`.
- Alternatively, re-enter the key with **Save key**.

## 11. Network diagnostics

In **Settings → Diagnostica** you can:

- enable **Log completo HTTP** (Full HTTP log) (it includes the request bodies; the
  `Authorization`/`x-api-key` headers are always masked);
- open `Logs/http.log`, `Logs/keychain.log` and the Logs folder;
- import the keys from the Keychain.

For each request the log shows method, URL, status, masked headers and, in
case of an error, the full body returned by the provider. This lets you
distinguish immediately:

- **missing key** → the log shows `request sent WITHOUT API key` and the
  `Authorization` header is not there;
- **key present but wrong** → the header is there (masked) and the 401 body explains
  the reason;
- **key present but unreadable** → `Logs/keychain.log` shows
  `errSecUserCanceled (-128)` or `errSecInteractionNotAllowed`.

## 12. Troubleshooting

- **"No LLM provider configured"**: select an active provider in Settings.
- **HTTP 401**: open `Logs/http.log`. If the `Authorization` header is missing, the
  key has not been read: re-enter it with **Save key** or import it from the
  Keychain. Also check the base URL and model.
- **Module does not start**: check that the executable (`python3`, `node`, …) is in the
  PATH and that `module.json` has a valid `transport.command`.
- **Black/empty screenshot**: the Screen Recording permission is missing, or the
  window is not in the allowlist.
- **Write denied**: the grant is `RO`; change it to `RW` from the File Access tab.
- **Web blocked**: check the **Network** tab; the rule that blocked it is in
  `ban events` / in the log. Redirects to banned URLs are blocked after the
  request.
- **Full reset**: close the app and delete
  `~/Library/Application Support/Sphere/` (you lose sessions, grants and installed
  modules).
