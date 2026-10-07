#!/usr/bin/env bash
# orchestrated 模式：以一次性子进程派发一个回合给一个或多个席位。
# 用法：dispatch.sh <Pk> [<Pj> …] [--via claude|codex|opencode|devin|manual] [--model M] [--thinking low|medium|high] [--note "…"] [--wait] [--dry-run]
#   via/model/thinking 默认取 table.yaml 的 via_Pk / model_Pk / thinking_Pk；--wait 等全部子进程退出后打印 status；--dry-run 只打印将执行的命令
#   子进程的工作目录默认为工作区上两级（<project>/.roundtables/<slug> → <project>），可用环境变量 PROJECT_ROOT 覆盖
set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WS"

ROLES=""; VIA_OVERRIDE=""; MODEL_OVERRIDE=""; THINK_OVERRIDE=""; NOTE=""; WAIT=0; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --via)      VIA_OVERRIDE=$2; shift 2 ;;
    --model)    MODEL_OVERRIDE=$2; shift 2 ;;
    --thinking) THINK_OVERRIDE=$2; shift 2 ;;
    --note)     NOTE=$2; shift 2 ;;
    --wait)     WAIT=1; shift ;;
    --dry-run)  DRY=1; shift ;;
    -*) echo "未知参数 $1" >&2; exit 2 ;;
    *) ROLES="$ROLES $1"; shift ;;
  esac
done
ROLES="${ROLES# }"
[ -n "$ROLES" ] || { sed -n '2,5s/^# *//p' "$0" >&2; exit 2; }

cfg() { sed -n "s/^$1:[[:space:]]*//p" table.yaml | tail -n1 | sed -e 's/[[:space:]]#.*$//' -e 's/^"\(.*\)"$/\1/' -e 's/[[:space:]]*$//'; }
ROOT="${PROJECT_ROOT:-$(cd "$WS/../.." && pwd)}"
PIDS=""

for ROLE in $ROLES; do
  VIA=${VIA_OVERRIDE:-$(cfg "via_$ROLE")}; : "${VIA:=manual}"
  MODEL=${MODEL_OVERRIDE:-$(cfg "model_$ROLE")}
  THINK=${THINK_OVERRIDE:-$(cfg "thinking_$ROLE")}
  if [ -n "$NOTE" ]; then PROMPT=$(bash "$WS/bin/prompt.sh" "$ROLE" --oneshot --note "$NOTE")
  else PROMPT=$(bash "$WS/bin/prompt.sh" "$ROLE" --oneshot); fi
  [ -n "$PROMPT" ] || exit 2

  if [ "$VIA" = manual ]; then
    echo "=== $ROLE 为 manual：请在一个新会话中粘贴以下提示词 ==="
    echo "$PROMPT"
    echo "=== 结束 ==="
    continue
  fi
  [ "$DRY" = 1 ] || command -v "$VIA" >/dev/null 2>&1 || { echo "找不到 CLI: ${VIA}（席位 ${ROLE}）" >&2; exit 127; }

  # 各 CLI 的无头（非交互）调用。任何一次权限提示都会让无头运行静默死亡，所以一律 bypass；
  # 安全网是圆桌协议本身（每个席位只写自己的文件）和主持人的事后核对。
  # 思考等级同时走两条路：CLI 原生参数（若有）+ 提示词里的等级要求（兜底）。
  ENV_PREFIX=(env)
  case "$VIA" in
    claude)
      set -- claude -p "$PROMPT" --permission-mode bypassPermissions --add-dir "$WS"
      [ -n "$MODEL" ] && set -- "$@" --model "$MODEL"
      case "$THINK" in high) ENV_PREFIX+=(MAX_THINKING_TOKENS=32000);; medium) ENV_PREFIX+=(MAX_THINKING_TOKENS=8192);; esac ;;
    codex)
      set -- codex exec --dangerously-bypass-approvals-and-sandbox -C "$ROOT" --add-dir "$WS" --skip-git-repo-check
      [ -n "$MODEL" ] && set -- "$@" -m "$MODEL"
      [ -n "$THINK" ] && set -- "$@" -c "model_reasoning_effort=\"$THINK\""
      set -- "$@" "$PROMPT" ;;
    opencode)
      [ -n "$MODEL" ] || { echo "opencode 没有默认模型：请在 table.yaml 配 model_$ROLE: provider/model 或传 --model" >&2; exit 2; }
      set -- opencode run --auto --dir "$ROOT" -m "$MODEL"
      [ -n "$THINK" ] && set -- "$@" --variant "$THINK"
      set -- "$@" "$PROMPT" ;;
    devin)
      set -- devin -p "$PROMPT" --permission-mode bypass
      [ -n "$MODEL" ] && set -- "$@" --model "$MODEL" ;;
    *) echo "未知 via: ${VIA}（claude | codex | opencode | devin | manual）" >&2; exit 2 ;;
  esac

  if [ "$DRY" = 1 ]; then
    echo "=== $ROLE via=$VIA model=${MODEL:-default} thinking=${THINK:-default} cwd=$ROOT ==="
    printf '%q ' "${ENV_PREFIX[@]}" "$@"; echo; continue
  fi
  TS=$(date +%Y%m%d-%H%M%S); LOG="$WS/logs/$ROLE-$TS.log"
  { echo "# $(date '+%Y-%m-%dT%H:%M:%S') dispatch $ROLE via=$VIA model=${MODEL:-default} thinking=${THINK:-default} cwd=$ROOT"; echo; } > "$LOG"
  ( cd "$ROOT" && nohup "${ENV_PREFIX[@]}" "$@" >> "$LOG" 2>&1 ) &
  PID=$!
  echo "$PID" > "$WS/logs/$ROLE.pid"
  PIDS="$PIDS $PID"
  bash "$WS/bin/log.sh" R0 "派发 $ROLE via=$VIA model=${MODEL:-default} thinking=${THINK:-default} pid=$PID log=logs/$ROLE-$TS.log"
  echo "已派发 $ROLE via=$VIA thinking=${THINK:-default} pid=$PID → $LOG"
done

[ -n "$PIDS" ] || exit 0
if [ "$WAIT" = 1 ]; then
  RC=0
  for p in $PIDS; do wait "$p" || RC=$?; done
  echo "子进程全部退出（最后一个非零退出码: ${RC}）"
  echo
  bash "$WS/bin/status.sh"
  exit "$RC"
fi
echo "后台运行中：pid${PIDS}。等待方式：bash $WS/bin/wait.sh --change  或  wait${PIDS}（同一 shell 内）"
