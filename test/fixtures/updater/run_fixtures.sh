#!/bin/bash
# Isolated concurrency fixtures for macos/Runner/RelayDeskUpdater.app/
# Contents/MacOS/updater.sh — every case runs inside a temp dir with
# stubbed ditto/open/pgrep/xattr/ps. NO real app is ever replaced.
#
#   bash test/fixtures/updater/run_fixtures.sh
#
# Scenarios:
#   1. mid-swap second helper   — a helper losing the lock must not
#                                 resurrect the backup or merge payloads
#   2. crash recovery           — orphan lock + missing TARGET + BACKUP
#                                 present → backup revived, swap done
#   3. reclaim race             — orphan lock + two helpers → exactly
#                                 one ditto
#   4. arb contention           — live AND orphaned foreign ARB are
#                                 never deleted; install stands down
#                                 with a diagnosable message; manual
#                                 removal recovers it
#   5. SIGTERM mid-arbitration  — cleanup() releases our own ARB so the
#                                 next install is not blocked (SIGKILL
#                                 orphans it → manual recovery, see 4)
set -u
cd "$(dirname "$0")/../../.."
SCRIPT="$PWD/macos/Runner/RelayDeskUpdater.app/Contents/MacOS/updater.sh"
FIX=/tmp/relay-updater-fixtures
DEADPID=99999   # stands in for the (dead) parent pid AND dead lock owners
fail=0

say()  { printf '%s\n' "$*"; }
ok()   { say "  PASS $*"; }
bad()  { say "  FAIL $*"; fail=1; }

setup() {
  rm -rf "$FIX"
  mkdir -p "$FIX/updates/v9.9.9/payload/New.app/Contents/MacOS"
  echo NEW > "$FIX/updates/v9.9.9/payload/New.app/Contents/MacOS/new.txt"
  mkdir -p "$FIX/Target.app/Contents/MacOS"
  echo OLD > "$FIX/Target.app/Contents/MacOS/old.txt"
  touch "$FIX/updates/v9.9.9/package.zip"
  mkdir -p "$FIX/bin"
  # Stubs: ditto sleeps so overlapping calls would be observable; open/
  # xattr succeed; pgrep reports nothing running.
  cat > "$FIX/bin/ditto" <<'EOS'
#!/bin/bash
echo "ditto $$" >> /tmp/relay-updater-fixtures/ditto.log
sleep 3
mkdir -p "$2"
cp -R "$1/"* "$2/" 2>/dev/null || cp -R "$1" "$2"
EOS
  cat > "$FIX/bin/open" <<'EOS'
#!/bin/bash
exit 0
EOS
  cat > "$FIX/bin/pgrep" <<'EOS'
#!/bin/bash
exit 1
EOS
  cat > "$FIX/bin/xattr" <<'EOS'
#!/bin/bash
exit 0
EOS
  chmod +x "$FIX/bin/"*
}
LOCK="$FIX/Target.app.update-lock"
ARB="$LOCK.arb"
ARGS="$FIX/updates/v9.9.9 $FIX/updates/v9.9.9/payload/New.app $FIX/Target.app $FIX/updates/v9.9.9/package.zip"
run() { PATH="$FIX/bin:/usr/bin:/bin" bash "$SCRIPT" "$DEADPID" $ARGS >"$2" 2>&1; }
dittos() { cat "$FIX/ditto.log" 2>/dev/null | wc -l | tr -d ' '; }

say "== 1. mid-swap second helper =="
setup
run x "$FIX/h1.log" & H1=$!
sleep 2.5   # H1 is inside the slow ditto, backup parked
run x "$FIX/h2.log"; E2=$?
wait $H1; E1=$?
[ "$(ls "$FIX/Target.app/Contents/MacOS" | tr '\n' ' ')" = "new.txt " ] \
  && [ ! -d "$FIX/Target.app.relay-backup" ] && [ "$E1" = 0 ] && [ "$E2" = 0 ] \
  && ok "loser never touched BACKUP; clean new bundle" \
  || bad "E1=$E1 E2=$E2 target=$(ls "$FIX/Target.app/Contents/MacOS" | tr '\n' ' ') backup=$([ -d "$FIX/Target.app.relay-backup" ] && echo yes)"

say "== 2. crash recovery (orphan lock + backup present) =="
setup
rm -rf "$FIX/Target.app"
mkdir -p "$LOCK" "$FIX/Target.app.relay-backup"
echo 99998 > "$LOCK/pid"; touch -t 202001010000 "$LOCK"
echo OLD > "$FIX/Target.app.relay-backup/old.txt"
run x "$FIX/h3.log"; E=$?
[ -f "$FIX/Target.app/Contents/MacOS/new.txt" ] && [ ! -d "$LOCK" ] && [ "$E" = 0 ] \
  && ok "backup revived then swapped, locks cleaned" \
  || bad "E=$E target=$(find "$FIX/Target.app" -type f 2>/dev/null | tr '\n' ' ') lock=$([ -d "$LOCK" ] && echo yes)"

