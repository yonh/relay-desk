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
  for c in \
    "$HOME/Library/Containers/com.example.relayDesk/Data/Library/Application Support/com.example.relayDesk/updates/handoff.params" \
    "$HOME/Library/Application Support/com.example.relayDesk/updates/handoff.params"; do
    [ -f "$c" ] && HANDOFF_FILE="$c" && break
  done
  if [ -n "$HANDOFF_FILE" ]; then
    # Stale handoff: only trust a file written in the last 10 minutes — a
    # replayed/planted params file must not drive destructive swaps later.
    now=$(date +%s)
    mtime=$(stat -f %m "$HANDOFF_FILE" 2>/dev/null || echo 0)
    if [ $((now - mtime)) -gt 600 ]; then
      exit 0
    fi
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
# Containment checks on file-sourced params: PID numeric, payload must sit
# inside the staging root, and only *.app bundles may be replaced.
case "$PARENT" in *[!0-9]*|"") exit 0;; esac
case "$STAGED" in "$ROOT"/*) ;; *) exit 0;; esac
case "$TARGET" in *.app) ;; *) exit 0;; esac
MARKER="$ROOT/helper.started"
ABORT="$ROOT/helper.abort"
ABORTED="$ROOT/helper.aborted"
LOCK="$ROOT/helper.lock"
PAYLOAD="$ROOT/payload"
BACKUP="$TARGET.relay-backup"
OWN_LOCK=0
# Self-heal on abnormal exit: if we die after parking the old bundle but
# before a successful ditto, put it back; release the lock only if we own
# it (a quiet-exit second helper must not drop the first helper's lock).
cleanup() {
  if [ -d "$BACKUP" ] && [ ! -d "$TARGET" ]; then
    mv "$BACKUP" "$TARGET" 2>/dev/null || echo "rollback-failed" > "$ABORTED"
  fi
  [ "$OWN_LOCK" = 1 ] && rmdir "$LOCK" 2>/dev/null
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
# (both saw a dead parent; only one may mutate the target).
mkdir "$LOCK" 2>/dev/null || exit 0
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
  rm -rf "$PAYLOAD" "$ARCHIVE" "$MARKER" "$ABORT" "$LOCK"
  [ -n "$HANDOFF_FILE" ] && rm -f "$HANDOFF_FILE"
  OWN_LOCK=0
  # Delete the backup only after the new app actually launches — if open
  # fails, BACKUP stays on disk for manual recovery (L2 sweep handles it).
  open "$TARGET" && rm -rf "$BACKUP"
else
  # Move the payload out of the swept staging dir FIRST — the relaunched
  # app's own startup sweep would delete it before we get here otherwise.
  TAG=$(basename "$ROOT")
  DEST="$HOME/Downloads/RelayDesk-$TAG"
  rm -rf "$DEST"
  mv "$PAYLOAD" "$DEST" 2>/dev/null
  rm -rf "$MARKER" "$LOCK"
  [ -n "$HANDOFF_FILE" ] && rm -f "$HANDOFF_FILE"
  OWN_LOCK=0
  # Roll the old version back: ditto may have left a partial bundle, so the
  # leftover target must be removed before mv — rename into a non-empty dir
  # fails and would nest the backup inside the broken app.
  if [ -d "$BACKUP" ]; then
    rm -rf "$TARGET" && mv "$BACKUP" "$TARGET"
  fi
  # Relaunch the old version so the user is not stranded, then reveal the
  # payload for a manual drag-install.
  open "$TARGET" 2>/dev/null
  if [ -d "$DEST" ]; then open -R "$DEST"; else open -R "$STAGED"; fi
fi
