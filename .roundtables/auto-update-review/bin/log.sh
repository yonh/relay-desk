#!/usr/bin/env bash
# 向 LOG.md 追加一行时间线。用法：log.sh <R0|Pk> "<做了什么>"
set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -ge 2 ] || { echo "用法: log.sh <R0|Pk> \"<做了什么>\"" >&2; exit 2; }
ROLE=$1; shift
printf -- "- %s [%s] %s\n" "$(date '+%Y-%m-%dT%H:%M:%S')" "$ROLE" "$*" >> "$WS/LOG.md"
