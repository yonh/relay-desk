#!/usr/bin/env bash
# 阻塞直到轮到某席位发言/总结，或圆桌结束。用法：wait.sh <Pk> [--timeout 秒] [--interval 秒]
#        wait.sh --change [...]   阻塞直到状态发生任何变化（主持人用）
#        wait.sh --joined [...]   阻塞直到所有席位都已 join.sh 登记
# 退出码：0 轮到你/结束；124 超时
set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
ROLE=""; TIMEOUT=3600; INTERVAL=15; CHANGE=0; JOINED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout)  TIMEOUT=$2; shift 2 ;;
    --interval) INTERVAL=$2; shift 2 ;;
    --change)   CHANGE=1; shift ;;
    --joined)   JOINED=1; shift ;;
    *) ROLE=$1; shift ;;
  esac
done
[ -n "$ROLE" ] || [ "$CHANGE" = 1 ] || [ "$JOINED" = 1 ] || { sed -n '2,5s/^# *//p' "$0" >&2; exit 2; }

get() { printf '%s\n' "$SNAP" | sed -n "s/^$1=//p"; }
SNAP=$(bash "$WS/bin/status.sh" --porcelain); FIRST="$SNAP"
START=$(date +%s)
while :; do
  STATE=$(get state); NR=$(get next_role); PEND=$(get pending); SYNTH=$(get synthesizer)
  case "$STATE" in done|stopped) break ;; esac
  if [ "$JOINED" = 1 ]; then
    [ -z "$(get missing)" ] && break
  elif [ "$CHANGE" = 1 ]; then
    [ "$SNAP" != "$FIRST" ] && break
  elif [ "$STATE" = synthesizing ] && [ "$SYNTH" = "$ROLE" ]; then
    break
  elif [ "$NR" = "$ROLE" ]; then
    break
  elif [ "$NR" = participants ] && printf ' %s ' "$PEND" | grep -q " $ROLE "; then
    break
  fi
  if [ $(( $(date +%s) - START )) -ge "$TIMEOUT" ]; then
    WHAT="仍未轮到 ${ROLE:-（状态未变）}"; [ "$JOINED" = 1 ] && WHAT="仍有席位未就位: $(get missing)"
    echo "wait.sh: 超时 ${TIMEOUT}s，${WHAT}；当前状态 ${STATE}。再跑一次即可继续等。" >&2
    exit 124
  fi
  sleep "$INTERVAL"
  SNAP=$(bash "$WS/bin/status.sh" --porcelain)
done
bash "$WS/bin/status.sh"
