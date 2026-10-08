#!/bin/bash
# Relay Desk update installer. Bundled inside the main app (signed/notarized
# with it) and launched via `/usr/bin/open -n`, which spawns it outside the
# main app's sandbox.
#
# LaunchServices drops `--args` argv for launch requests issued by a
# sandboxed process (verified on macOS 26: the stub receives only argv[0]),
# so runtime values arrive in a handoff file the app writes next to the
# tag staging dir:
#   <Application Support>/updates/handoff.params
# one `KEY=value` line per parameter — parsed field-by-field, never eval'd.
# argv remains accepted as a fallback for manual runs:
#   $1  parent PID (the running Relay Desk process)
#   $2  update staging root  (<Application Support>/updates/<tag>)
#   $3  staged .app path     ($ROOT/payload/<name>.app)
#   $4  target .app path     (the installed bundle to replace)
#   $5  downloaded archive   ($ROOT/package.zip — deleted on success)
set -u
PARENT="${1:-}"
ROOT="${2:-}"
STAGED="${3:-}"
TARGET="${4:-}"
ARCHIVE="${5:-}"
HANDOFF_FILE=""
if [ -z "$PARENT" ]; then
  # The sandboxed app writes the handoff inside its container; a
  # non-sandboxed build would use the plain Application Support dir.
  # Freshness is checked PER candidate inside the loop — a stale file in
  # one location must not shadow a live handoff the other build wrote.
  now=$(date +%s)
  for c in \
    "$HOME/Library/Containers/com.example.relayDesk/Data/Library/Application Support/com.example.relayDesk/updates/handoff.params" \
    "$HOME/Library/Application Support/com.example.relayDesk/updates/handoff.params"; do
    [ -f "$c" ] || continue
    # Stale handoff: only trust a file written in the last 10 minutes — a
    # replayed/planted params file must not drive destructive swaps later.
    mtime=$(stat -f %m "$c" 2>/dev/null || echo 0)
    [ $((now - mtime)) -gt 600 ] && continue
    HANDOFF_FILE="$c" && break
  done
  if [ -n "$HANDOFF_FILE" ]; then
    # `|| [ -n "$line" ]` keeps a final line that has no trailing newline —
    # plain `read` would drop it and the last param would come out empty.
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        PARENT=*)  PARENT="${line#PARENT=}";;
        ROOT=*)    ROOT="${line#ROOT=}";;
        STAGED=*)  STAGED="${line#STAGED=}";;
        TARGET=*)  TARGET="${line#TARGET=}";;
        ARCHIVE=*) ARCHIVE="${line#ARCHIVE=}";;
      esac
    done < "$HANDOFF_FILE"
    unset line
  fi
