#!/usr/bin/env bash
# Build the Relay Desk automation CLI (relayctl) as a self-contained macOS
# executable and stage a three-file archive for third parties.
#
# The CLI entrypoint tool/relayctl.dart is SDK-only, so this script compiles it
# against an isolated, empty package_config.json. That keeps Flutter's
# package resolution and native-asset hooks out of the build.
#
# Each host architecture compiles its own binary. There is no universal binary
# and no Intel cross-compilation.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
readonly ENTRYPOINT="${SCRIPT_DIR}/relayctl.dart"

usage() {
  cat <<'USAGE'
Usage: bash tool/build_relayctl.sh [--output-dir DIR]

Compiles tool/relayctl.dart (Dart SDK only) into a self-contained executable
for the current macOS host architecture, then stages:

  <output-root>/macos-<arch>/relayctl
  <output-root>/macos-<arch>/README.md
  <output-root>/macos-<arch>/SHA256SUMS
  <output-root>/relayctl-macos-<arch>.tar.gz

Options:
  --output-dir DIR  Output root for staged files and the archive.
                    Default: <repo>/build/relayctl
  -h, --help        Print this help and exit without touching the OS,
                    the compiler or the entrypoint.

Environment:
  DART_BIN          Absolute or relative path to one Dart executable.
                    Spaces are honoured. Default: `command -v dart`.

Notes:
  - macOS only; arm64 maps to macos-arm64, x86_64 maps to macos-x64.
    Any other architecture is rejected.
  - One executable per host architecture; no universal binary is produced.
  - No Developer ID signing or notarization is performed.
    This is a local/internal verification artifact.
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '%s\n' "$*"
}

# ---------------------------------------------------------------- arguments --
# Parsed before any environment probing so that --help stays offline.
output_root="${REPO_ROOT}/build/relayctl"
output_root_set=0
cwd="$(pwd -P)"

set_output_root() {
  if [ -z "$1" ]; then
    printf 'error: --output-dir requires a non-empty directory\n\n' >&2
    usage >&2
    exit 2
  fi
  if [ "$output_root_set" -eq 1 ]; then
    printf 'error: --output-dir given more than once\n\n' >&2
    usage >&2
    exit 2
  fi
  output_root="$1"
  output_root_set=1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --output-dir)
      [ "$#" -ge 2 ] || { printf 'error: --output-dir requires a directory\n\n' >&2; usage >&2; exit 2; }
      set_output_root "$2"
      shift 2
      ;;
    --output-dir=*)
      set_output_root "${1#--output-dir=}"
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      printf 'error: unsupported argument: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ "$#" -gt 0 ]; then
  printf 'error: unsupported argument: %s\n\n' "$1" >&2
  usage >&2
  exit 2
fi

# --------------------------------------------------------------- platform ----
[ "$(uname -s)" = "Darwin" ] || die "relayctl packaging is macOS only (uname -s: $(uname -s))"

case "$(uname -m)" in
  arm64)  arch="arm64" ;;
  x86_64) arch="x64"  ;;
  *)      die "unsupported macOS architecture: $(uname -m); expected arm64 or x86_64" ;;
esac

