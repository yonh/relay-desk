---
name: relay-desk
description: Inspect a running Relay Desk app — current project, identity, panel, native window, saved workspace — through the standalone relayctl CLI, and grade code acceptance against real evidence. Use when the user asks to inspect Relay Desk, find which identity/panel/window is current, capture a panel screenshot, or sample a page's media playback state — and for code acceptance against real evidence. Scoped to Relay Desk on macOS; the transport is read-only metadata plus explicit-ID panel screenshot and media-state sampling — no page DOM, caller script evaluation or network capture.
---

# Relay Desk inspection

Relay Desk is a Flutter macOS host whose panels are WKWebViews. `relayctl` reaches an opt-in local service inside a running instance and returns metadata about projects, identities, panels, AppKit NSWindows and saved workspaces. Every operation here is read-only.

## Resolve the executable once per run

`relayctl` is a self-contained macOS executable with the Dart runtime compiled in, so running it needs **no Python, Dart or Flutter**. Take the first candidate that applies:

1. **`$RELAY_DESK_CLI`** — a path the user chose explicitly. If it is set but missing or not executable, that is an **error to report, not a reason to fall through**: a bad explicit path must not silently become a different CLI.
2. **`relayctl` on `PATH`.**
3. **The repo build for this host architecture**, under the repo root (`$RELAY_DESK_REPO` when set, otherwise `/Users/yonh/workspaces/flutter/relay-desk`): `build/relayctl/macos-arm64/relayctl` or `build/relayctl/macos-x64/relayctl`, picking the folder matching `uname -m` (arm64 or x86_64 respectively).
4. **Developer source fallback, only when a Dart SDK is available**: `dart tool/relayctl.dart`, run from the repo. This needs both a checkout and a Dart SDK, so it is a developer convenience — never present it as something a third party can rely on.

There is no Python fallback. When nothing resolves, say so plainly and give the two real options: a developer runs `bash tool/build_relayctl.sh`, or you obtain the archive matching the host architecture (`relayctl-macos-arm64.tar.gz` / `relayctl-macos-x64.tar.gz`, each unpacking into a `macos-arm64` / `macos-x64` folder). Do not ask a third-party user to install Flutter, Dart or Python.

Each build is for its own host architecture — no universal binary, no cross-compile — and is an unsigned local/internal artifact. Building inside the user's repo writes into their working tree, so only do it when the task authorizes that.

Resolve once and hold the result for the whole run. Prefer the **absolute path** of the executable (or `$RELAY_DESK_CLI` / the `dart tool/relayctl.dart` prefix) so later query commands are independent of the working directory. Inside an unpacked `macos-arm64` / `macos-x64` directory, write it as `./relayctl`.

```bash
relayctl --help      # authoritative op list and selector flags
relayctl sessions    # offline: descriptors with file, pid, endpoint
```

Read `--help` for the operation list instead of relying on a remembered one; the ops grow as later stages land.

The service exists only in a macOS debug build compiled with `RELAY_DESK_AUTOMATION=true`, and there is no user-facing switch for it yet. Developers can use `flutter run -d macos --dart-define=RELAY_DESK_AUTOMATION=true`; recipients can launch a developer-provided opt-in app build. The CLI alone does not enable the interface in an installed release build. Match your expectations against the `sessions` and `capabilities` you actually reached.

## Read in this order

1. **`sessions`** — live instance descriptors. Completion: you hold one session file path, or you have a stated reason none exists.
2. **`capabilities`** — `readOnly`, `engine`, `operations`, `limitations`. Completion: you can quote which operations this build serves and which are absent.
3. **`state`** — current selection plus native focus in one capture. Completion: exact `projectId`, `identityId`, panel, `windowId`, `workspaceId` bound, and `selectionConsistent` read.
4. **Exact-ID follow-ups** — pass the IDs step 3 gave you (`--project`, `--identity`, `--window`, `--workspace`) when you need details or a stable target. Completion: every claim you make names the ID it came from, or is reported as unavailable.

Discovery only works with exactly one running instance. With several, ask which one and select it with the global flag placed **before the operation** — `relayctl --session FILE state` — or the environment variable `RELAY_DESK_SESSION`.

Absence of a session is a result to report. Starting or replacing an opt-in app requires task authorization; honor an explicit authorization when present and avoid restarting the user's active instance on your own initiative. `relayctl` neither starts nor restarts the app.

## Credential discipline

