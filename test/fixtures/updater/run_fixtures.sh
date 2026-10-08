#!/bin/bash
# Isolated concurrency fixtures for macos/Runner/RelayDeskUpdater.app/
# Contents/MacOS/updater.sh — every case runs in a mktemp dir with
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
#   6. release race             — TERM landing between "drop ownership"
#                                 and "delete dir" leaves an orphan but
#                                 NEVER deletes another holder's ARB
set -u
cd "$(dirname "$0")/../../.."
SCRIPT="$PWD/macos/Runner/RelayDeskUpdater.app/Contents/MacOS/updater.sh"
FIX=$(mktemp -d /tmp/relay-updater-fixtures.XXXXXX)
DEADPID=99999   # stands in for the (dead) parent pid AND dead lock owners
CHILDREN=""     # every backgrounded helper/sleeper — all killed on exit
fail=0

# Recursively kill a process and every descendant — stubs spawn their
# own children (sleep), so pkill -P alone leaves grandchildren behind.
killtree() {
  local kid
  for kid in $(pgrep -P "$1" 2>/dev/null); do killtree "$kid"; done
  kill "$1" 2>/dev/null
}
teardown() {
  for p in $CHILDREN; do killtree "$p"; done
  wait 2>/dev/null
  rm -rf "$FIX"
}
trap teardown EXIT

say()  { printf '%s\n' "$*"; }
ok()   { say "  PASS $*"; }
bad()  { say "  FAIL $*"; fail=1; }

# A timed-out barrier means the helper under test is stuck — continuing
# would let it keep writing while later scenarios rebuild the same
# directory. Fail the whole suite right away; teardown reaps every
# tracked process subtree before the temp dir is removed.
die()  { say "  FAIL $*"; exit 1; }

# Bounded wait for a path to appear/disappear — synchronization, not a
# fixed sleep. A timed-out barrier aborts the scenario (via `|| die`)
# so a stuck helper can't corrupt later scenarios' assertions.
wait_for() { # path timeout_seconds
  local i=0
  while [ ! -e "$1" ]; do
    i=$((i+1)); [ "$i" -gt $(( ${2:-10} * 10 )) ] && return 1
    sleep 0.1
  done
}
wait_for_absent() { # path timeout_seconds
  local i=0
  while [ -e "$1" ]; do
    i=$((i+1)); [ "$i" -gt $(( ${2:-10} * 10 )) ] && return 1
    sleep 0.1
  done
}

setup() {
  rm -rf "$FIX/work"
  mkdir -p "$FIX/work"
  W="$FIX/work"
  mkdir -p "$W/updates/v9.9.9/payload/New.app/Contents/MacOS"
  echo NEW > "$W/updates/v9.9.9/payload/New.app/Contents/MacOS/new.txt"
  mkdir -p "$W/Target.app/Contents/MacOS"
  echo OLD > "$W/Target.app/Contents/MacOS/old.txt"
  touch "$W/updates/v9.9.9/package.zip"
  mkdir -p "$W/bin"
  # Stubs: ditto sleeps so overlapping calls would be observable; open/
  # xattr succeed; pgrep reports nothing running.
  cat > "$W/bin/ditto" <<EOS
#!/bin/bash
touch "$W/ditto.entered" 2>/dev/null
echo "ditto \$\$" >> "$W/ditto.log"
sleep 3
mkdir -p "\$2"
cp -R "\$1/"* "\$2/" 2>/dev/null || cp -R "\$1" "\$2"
EOS
  cat > "$W/bin/open" <<'EOS'
#!/bin/bash
exit 0
EOS
  cat > "$W/bin/pgrep" <<'EOS'
#!/bin/bash
exit 1
EOS
  cat > "$W/bin/xattr" <<'EOS'
#!/bin/bash
exit 0
EOS
  chmod +x "$W/bin/"*
}

ARGS() { echo "$W/updates/v9.9.9 $W/updates/v9.9.9/payload/New.app $W/Target.app $W/updates/v9.9.9/package.zip"; }
run()  { PATH="$W/bin:/usr/bin:/bin" bash "$SCRIPT" "$DEADPID" $(ARGS) >"$2" 2>&1; }
dittos() { cat "$W/ditto.log" 2>/dev/null | wc -l | tr -d ' '; }