say "== 3. reclaim race: orphan lock, two helpers =="
setup
rm -rf "$FIX/Target.app"; mkdir -p "$FIX/Target.app/Contents/MacOS"; echo OLD > "$FIX/Target.app/Contents/MacOS/old.txt"
mkdir -p "$LOCK" && echo 99998 > "$LOCK/pid" && touch -t 202001010000 "$LOCK"
run x "$FIX/h4.log" & H4=$!
run x "$FIX/h5.log" & H5=$!
wait $H4; E4=$?; wait $H5; E5=$?
[ "$(dittos)" = "1" ] && [ "$(ls "$FIX/Target.app/Contents/MacOS")" = "new.txt" ] \
  && ok "exactly one swapper (exits $E4/$E5)" \
  || bad "dittos=$(dittos) E4=$E4 E5=$E5"

say "== 4. arb contention: live and orphan ARB stand down, manual recovery =="
setup
mkdir -p "$LOCK" && echo 99998 > "$LOCK/pid" && touch -t 202001010000 "$LOCK"
# 4a: ARB held by a LIVE helper-like process
mkdir -p "$ARB"
cat > "$FIX/bin/updater.sh" <<'EOS'
#!/bin/bash
sleep 15
EOS
chmod +x "$FIX/bin/updater.sh"
"$FIX/bin/updater.sh" & LIVEARB=$!
echo "$LIVEARB" > "$ARB/pid"; touch -t 202001010000 "$ARB"
run x "$FIX/h6.log"; E6=$?
[ "$E6" = 1 ] && [ "$(dittos)" = "0" ] && [ -d "$ARB" ] && [ -d "$LOCK" ] \
  && grep -q "arb-contended" "$FIX/updates/v9.9.9/helper.aborted" \
  && [ "$(ls "$FIX/Target.app/Contents/MacOS")" = "old.txt" ] \
  && ok "live ARB: exited 1, nothing deleted, message written" \
  || bad "live ARB: E=$E6 ditto=$(dittos) arb=$([ -d "$ARB" ] && echo yes) lock=$([ -d "$LOCK" ] && echo yes)"
kill "$LIVEARB" 2>/dev/null; wait "$LIVEARB" 2>/dev/null
# 4b: ARB orphaned by a dead pid — competitors still must not delete it
echo 88888 > "$ARB/pid"; touch -t 202001010000 "$ARB"
run x "$FIX/h7.log"; E7=$?
[ "$E7" = 1 ] && [ "$(dittos)" = "0" ] && [ -d "$ARB" ] \
  && ok "orphan ARB: competitors leave it untouched" \
  || bad "orphan ARB: E=$E7 arb=$([ -d "$ARB" ] && echo yes)"
# 4c: manual recovery unblocks the install
rm -rf "$ARB"
run x "$FIX/h8.log"; E8=$?
[ "$E8" = 0 ] && [ "$(dittos)" = "1" ] && [ "$(ls "$FIX/Target.app/Contents/MacOS")" = "new.txt" ] \
  && ok "manual rm recovers: one clean swap" \
  || bad "recovery: E=$E8 ditto=$(dittos)"

say "== 5. SIGTERM mid-arbitration releases our own ARB =="
setup
mkdir -p "$LOCK"
# The lock owner must be ALIVE for the helper to reach `ps` inside
# arbitration — a dead owner is decided without ever calling it. A
# sleeping process stands in; the stubbed `ps` below returns nothing,
# so the owner reads as undeterminable and the aged lock is reclaimed.
sleep 30 & ARBOWNER=$!
echo "$ARBOWNER" > "$LOCK/pid"; touch -t 202001010000 "$LOCK"
# Stretch the arbitration window: a slow `ps` keeps the helper inside
# the ARB-holding inspection long enough to catch SIGTERM there.
cat > "$FIX/bin/ps" <<'EOS'
#!/bin/bash
sleep 4
EOS
chmod +x "$FIX/bin/ps"
# Launch the helper directly — `$!` must be the script process itself,
# not a wrapping function subshell, or SIGTERM would miss the helper.
PATH="$FIX/bin:/usr/bin:/bin" bash "$SCRIPT" "$DEADPID" $ARGS >"$FIX/h9.log" 2>&1 &
H9=$!
sleep 2     # helper is inside arbitration, holding its own ARB
kill -TERM "$H9" 2>/dev/null
wait "$H9" 2>/dev/null
kill "$ARBOWNER" 2>/dev/null; wait "$ARBOWNER" 2>/dev/null
[ ! -d "$ARB" ] && [ -d "$LOCK" ] \
  && ok "trap released our ARB; foreign LOCK untouched" \
  || bad "SIGTERM: arb=$([ -d "$ARB" ] && echo left) lock=$([ -d "$LOCK" ] && echo yes)"
# And the next install still works (dead lock reclaimed normally)
rm "$FIX/bin/ps"
run x "$FIX/h10.log"; E10=$?
[ "$E10" = 0 ] && [ "$(dittos)" = "1" ] \
  && ok "next install proceeds after SIGTERM'd arbitration" \
  || bad "post-SIGTERM install: E=$E10 ditto=$(dittos)"

rm -rf "$FIX"
if [ "$fail" = 0 ]; then say "ALL FIXTURES PASSED"; else say "FIXTURE FAILURES"; exit 1; fi
