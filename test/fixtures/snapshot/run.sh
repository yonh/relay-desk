#!/bin/bash
# Compiles the production SnapshotPolicy.swift together with the fixture and
# runs it. No Xcode project, no Flutter SDK — just the swiftc toolchain, so
# the same decision code the app ships is exercised directly.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -o "$OUT/snapshot_fixture" \
  "$ROOT/macos/Runner/SnapshotPolicy.swift" \
  "$HERE/main.swift"

"$OUT/snapshot_fixture"
