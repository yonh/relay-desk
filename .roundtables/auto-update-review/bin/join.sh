#!/usr/bin/env bash
# 身份登记（握手）：嘉宾开始发言前声明"我是 Pk，用的是什么工具/模型"。写入 roster/Pk.yaml，其他会话与人类可见。
# 用法：join.sh <R0|Pk> --tool <claude|codex|opencode|devin|…> --model <模型名> [--thinking low|medium|high] [--force]
#   同一席位已被登记且工具/模型不同 ⇒ 席位冲突，退出码 3；确认是本会话重连时加 --force 覆盖。
set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WS"
ROLE=${1:-}; [ -n "$ROLE" ] || { sed -n '2,4s/^# *//p' "$0" >&2; exit 2; }
shift
TOOL=""; MODEL=""; THINK=""; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tool)     TOOL=$2; shift 2 ;;
    --model)    MODEL=$2; shift 2 ;;
    --thinking) THINK=$2; shift 2 ;;
    --force)    FORCE=1; shift ;;
    *) echo "未知参数 $1" >&2; exit 2 ;;
  esac
done
[ -n "$TOOL" ] && [ -n "$MODEL" ] || { echo "必须给出 --tool 与 --model（写你实际运行的工具与模型，例如 --tool codex --model gpt-5.2-codex）" >&2; exit 2; }

cfg() { sed -n "s/^$1:[[:space:]]*//p" table.yaml | tail -n1 | sed -e 's/[[:space:]]#.*$//' -e 's/^"\(.*\)"$/\1/' -e 's/[[:space:]]*$//'; }
PARTICIPANTS=$(cfg participants); MODE=$(cfg mode)
if [ "$ROLE" = R0 ]; then
  [ "$MODE" = orchestrated ] || { echo "peer 模式没有 R0" >&2; exit 2; }
elif ! printf ' %s ' "$PARTICIPANTS" | grep -q " $ROLE "; then
  echo "未知席位 ${ROLE}（table.yaml: participants=${PARTICIPANTS}）" >&2; exit 2
fi

F="roster/$ROLE.yaml"
if [ -f "$F" ] && [ "$FORCE" = 0 ]; then
  OLD_TOOL=$(sed -n 's/^tool:[[:space:]]*//p' "$F"); OLD_MODEL=$(sed -n 's/^model:[[:space:]]*//p' "$F")
  if [ "$OLD_TOOL/$OLD_MODEL" != "$TOOL/$MODEL" ]; then
    echo "席位冲突：$ROLE 已由 $OLD_TOOL/$OLD_MODEL 于 $(sed -n 's/^joined:[[:space:]]*//p' "$F") 登记。" >&2
    echo "若你确实是同一会话重连，加 --force；否则停下来向人类确认你应该是哪个席位。" >&2
    exit 3
  fi
  echo "$ROLE 已登记（同一工具/模型），更新时间戳。"
fi
{
  echo "role: $ROLE"
  echo "tool: $TOOL"
  echo "model: $MODEL"
  [ -n "$THINK" ] && echo "thinking: $THINK"
  echo "host: $(hostname -s 2>/dev/null || hostname)"
  echo "cwd: $PWD"
  echo "ppid: $PPID"
  echo "joined: $(date '+%Y-%m-%dT%H:%M:%S')"
} > "$F"
bash "$WS/bin/log.sh" "$ROLE" "就位 tool=$TOOL model=$MODEL${THINK:+ thinking=$THINK}"
echo "已登记 $ROLE → $F"
echo
bash "$WS/bin/status.sh"
