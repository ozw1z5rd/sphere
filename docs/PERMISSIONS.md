# Permission model

Sphere separates two sensitive surfaces: **files** and **screen**. In both
cases the principle is: default deny, explicit consent, audit.

## File access

### How it works

1. The user grants a path (`RO` or `RW`, recursive) from the **File Access** tab
   or with `grant add`.
2. The **built-in filesystem broker** (`sphere.filesystem`, in-process MCP)
   exposes `fs_read`, `fs_write`, `fs_list`, `fs_glob`, `fs_grep`, `fs_stat`,
   `fs_read_bytes`, `fs_edit`, `fs_select` and `image_inspect`. Read-only git
   (`sphere.git`) and system/clipboard tools (`sphere.system`) use the same
   grant checks.
3. Every request goes through `PermissionEngine`:
   - normalizes the path (`~`, relative paths, symlinks);
   - checks that it falls within a grant;
   - checks that writes have an `RW` grant;
   - records an event in `access_events`;
   - increments the grant's `read_count`/`write_count`.
4. On denial the tool returns an error and the event is still recorded
   (`allowed = 0`).

### Why the broker is central

Counters and RO/RW are **authoritative only if IO goes through the broker**.
If an external MCP module reads files on its own, Sphere cannot intercept it in
a non-sandboxed app.

### Declared limitation

For third-party MCP modules:

- Sphere passes them only the paths declared in the manifest (via `cwd`/`env`),
  it does not grant per-path OS permissions;
- the manifest is declarative and shown to the user;
- the audit records process startup and tool calls, not internal syscalls.

Real per-module enforcement will arrive in Phase 2 with a `sandbox-exec`
profile (or sandboxed helper) to limit the child process's writes to the
granted paths.

## Sandboxed exec

`sphere.exec` is the most powerful built-in tool and is **disabled by
default**. When enabled from **Settings → Tools**:

- commands are passed as an `argv` array (never through a shell);
- the command must match the user's allowlist (prefix match, e.g. `git status`);
- the working directory must be inside a granted root;
- read-only commands (`git status`, `ls`, `cat`, `rg`, …) need an `RO` grant;
  commands that may write need an `RW` grant;
- a hard timeout (default 30 s, max 120 s) and output cap apply;
- the child runs under `sandbox-exec` with `network*` denied and `file-write*`
  limited to the granted root, `/private/tmp`, `/private/var/folders` and
  `/dev/{null,stdout,stderr,zero}`;
- `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.docker`, `~/.netrc` and Sphere's own
  Application Support folder are read-protected;
- the environment is scrubbed of secret-looking variables and `HOME` points to
  a temporary directory.

Limitations: `sandbox-exec` is deprecated; reads outside the denied paths are
still possible, so review the allowlist and keep grants narrow. The sandbox
protects writes and network, not confidentiality of every readable file.

### Best practices

- Grant the narrowest possible folder, not `~`.
- Use `RO` until you need to write.
- Keep the exec allowlist minimal; prefer read-only commands and build/test
  prefixes you actually use.
- Periodically check the counters and the timeline: unexpected access is a
  signal.
- Revoke grants that are no longer needed.

### Paths protected by macOS

Even without App Sandbox, some directories (Desktop, Documents, Downloads, etc.)
are protected by TCC: the first read may require system consent. Sphere does not
bypass TCC.

## Screen access

### Two levels

1. **macOS TCC — Screen Recording**: it is granted at the **app** level, not
   per window. Without it, captures come back empty/denied.
2. **Sphere's internal allowlist**: after the TCC permission, Sphere keeps a
   separate consent per individual window/app.

### Flow

1. `Request Screen Recording` activates/verifies the TCC permission.
2. `Refresh windows` lists the shareable windows.
3. `Allow` creates a `ScreenGrant` (per window or per bundle id).
4. `capture_window` checks the allowlist **before** capturing; if consent is
   missing, it denies.
5. Every capture increments `capture_count` and writes the audit.

Default: **deny**. An app not present in the allowlist cannot be captured
through Sphere.

### Notes

- Per-window consent is an application-level policy: it does not prevent other
  apps (or the CLI) from using ScreenCaptureKit. It is the most that can be
  achieved without special sandbox/entitlements.
- You can revoke a consent from the Screen tab (trash can).
- Captures end up in `Captures/`; delete them if they contain sensitive data.

## Clipboard access

`clipboard_read` and `clipboard_write` are system-wide (not path-scoped). Every
successful or denied invocation is recorded in `clipboard_events` with the
session, operation, detail and result; the status bar shows a per-session
counter and the Tools tab shows the log. Use the Tools tab to disable either
tool.

## Internet access

The `web_fetch` tool is a built-in provider (`sphere.web`). The network policy
is **default allow** with a user-managed **ban list**:

- **URL**: blocks prefixes (`https://example.com/api`).
- **Domain**: blocks the domain and subdomains.
- **IP/CIDR**: blocks literal or DNS-resolved IPs; supports IPv4 CIDR.

Checks:

1. before the request;
2. on the final URL after any redirects;
3. every request (allowed or blocked) is recorded in `network_events`;
4. every block increments the rule's counter.

The tool does not execute JavaScript and does not use cookies/cache (ephemeral
session). Content is limited by size (`max_bytes`, default 200 KB) and HTML
bodies are converted to text unless `format: raw`.

## Simplified threat model

| Risk | Current mitigation | Future phase |
|---|---|---|
| Module reads non-granted files | Broker for modules that use it; audit | per-module sandbox-exec |
| Exec writes outside the grant | `sandbox-exec` write deny + RW grant check | dedicated helper |
| Exec network access | `sandbox-exec` `deny network*` | — |
| Module captures the screen secretly | It has no access to the internal screen tools | sandboxed helper |
| Path traversal / symlink | Normalization and prefix comparison | dedicated tests |
| API key in plaintext | Keychain | — |
| Malicious module at install | Disabled by default, consent, Gatekeeper | Ed25519 signature + catalog |
