# Acceptance with Relay Desk

Relay Desk's automation transport was designed so that acceptance claims rest on evidence, not on reading a status field. Metadata's job is to make evidence attributable: which project, which actor identity, which panel, which native window. This file covers how to phrase what that evidence proves.

## Three evidence tiers

Every acceptance claim carries exactly one tier, and a claim never rises a tier on its own:

- **Statically reviewed** — a human or agent read the diff. Establishes intent and obvious defects; establishes nothing at runtime.
- **Automatically tested** — a check you can name and that actually ran passed against the code: `flutter test` for the app, or the offline CLI protocol tests for whichever CLI implementation you ran. Cite the exact target rather than "the tests". Establishes that the code does what that check asserts, in a build the user may not be running.
- **Runtime-verified** — behavior was actually observed, with the source of that observation named. Metadata reads need the opt-in debug service; a live native control tool can supply authorized UI evidence on its own. What stays out of reach either way is inferring a business pass from metadata fields.

Report the three separately. A passing dev-build test suite is evidence for *automatically tested* and nothing more, even when the release build is broken. No test suite, and no test suite passing on a different build than the one in use, promotes a claim to runtime verification.

The CLI you used is part of the evidence, so name it: the standalone `relayctl` executable, or the developer source run. Both speak the same P0 protocol, and a claim rests on the response you actually captured — not on which binary produced it, and not on the CLI's existence. Reaching the executable at all says nothing about whether the app instance it talks to is the one under test; that comes from `sessions` and `capabilities`.

## Gate every signal on capability detection

Before promising a signal, check `capabilities.operations` and `capabilities.limitations`. A signal whose capability is absent is reported as **unverified, needs <capability>**, followed by what evidence would settle it. Stages that add DOM reads, snapshots or network capture arrive later; until then the honest report is the gap.

## Bind targets before collecting evidence

Use metadata to pin the exact subject: the `projectId` under test, the identity acting, the resident panel for that identity, and the `nativeViewId`/`windowId` the evidence belongs to. Two recurring traps:

- Reading a panel as if it were a window — the panel is the WebView, the window is its native container.
- Reading a `selected` identity as the acting one — selection is UI state and lags intent; confirm the actor separately.

Cite these IDs alongside any evidence you gather, otherwise a later reader cannot tell whose result they are looking at.

## Role mapping is user-defined

Common setups label Relay Desk identities by business role (`普通用户`, `会员`, `运营`, `测试账号`) and map them to niucloud accounts by hand. That mapping is a **convention of the workspace, not a fact the metadata carries**. Identity names are locating labels.

Any stage that mutates business state must first establish which account is actually logged in, from business-visible evidence (the account page, the session on the server side), and report the mismatch when a label and the real account disagree. P0 reads metadata and does not verify which business account a panel is logged into, so record the intended mapping as an assumption to re-verify rather than as a verified fact.

## Signals metadata cannot establish

These stay unverified while the transport reads metadata only — do not let a plausible status field stand in for them:

- **Playback resume timing** — whether playback resumed at the stored position.
- **Valid watched duration** — whether a watch actually counted.
- **Gift eligibility** — whether the account qualified.
- **Successful claim** — whether the server recorded the claim.

A screenshot would not settle the last two either: eligibility and claim are server-side records.

## Requirements for the stages that will settle them

These are acceptance requirements to design future evidence against, not capabilities you can use now:

- Media expectations are **tolerance-based**: compare against time tolerance, not exact equality, and bound the number of retries.
- Watch duration and playback position are **separate reads** — one metric cannot stand in for the other.
- **Server cumulative watch-time semantics** are authoritative: client-side timers are advisory.
- Resume acceptance observes three things together: stored history position, actual playback position, and the bounded retry count.
- Gift eligibility and claim results come from **server records**, tagged with the acting account.

## Report shape

For each item, three lines at most:

1. The claim, with its tier from the three above.
2. The evidence source: command and response ID (plus which `relayctl` you ran), the name of the check that ran, or the file and lines reviewed.
3. Anything unverified, named together with the capability that would settle it.
