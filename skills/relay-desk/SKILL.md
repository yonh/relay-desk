---
name: relay-desk
description: Inspect a running Relay Desk app — current project, identity, panel, native window, saved workspace — through the standalone relayctl CLI, and grade code acceptance against real evidence. Use when the user asks to inspect Relay Desk, find which identity/panel/window is current, capture a panel screenshot, or sample a page's media playback state — and for code acceptance against real evidence. Scoped to Relay Desk on macOS; the transport is metadata plus explicit-ID panel screenshot, media-state and error sampling, DOM summary/find — caller script evaluation and network capture are never served.
---

# Relay Desk inspection

Relay Desk is a Flutter macOS host whose panels are WKWebViews. `relayctl` reaches an opt-in local service inside a running instance and returns metadata about projects, identities, panels, AppKit NSWindows and saved workspaces. Operations are read-only except the whitelisted write ops marked as such.

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

## Page error buffer

`relayctl errors --identity <uuid>` drains the page-side buffer of `error` and `unhandledrejection` events in that identity's panel (issue #17). Views created in an automation build carry the listeners from document start; the buffer lives inside each document, so:

- `collectedAt` marks when recording started — nothing before that exists; `bufferId` changes per navigation and per frame, `count`/`overflow` flag entries and drops (cap 200, bounded fields).
- `installed:false` means the page was created without the capture flag — "cannot observe", never "no errors". Same-origin iframes get their own buffer; cross-origin frames are `reachable:false`.
- Rejection reasons are type-tagged (`[object Object]`), never serialized payloads; frame `url` and entry `source` are URL-sanitized like all transport fields.
- The drain is read-only and does not clear the buffer — repeat calls on the same document return the same entries; compare `bufferId`+`count` for increments.

## DOM summary