scenario_1() {
  say "== 1. mid-swap second helper =="
  setup
  run x "$W/h1.log" & CHILDREN="$CHILDREN $!"
  # Barrier: wait until H1 is actually inside ditto (backup parked, lock held).
  wait_for "$W/ditto.entered" 10 || die "ditto barrier timed out"
  run x "$W/h2.log"; E2=$?
  wait; E1=0
  [ "$(ls "$W/Target.app/Contents/MacOS" | tr '\n' ' ')" = "new.txt " ] \
    && [ ! -d "$W/Target.app.relay-backup" ] && [ "$E2" = 0 ] \
    && ok "loser never touched BACKUP; clean new bundle" \
    || bad "E2=$E2 target=$(ls "$W/Target.app/Contents/MacOS" | tr '\n' ' ') backup=$([ -d "$W/Target.app.relay-backup" ] && echo yes)"
}

scenario_2() {
  say "== 2. crash recovery (orphan lock + backup present) =="
  setup
  L="$W/Target.app.update-lock"
  rm -rf "$W/Target.app"
  mkdir -p "$L" "$W/Target.app.relay-backup"
  echo 99998 > "$L/pid"; touch -t 202001010000 "$L"
  echo OLD > "$W/Target.app.relay-backup/old.txt"
  run x "$W/h3.log"; E=$?
  [ -f "$W/Target.app/Contents/MacOS/new.txt" ] && [ ! -d "$L" ] && [ "$E" = 0 ] \
    && ok "backup revived then swapped, locks cleaned" \
    || bad "E=$E lock=$([ -d "$L" ] && echo yes)"
}

scenario_3() {
  say "== 3. reclaim race: orphan lock, two helpers =="
  setup
  rm -rf "$W/Target.app"; mkdir -p "$W/Target.app/Contents/MacOS"; echo OLD > "$W/Target.app/Contents/MacOS/old.txt"
  L="$W/Target.app.update-lock"
  mkdir -p "$L" && echo 99998 > "$L/pid" && touch -t 202001010000 "$L"
  run x "$W/h4.log" & CHILDREN="$CHILDREN $!"
  run x "$W/h5.log" & CHILDREN="$CHILDREN $!"
  wait
  [ "$(dittos)" = "1" ] && [ "$(ls "$W/Target.app/Contents/MacOS")" = "new.txt" ] \
    && ok "exactly one swapper" \
    || bad "dittos=$(dittos)"
}

scenario_4() {
  say "== 4. arb contention: live and orphan ARB stand down, manual recovery =="
  setup
  L="$W/Target.app.update-lock"; A="$L.arb"
  mkdir -p "$L" && echo 99998 > "$L/pid" && touch -t 202001010000 "$L"
  # 4a: ARB held by a LIVE helper-like process
  mkdir -p "$A"
  cat > "$W/bin/updater.sh" <<'EOS'
#!/bin/bash
sleep 30
EOS
  chmod +x "$W/bin/updater.sh"
  "$W/bin/updater.sh" & LIVEARB=$!; CHILDREN="$CHILDREN $LIVEARB"
  echo "$LIVEARB" > "$A/pid"; touch -t 202001010000 "$A"
  run x "$W/h6.log"; E6=$?
  [ "$E6" = 1 ] && [ "$(dittos)" = "0" ] && [ -d "$A" ] && [ -d "$L" ] \
    && grep -q "arb-contended" "$W/updates/v9.9.9/helper.aborted" \
    && [ "$(ls "$W/Target.app/Contents/MacOS")" = "old.txt" ] \
    && ok "live ARB: exited 1, nothing deleted, message written" \
    || bad "live ARB: E=$E6 ditto=$(dittos) arb=$([ -d "$A" ] && echo yes) lock=$([ -d "$L" ] && echo yes)"
  killtree "$LIVEARB"
  wait "$LIVEARB" 2>/dev/null
  # 4b: ARB orphaned by a dead pid — competitors still must not delete it
  echo 88888 > "$A/pid"; touch -t 202001010000 "$A"
  run x "$W/h7.log"; E7=$?
  [ "$E7" = 1 ] && [ "$(dittos)" = "0" ] && [ -d "$A" ] \
    && ok "orphan ARB: competitors leave it untouched" \
    || bad "orphan ARB: E=$E7 arb=$([ -d "$A" ] && echo yes)"
  # 4c: manual recovery unblocks the install
  rm -rf "$A"
  run x "$W/h8.log"; E8=$?
  [ "$E8" = 0 ] && [ "$(dittos)" = "1" ] && [ "$(ls "$W/Target.app/Contents/MacOS")" = "new.txt" ] \
    && ok "manual rm recovers: one clean swap" \
    || bad "recovery: E=$E8 ditto=$(dittos)"
}