# ---------------------------------------------------------------- compiler ---
if [ -n "${DART_BIN:-}" ]; then
  # Resolve a bare command name through PATH first, then a path, so the
  # executability check always runs against the resolved file. Paths containing
  # spaces stay quoted throughout.
  case "$DART_BIN" in
    */*)
      dart_bin="$DART_BIN"
      [ -e "$dart_bin" ] || die "DART_BIN does not exist: $dart_bin"
      dart_bin="$(cd "$(dirname "$dart_bin")" && pwd -P)/$(basename "$dart_bin")"
      ;;
    *)
      resolved="$(command -v "$DART_BIN")" || die "DART_BIN not found on PATH: $DART_BIN"
      dart_bin="$resolved"
      ;;
  esac
  [ -f "$dart_bin" ] || die "DART_BIN is not a file: $dart_bin"
  [ -x "$dart_bin" ] || die "DART_BIN is not executable: $dart_bin"
else
  dart_bin="$(command -v dart)" || die "dart not found on PATH; install the Dart SDK or set DART_BIN"
fi

[ -f "$ENTRYPOINT" ] || die "CLI entrypoint not found: $ENTRYPOINT"
command -v shasum >/dev/null 2>&1 || die "shasum is required (macOS ships it) but was not found"
command -v tar >/dev/null 2>&1 || die "tar is required but was not found"

# ----------------------------------------------------------------- layout ----
if [ "$output_root_set" -eq 1 ]; then
  # Resolve against the current working directory without requiring the parent
  # to exist yet; missing parents are created later with mkdir -p.
  case "$output_root" in
    /*) ;;
    ~*) output_root="${HOME}${output_root#\~}" ;;
    *)  output_root="${cwd}/${output_root#./}" ;;
  esac
fi

stage_dir="${output_root}/macos-${arch}"
archive="${output_root}/relayctl-macos-${arch}.tar.gz"

# Build into a private temporary directory so a failed compile can never leave
# a half-written or stale executable behind, and so nothing outside this
# directory is ever removed.
build_tmp="$(mktemp -d "${TMPDIR:-/tmp}/relayctl-build.XXXXXX")"
cleanup() {
  rm -rf "$build_tmp"
}
trap cleanup EXIT

package_config="${build_tmp}/package_config.json"
cat >"$package_config" <<'JSON'
{
  "configVersion": 2,
  "packages": []
}
JSON

note "arch        macos-${arch} (host architecture only)"
note "dart        ${dart_bin}"
note "entrypoint  ${ENTRYPOINT}"
note "output      ${output_root}"

# ---------------------------------------------------------------- compile ----
note "compiling relayctl (isolated package config)"
"$dart_bin" compile exe \
  --packages="$package_config" \
  -o "${build_tmp}/relayctl" \
  "$ENTRYPOINT"

[ -f "${build_tmp}/relayctl" ] || die "compiler reported success but produced no executable"
chmod +x "${build_tmp}/relayctl"

# The label macos-<arch> promises the host architecture. Confirm the compiled
# Mach-O really is that slice before anything is staged, so a mismatched SDK or
# a Rosetta-translated host can never be published under the wrong name.
case "$arch" in
  arm64) expect_pattern='arm64' ;;
  x64)   expect_pattern='x86_64' ;;
esac

file_bin=""
if command -v file >/dev/null 2>&1; then
  file_bin="$(command -v file)"
elif [ -x /usr/bin/file ]; then
  file_bin="/usr/bin/file"
fi

if [ -n "$file_bin" ]; then
  binary_desc="$("$file_bin" -b "${build_tmp}/relayctl")"
  case "$binary_desc" in
    *universal*|*Universal*)
      die "compiled a universal binary but only ${arch} was expected; refusing to mislabel the artifact: ${binary_desc}"
      ;;
    *arm64*)  actual_arch="arm64" ;;
    *x86_64*) actual_arch="x64" ;;
    *)
      die "could not determine the compiled architecture (expected ${expect_pattern}): ${binary_desc}"
      ;;
  esac
  [ "$actual_arch" = "$arch" ] || die "compiled executable is ${actual_arch}, but this host is labelled macos-${arch}; check for a mixed-architecture Dart SDK or a Rosetta-translated shell before packaging"
  note "verified   macos-${arch} (${binary_desc})"
else
  die "file(1) is required to verify the executable architecture before packaging"
fi

# ------------------------------------------------------------------ stage ----
mkdir -p "$stage_dir"

install -m 0755 "${build_tmp}/relayctl" "${stage_dir}/relayctl"

cat >"${stage_dir}/README.md" <<README
# relayctl (macos-${arch})

Relay Desk 自动化 CLI 的独立可执行文件，仅包含 macos-${arch}（本机架构）一个版本。
它把 Dart 运行时打包进可执行文件，使用方无需安装 Python、Dart 或 Flutter。

## 前置条件

relayctl 只连接已经在运行的 Relay Desk 调试实例。请启动开发者提供的、已经在编译时开启调试接口的应用构建。
接收方无需安装开发环境，也无需执行 Flutter 命令。普通发布版目前不能由 CLI 开启该接口。

- 该服务只在 macOS debug 构建下启动，只监听 127.0.0.1 的随机端口。
- 正式发布构建不会启动这个接口。
- relayctl 自己不会启动、也不会重启 Relay Desk 应用，请先自行把应用跑起来。

## 使用

先解包，再进入目录：

    tar -xzf relayctl-macos-${arch}.tar.gz
    cd macos-${arch}
    ./relayctl --help

本机只有一个会话时，直接查询：

    ./relayctl sessions
    ./relayctl capabilities
    ./relayctl state
    ./relayctl projects
    ./relayctl identities
    ./relayctl panels
    ./relayctl windows
    ./relayctl workspaces

带选择器的单项查询（省略选择器时返回应用当前选择的那一项）：

    ./relayctl project --project PROJECT_ID
    ./relayctl identity --identity IDENTITY_ID
    ./relayctl panel --identity IDENTITY_ID
    ./relayctl window --window WINDOW_ID
    ./relayctl workspace --workspace WORKSPACE_ID

响应为 JSON，格式为 {"ok": true, "data": ...} 或
{"ok": false, "error": {"code": ..., "message": ...}}。

## 会话描述文件与保密

sessions 只列出本机会话描述文件的路径、pid 和 endpoint，不做任何网络请求。

会话描述文件内含 bearer token，文件权限为 600，属于凭据：

- 不要上传、转发、粘贴到聊天或提交进版本库。
- 不要 cat 整个文件，也不要把 token 打印到终端日志。
- 校验完整性请在解包目录执行 shasum -c SHA256SUMS。

同时运行多个开发实例时，必须用 --session 指定某一个描述文件，且要放在子命令之前：

    ./relayctl --session /path/to/automation-xxxx.json state

也可以用环境变量 RELAY_DESK_SESSION 代替 --session。仅有一个会话时才可以省略。

## 校验

    shasum -a 256 relayctl README.md   # 与 SHA256SUMS 比对
    shasum -c SHA256SUMS

## 范围说明

- 只编译本机架构，不提供 universal 二进制，也不在 arm64 上交叉编译 x86_64。
- 本产物未做 Developer ID 签名与公证，属于本地/内部验收构建。
- P0 协议只读：capabilities、state、projects、project、identities、identity、
  panels、panel、windows、window、workspaces、workspace。写操作与 DOM/截图能力
  尚未开放。
README

# Keep only the three known files in the archive: no session descriptor, no
# token, no .env, no package_config.json, no source.
(
  cd "$stage_dir"
  shasum -a 256 relayctl README.md >SHA256SUMS
)

note "staged ${stage_dir}"

# ---------------------------------------------------------------- archive ----
# Built inside the private temp directory and moved into place, so a failed
# tar never truncates a previously good archive.
tar -czf "${build_tmp}/relayctl-macos-${arch}.tar.gz" \
  -C "$output_root" \
  "macos-${arch}/relayctl" \
  "macos-${arch}/README.md" \
  "macos-${arch}/SHA256SUMS"

mv -f "${build_tmp}/relayctl-macos-${arch}.tar.gz" "$archive"

note ""
note "artifact  ${stage_dir}/relayctl"
note "          ${stage_dir}/README.md"
note "          ${stage_dir}/SHA256SUMS"
note "          ${archive}"
note ""
note "verify    (cd \"${stage_dir}\" && shasum -c SHA256SUMS)"
note "smoke     \"${stage_dir}/relayctl\" --help"