`relayctl dom --identity <uuid>` (issue #20) walks the page with a fixed read-only probe — never caller-supplied JavaScript. It returns `documentId` (per-probe nonce — every call produces a fresh one, even for an unchanged page), `title`, sanitized `url`, and a `frames[]` walk:

- Each frame reports `label` (`main`, `f0`, …), `depth`, `title`, `text` (bounded visible text), `elementCount`, and an `elements[]` list of semantic nodes: `ref`, `tag`, `role`, `label`, sanitized `href`.
- A `ref` is `<frameIndex>.<document position>` — the element's `querySelectorAll('*')` preorder slot within its own frame's document. It is stable within that probe result; it **means nothing across calls or after DOM changes** — re-probe instead of assuming stability.
- Same-origin iframes are recursed into; unreachable frames report `reachable:false` — "cannot observe", never "empty frame". A loading page legitimately returns empty frames — that is the honest loading state, not an error.
- Budgets (depth 8, 16 frames, 300 elements/frame, 80-char labels, 2000-node scan) truncate oversized documents; top-level `truncated`/`skipped` flag what was cut — never read a truncated result as complete.
- The probe never returns scripts, input values, or password fields — it is a summary for locating elements, not a DOM dump.

## DOM element find

`relayctl dom_find --identity <uuid> --text|--role|--selector <v>` (issue #21) searches the rendered page with a fixed native probe — the criteria travel as JSON data, never as caller JavaScript:

- Exactly one criterion is required: `--text` (normalized visible-text match; `--match exact|contains`, default contains; deepest matches only, so hits are operable leaf elements), `--role` (explicit `role` attr or tag-implied role; `--name` narrows by accessible name), or `--selector` (CSS selector; a malformed one is `invalid_selector`).
- `--frame <label>` restricts to one frame (`main`, `f0`, …): an unknown label is `not_found`, a cross-origin one is `frame_unreachable` — never search-blind spots silently.
- Results are `documentId` + `matchCount` + a bounded `matches` list (`ref`, `frame`, `tag`, `role`, `label`, `visible`, `disabled`) with `truncated` on overflow. **Multiple matches stay a list — never report the first as chosen.** Zero matches is `not_found`, not an empty success.
- A `ref` is `<frameIndex>.<document position>`; it identifies one element only while that document is unchanged — a navigation or DOM mutation shifts positions, so re-find instead of assuming stability. (Inspecting one ref is the dom_inspect stage.)
- The op only reads — it never clicks, types, or returns input values.

## DOM element inspect

`relayctl dom_inspect --identity <uuid> --ref <f.p> --document-id <id>` (issue #22) resolves one ref issued by `dom`/`dom_find` and reports the element's live state: `tag`, `role`, `name`, `visible`, `disabled`, `checked`, `selected`, `focused`, whitelisted `attrs` (id/class/type/href/src/…—never values or innerHTML), and `rect` in **`frame` coordinate space** (viewport-relative CSS pixels of the element's own frame; scroll and iframe offsets are not composed).

- `--document-id` is required: the probes stamp `__rdDocNonce`/`__rdRef` expandos so a changed document, reordered position or replaced element is `stale_element` — re-probe, never reuse an old ref. A position that was never issued is `not_found`; a cross-origin frame is `frame_unreachable`.
- A failed navigation can leave `webView.url` pointing at the failed target while the old document survives — the ref then still resolves honestly to the old element.
- Read-only: no clicks, no input, no attribute writes.

## Project activation (write op)

`relayctl activate_project --project <uuid>` (issue #31) switches the app to an existing project — the same call the sidebar makes, so layout restore and panel sync are the UI's own. It is the first whitelisted **write** operation: `capabilities.readOnly` is now `false`, and writes are listed under `writeOperations` (reads stay under `operations`).

- `--project` is required — never a project name, never the current selection.
- Activation is asynchronous in the app: the response reports `selectedProjectId` (provider), `workspaceSelectedProjectId` (workspace marker, lags on restore), `frameSettled` and `settled`. `settled:false` means "still converging — re-query `state`", not failure and not success.
- `panels` in the response is the resident set at that moment and can still list the previous project's panels; `selectedPanelId`/`focusedIdentityId` are reported as-is — UI selection, native focus and the switch's end state are three different signals.
- Unknown projectId → `not_found`; a concurrent activation → `panel_busy` (409), retry after it finishes — never read a busy as the other project's state.
- After activation, `state`/`panels`/`screenshot`/`media`/`errors` address the new project's identities as usual.

## Panel open (write op)

`relayctl open_panel --identity <uuid>` (issue #32) opens (or re-surfaces) the panel of an existing identity — the same `WorkspaceController.ensurePanel` the workspace sync calls, never a second WebView lifecycle:

- `--identity` is required and must belong to the **currently activated** project: an identity of another project is `project_not_active` (409) — activate that project first, open_panel never switches implicitly.
- Idempotent: re-opening an already-resident panel returns `alreadyOpen: true` without disturbing it.
- Opening is asynchronous: the response reports `alreadyOpen`, `nativeViewId`, `windowId`, and `viewReady`. `viewReady: false` means the platform view registered but the state hasn't transitioned yet — re-query `state`/`panel`, don't retry the open.
- Unknown identityId → `not_found`; a concurrent open on the same identity → `panel_busy` (409).
- After it returns, `screenshot`/`media`/`errors`/`dom` can address the panel's view as usual.

## Scope

The current stages expose a read-only panel screenshot plus metadata, media-state sampling, the page error buffer, a DOM summary and DOM find, plus the write operations `activate_project` and `open_panel`; they expose no element inspect, script evaluation, navigation, synthetic input, console, network or CDP; `capabilities.limitations` reports these as false. Ask for those signals from a native control tool (screen, click, keyboard) only when the task authorizes UI work and those tools exist — a `read only` request scope keeps the whole session read only, including native channels.

Metadata alone never establishes that a business behavior passed. For evidence tiers, role mapping, and the playback/gift signals metadata cannot prove, read [references/acceptance.md](references/acceptance.md) when the task is grading acceptance rather than reading metadata.