scenario_5() {
  say "== 5. SIGTERM mid-arbitration releases our own ARB =="
  setup
  L="$W/Target.app.update-lock"; A="$L.arb"
  mkdir -p "$L"
  # The lock owner must be ALIVE for the helper to reach `ps` inside
  # arbitration — a dead owner is decided without ever calling it. A
  # sleeping process stands in; the stubbed `ps` returns nothing, so the
  # owner reads as undeterminable and the aged lock is reclaimed.
  sleep 30 & LOCKPID=$!; CHILDREN="$CHILDREN $LOCKPID"
  echo "$LOCKPID" > "$L/pid"; touch -t 202001010000 "$L"
  # Stretch the arbitration window and mark entry so the TERM is placed
  # deterministically: the stubbed ps touches a barrier file, then sleeps.
  cat > "$W/bin/ps" <<EOS
#!/bin/bash
touch "$W/ps.entered"
sleep 8
EOS
  chmod +x "$W/bin/ps"
  PATH="$W/bin:/usr/bin:/bin" bash "$SCRIPT" "$DEADPID" $(ARGS) >"$W/h9.log" 2>&1 &
  H9=$!; CHILDREN="$CHILDREN $H9"
  # Barrier: helper is provably inside the ARB-holding inspection now.
  wait_for "$W/ps.entered" 10 || die "ps barrier timed out"
  kill -TERM "$H9" 2>/dev/null
  wait "$H9" 2>/dev/null
  kill "$LOCKPID" 2>/dev/null
  [ ! -d "$A" ] && [ -d "$L" ] \
    && ok "trap released our ARB; foreign LOCK untouched" \
    || bad "SIGTERM: arb=$([ -d "$A" ] && echo left) lock=$([ -d "$L" ] && echo yes)"
  rm "$W/bin/ps"
  run x "$W/h10.log"; E10=$?
  [ "$E10" = 0 ] && [ "$(dittos)" = "1" ] \
    && ok "next install proceeds after SIGTERM'd arbitration" \
    || bad "post-SIGTERM install: E=$E10 ditto=$(dittos)"
}

scenario_6() {
  say "== 6. release race: TERM between drop-ownership and delete =="
  setup
  L="$W/Target.app.update-lock"; A="$L.arb"
  mkdir -p "$L"
  sleep 30 & LOCKPID=$!; CHILDREN="$CHILDREN $LOCKPID"
  echo "$LOCKPID" > "$L/pid"; touch -t 202001010000 "$L"
  # The lock owner must be alive for the helper to reach `ps`; the stubbed
  # rm stalls inside the ARB release so the TERM lands deterministically
  # between OWN_ARB=0 and the deletion finishing. If cleanup() still
  # believed it owned the ARB it would run `rm -rf $A` a SECOND time —
  # count rm invocations against the arb path to prove it doesn't.
  cat > "$W/bin/ps" <<EOS
#!/bin/bash
sleep 1
EOS
  cat > "$W/bin/rm" <<EOS
#!/bin/bash
echo "rm \$*" >> "$W/rm.log"
case "\$*" in *.arb*) touch "$W/rm.arb";; esac
sleep 4
/bin/rm "\$@"
EOS
  chmod +x "$W/bin/rm" "$W/bin/ps"
  PATH="$W/bin:/usr/bin:/bin" bash "$SCRIPT" "$DEADPID" $(ARGS) >"$W/h11.log" 2>&1 &
  H11=$!; CHILDREN="$CHILDREN $H11"
  # Barrier: provably inside `OWN_ARB=0; rm -rf "$ARB"` right now.
  wait_for "$W/rm.arb" 10 || die "rm barrier timed out"
  kill -TERM "$H11" 2>/dev/null; wait "$H11" 2>/dev/null
  kill "$LOCKPID" 2>/dev/null
  # bash exits on TERM while its stubbed `rm` child is still sleeping —
  # give the orphaned child a moment to finish the real deletion.
  wait_for_absent "$A" 8 || true
  ARMS=$(grep -c '\.arb' "$W/rm.log" 2>/dev/null)
  [ "$ARMS" = "1" ] && [ ! -d "$A" ] \
    && ok "cleanup skipped ARB once ownership was dropped (rm count=$ARMS)" \
    || bad "release race: arb rm invocations=$ARMS arb-dir=$([ -d "$A" ] && echo left)"
}

scenario_1
scenario_2
scenario_3
scenario_4
scenario_5
scenario_6

if [ "$fail" = 0 ]; then say "ALL FIXTURES PASSED"; else say "FIXTURE FAILURES"; exit 1; fi