fi
: "${PARENT:?pid}" "${ROOT:?root}" "${STAGED:?staged}" "${TARGET:?target}" "${ARCHIVE:?archive}"
# Containment checks on file-sourced params: PID numeric; ROOT must be an
# updates/<tag> dir; payload and archive must sit inside it; only *.app
# bundles may be replaced (the target is wherever the running app was
# installed, so it is not bounded to a fixed directory).
case "$PARENT" in *[!0-9]*|"") exit 0;; esac
case "$ROOT"   in */updates/?*) ;; *) exit 0;; esac
case "$STAGED" in "$ROOT"/*) ;; *) exit 0;; esac
case "$ARCHIVE" in "$ROOT"/*) ;; *) exit 0;; esac
case "$TARGET" in *.app) ;; *) exit 0;; esac
MARKER="$ROOT/helper.started"
ABORT="$ROOT/helper.abort"
ABORTED="$ROOT/helper.aborted"
LOCK="$ROOT/helper.lock"
PAYLOAD="$ROOT/payload"
BACKUP="$TARGET.relay-backup"
OWN_LOCK=0
# Self-heal on abnormal exit: if we die after parking the old bundle but
# before a successful ditto, put it back. EVERYTHING here — restoring the
# backup included — requires actually holding the lock: a second helper
# that lost the mkdir race must never mutate TARGET/BACKUP, or its EXIT
# trap would resurrect the old bundle under the lock-holder's ditto and
# merge old+new files into one corrupt app.
cleanup() {
  if [ "$OWN_LOCK" = 1 ]; then
    if [ -d "$BACKUP" ] && [ ! -d "$TARGET" ]; then
      mv "$BACKUP" "$TARGET" 2>/dev/null || echo "rollback-failed" > "$ABORTED"
    fi
    rm -rf "$LOCK"
  fi
  return 0
}
trap cleanup EXIT
touch "$MARKER"
# Wait for the main app to exit (max ~120s), standing down early if the
# app cancelled the hand-off after this helper launched late.
for i in $(seq 1 600); do
  [ -f "$ABORT" ] && exit 0
  kill -0 $PARENT 2>/dev/null || break
  sleep 0.2
done
sleep 1
# Never swap a live app: the parent may be gone but the user could have
# relaunched it in the gap — pgrep catches ANY running instance. The hit
# reason goes into helper.aborted so a silent abort is diagnosable.
if [ -f "$ABORT" ] || kill -0 $PARENT 2>/dev/null; then
  echo "parent-alive-or-aborted" > "$ABORTED"
  exit 1
fi
if pgrep -f "$TARGET/Contents/MacOS/" >/dev/null; then
  echo "instance-running" > "$ABORTED"
  exit 1
fi
# Single-swapper lock: a second helper reaching this point exits quietly
# (both saw a dead parent; only one may mutate the target). Ownership is
# recorded by PID inside the lock — matching a live helper by script path
# was wrong: two different installs have different paths and would evict
# each other's LIVE lock. A lock whose recorded owner is dead (or missing
# past a grace window for a just-created lock) is a crash leftover —
# evict it and take over, otherwise a SIGKILLed helper wedges updates.
if ! mkdir "$LOCK" 2>/dev/null; then
  LPID="$(cat "$LOCK/pid" 2>/dev/null || true)"
  case "$LPID" in
    ''|*[!0-9]*)
      # No recorded owner: a fresh lock is still being initialized by its
      # creator — only an aged one counts as orphaned.
      LAGE=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
      [ "$LAGE" -lt 10 ] && exit 0
      ;;
    *)
      kill -0 "$LPID" 2>/dev/null && exit 0
      ;;
  esac
  # Reclaim the orphan atomically: park it under a per-process name, then
  # rebuild — a plain rm+mkdir would let a concurrent helper delete the
  # lock we just created and slip into the swap with us.
  CLAIM="$LOCK.stale.$$"
  mv "$LOCK" "$CLAIM" 2>/dev/null || exit 0
  rm -rf "$CLAIM"
  mkdir "$LOCK" 2>/dev/null || exit 0
fi
echo $$ > "$LOCK/pid"
OWN_LOCK=1
# Crash recovery FIRST: a previous helper killed after parking the old
# bundle left TARGET missing and BACKUP as the only runnable copy —
# resurrect it before `rm -rf` below can destroy the sole working app.
if [ ! -d "$TARGET" ] && [ -d "$BACKUP" ]; then
  mv "$BACKUP" "$TARGET" 2>/dev/null || { touch "$ABORTED"; exit 1; }
fi
rm -rf "$BACKUP"
# If the old bundle exists, moving it aside MUST succeed — continuing with
# the old bundle in place would merge old+new into a corrupted app.
if [ -d "$TARGET" ]; then
  mv "$TARGET" "$BACKUP" || { touch "$ABORTED"; exit 1; }
fi
if ditto "$STAGED" "$TARGET"; then
  # TOCTOU re-check: the window between the early pgrep and this destructive
  # step is the whole ditto — a relaunch inside it must roll back instead of
  # deleting the running instance's bundle.
  if pgrep -f "$TARGET/Contents/MacOS/" >/dev/null; then
    rm -rf "$TARGET" && mv "$BACKUP" "$TARGET"
    echo "instance-running-late" > "$ABORTED"
    exit 1
  fi
  xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
  rm -rf "$PAYLOAD" "$ARCHIVE" "$MARKER" "$ABORT"
  [ -n "$HANDOFF_FILE" ] && rm -f "$HANDOFF_FILE"
  # Delete the backup only after the new app actually launches — if open
  # fails, BACKUP stays on disk for manual recovery (L2 sweep handles it).
  open "$TARGET" && rm -rf "$BACKUP"
  # The lock covers EVERY mutation including the backup delete — release
  # it only here at the end so a second helper can never slip in while a
  # half-finished swap still needs the rollback copy.
  rm -rf "$LOCK"
  OWN_LOCK=0
else
  # Move the payload out of the swept staging dir FIRST — the relaunched
  # app's own startup sweep would delete it before we get here otherwise.
  TAG=$(basename "$ROOT")
  DEST="$HOME/Downloads/RelayDesk-$TAG"
  rm -rf "$DEST"
  mv "$PAYLOAD" "$DEST" 2>/dev/null
  rm -rf "$MARKER"
  [ -n "$HANDOFF_FILE" ] && rm -f "$HANDOFF_FILE"
  # Roll the old version back while still holding the lock: ditto may have
  # left a partial bundle, so the leftover target must be removed before
  # mv — rename into a non-empty dir fails and would nest the backup
  # inside the broken app.
  if [ -d "$BACKUP" ]; then
    rm -rf "$TARGET" && mv "$BACKUP" "$TARGET"
  fi
  # Relaunch the old version so the user is not stranded, then reveal the
  # payload for a manual drag-install.
  open "$TARGET" 2>/dev/null
  if [ -d "$DEST" ]; then open -R "$DEST"; else open -R "$STAGED"; fi
  rm -rf "$LOCK"
  OWN_LOCK=0
fi