Session descriptor files carry a bearer token. Pass the file path and keep its contents out of output, logs and commits — `sessions` prints only file, pid and endpoint, and that is the shareable part. Never cat a descriptor or echo its token.

## What the fields mean

- A **panel** is a WebView bound to one identity inside a workspace layout; an **NSWindow** is the native window hosting it. Embedded and detached presentation are the same running instance. Names and IDs are not interchangeable.
- **Selected** identity is the Flutter UI selection; **focused** identity is which WKWebView owns the native `firstResponder`. They differ routinely, and focus is null while the address bar or sidebar holds focus.
- **No current selection is a valid answer**: the single-item fields inside `data` are null (`data.project`, `data.identity`, `data.panel`, `data.window`) and list reads scoped to the current project come back empty, while `not_found` marks an explicit unknown ID. Unfiltered lists still describe reality: `panels` and `windows` keep reporting resident panels and every NSWindow. When the app is inactive, `currentWindowId` is null even though AppKit keeps its key flag.
- `selectionConsistent: false` means the selected identity has no resident panel, or its identity is missing or belongs to a project other than the current one; report that as stale selection instead of attributing it to the new project. A named workspace left over from the previous project is a separate case — it returns `workspaceId: null` and leaves `selectionConsistent` alone.
- `sharedSession` / `isIsolated: false` means the identity is **not** isolated. Identity and panel names are locating labels, not proof of which business account is logged in.

## Screenshot artifacts

`relayctl screenshot --identity <uuid> --output <path>` writes one PNG per call — nothing is captured automatically. Keep every screenshot for a task inside a dedicated artifact directory instead of scattering files in `/tmp`:

- Pick the directory **once per task**: `~/Library/Caches/relay-desk/agent-evidence/<task-id>/` by default (`<task-id>` is any stable label, e.g. `issue-13`); honor an explicit user-specified path when given. The directory path is metadata, not a credential.
- Always pass an absolute `--output` inside that directory; the flag stays mandatory — don't change invocation style for this.
- Reuse fixed names: `current.png` for routine looks (each capture overwrites it, file count stays flat); `before.png` / `after.png` or a few meaningful fixed names for paired evidence. Do not build a polling screenshot library nobody asked for.
- In your report, state the directory, file count and total size. A failed capture gets no fake success entry and no pointless retries keeping junk copies.
- Copy into a repo evidence path only when the task requires formal archived evidence; never auto-commit business screenshots.
- Cleanup is scoped to files this task owns: at task end, remove your own temporary look-only shots; keep evidence that must persist. Never sweep other files under `/tmp`, never touch an active task's directory or archived evidence.

## Media sampling

`relayctl media --identity <uuid>` samples the page in that identity's panel with a fixed read-only probe — never caller-supplied JavaScript. It returns `sampledAt`, identity/view/window bindings, and a `frames[]` walk:

- Each frame reports `label` (`main`, `f0`, `f0.f1`, ...), `depth`, sanitized `url`, `reachable`, and a `media[]` list of `video`/`audio` state: `currentTime`, `duration` + `durationKind` (`finite`/`live`/`unknown` — non-finite durations are `null`, never invalid numbers), `paused`, `ended`, `seeking`, `readyState`, `playbackRate`, `seekable` ranges, and MediaError `error.code`.
- Same-origin iframes are recursed into; cross-origin frames report `reachable:false, reason:unavailable` — that is "cannot observe", never "no media". A reachable frame with `mediaCount:0` genuinely has no media elements.
- Budgets (depth 4, 32 frames, 32 media/frame) truncate oversized documents; top-level `truncated`/`skippedFrames`/`depthLimitSkipped` and per-frame `mediaSkipped` flag what was cut — do not read a truncated result as complete.
- `sampledAt` marks when the single probe pass finished; media fields move while sampling, so two samples differ naturally. Compare positions with the business's own tolerance, never float equality.
- Fields prove **player state only** — they cannot prove effective watch time, gift eligibility, or which business account is logged in.

## Scope

The current stages expose a read-only panel screenshot plus metadata and media-state sampling; they expose no page DOM, script evaluation, navigation, synthetic input, console, network or CDP; `capabilities.limitations` reports these as false. Ask for those signals from a native control tool (screen, click, keyboard) only when the task authorizes UI work and those tools exist — a `read only` request scope keeps the whole session read only, including native channels.

Metadata alone never establishes that a business behavior passed. For evidence tiers, role mapping, and the playback/gift signals metadata cannot prove, read [references/acceptance.md](references/acceptance.md) when the task is grading acceptance rather than reading metadata.
