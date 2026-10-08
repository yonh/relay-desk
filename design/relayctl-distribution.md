# relayctl 打包与分发（macOS）

本文件描述如何重复地产出 relayctl 自动化 CLI 的 macOS 可执行文件，以及第三方拿到压缩包后如何使用。

- 构建脚本：`tool/build_relayctl.sh`
- CLI 入口：`tool/relayctl.dart`（仅依赖 Dart SDK，不依赖 Flutter）
- 协议上下文：`design/automation-roadmap.md` 的 P0 协议 v1，参考实现 `tool/relayctl.py`

## 当前状态（务必先读）

- 这是一次**本地/内部验收构建**：产物未做 Developer ID 签名、未做 Apple 公证。
  面向外部发布所需的签名、公证、notarization 与自动更新属于后续阶段，不在本切片范围内。
- 应用侧接口仍是 **macOS debug 构建 + opt-in**：只有以
  `--dart-define=RELAY_DESK_AUTOMATION=true` 启动的 debug 实例才会开启
  `POST /v1/command` 服务（仅监听 127.0.0.1 随机端口）。正式发布版**不会启动**该服务，
  目前也没有面向用户的 UI 开关。本文件不提供任何关闭系统安全机制的说明。
- **本机架构专用**：脚本按 `uname -m` 决定产物，arm64 得到 `macos-arm64`，
  x86_64 得到 `macos-x64`。不做 universal 二进制，也不在 arm64 上交叉编译 x86_64；
  需要另一种架构时，在该架构的机器上重跑本脚本。
- Python 旧 CLI（`tool/relayctl.py`）暂时保留，作为协议参考与回归对照；
  新默认入口是编译出来的原生可执行文件 `relayctl`。

## 开发者：编译

应用接口仅由显式启用的 macOS debug 实例提供：

```bash
flutter run -d macos --dart-define=RELAY_DESK_AUTOMATION=true
```

此命令会启动应用实例，应按调试安排执行；下面的 CLI 编译不会启动应用。

```bash
cd /Users/yonh/workspaces/flutter/relay-desk
bash tool/build_relayctl.sh
```

自定义输出根目录：

```bash
bash tool/build_relayctl.sh --output-dir /tmp/relayctl-out
```

`--output-dir` 是本脚本唯一的功能参数；`--help` / `-h` 只打印用法，并且在探测系统、
编译器与入口文件之前就返回，完全离线、不产生任何产物。`--output-dir` 接受绝对或相对路径
（相对路径按当前工作目录解析，父目录不存在时由脚本递归创建），传空值或重复传参按用法错误
（exit 2）处理。

可选环境变量 `DART_BIN` 指向一个 Dart 可执行文件（单个路径，含空格会被正确引用）；
未设置时使用 `command -v dart`。裸命令名先经 PATH 解析、给定的文件路径先绝对化，
然后才对解析结果检查可执行性。

脚本要点：

- 用 `mktemp -d` 建立私有临时目录，`trap` 只清理自己那一个目录；不会删除用户整个输出目录，
  也不会碰应用的 `build/` 或其他既有产物。
- 用一份隔离的空 `package_config.json`（`configVersion: 2`，`packages: []`）执行
  `dart compile exe --packages=... -o ... tool/relayctl.dart`，避免引入 Flutter 的
  包解析与 native-asset 构建。
- 编译发生在临时目录，成功后才落到暂存目录；压缩包先在临时目录生成再移动就位。
  任一步失败都会以非零码退出并停止，绝不继续分发旧的或半成品产物。
- 安装到暂存目录之前，先用 `file -b` 校验编译产物的架构与 `uname -m` 选出的标签一致；
  universal 二进制、混架构 Dart SDK 或 Rosetta 转换都会直接报错退出，而不是把产物错标成
  另一种架构。
- 只用 `shasum -a 256` 生成 `SHA256SUMS`；压缩包内固定只有三个文件，不含会话描述文件、
  token、`.env`、`package_config.json` 或源码。
- 不使用 `eval`。

### 产物路径

默认输出根目录是 `<repo>/build/relayctl`（未指定 `--output-dir` 时）：

| 路径 | 内容 |
|---|---|
| `build/relayctl/macos-arm64/relayctl` | 本机架构的可执行文件（0755） |
| `build/relayctl/macos-arm64/README.md` | 面向第三方的中文使用说明，随包分发 |
| `build/relayctl/macos-arm64/SHA256SUMS` | `relayctl` 与 `README.md` 的 sha256 |
| `build/relayctl/relayctl-macos-arm64.tar.gz` | 只含上述三个文件的压缩包 |

`macos-x64` 同理，只是目录名与压缩包名里的架构标识不同。

## 第三方：解包与使用

### 开发侧协议回归

现有协议用例可同时验证参考入口与独立二进制：

```bash
python3 -m unittest discover -s test/tool -p '*_test.py' -v
RELAYCTL_BIN="$PWD/build/relayctl/macos-arm64/relayctl" \
  python3 -m unittest discover -s test/tool -p '*_test.py' -v
```

以上命令在仓库根目录执行；Intel Mac 将路径改为 `macos-x64`。
Python 只用于开发侧测试驱动，二进制的运行和分发无需 Python。
用例连接临时 loopback 服务，不接触真实应用或会话文件。

### 使用分发包

```bash
tar -xzf relayctl-macos-arm64.tar.gz
cd macos-arm64
shasum -c SHA256SUMS
./relayctl --help
```

`relayctl` 是自包含可执行文件，Dart 运行时已打包进去，**不需要安装 Python、Dart 或 Flutter**
（参考
[dart compile exe 自包含可执行文件](https://dart.dev/tools/dart-compile#self-contained-executables-exe)）。

常用命令（省略选择器时返回应用当前选择的那一项）：

```bash
./relayctl sessions
./relayctl capabilities
./relayctl state
./relayctl projects
./relayctl identities
./relayctl panels
./relayctl windows
./relayctl workspaces

./relayctl project --project PROJECT_ID
./relayctl identity --identity IDENTITY_ID
./relayctl panel --identity IDENTITY_ID
./relayctl window --window WINDOW_ID
./relayctl workspace --workspace WORKSPACE_ID
```

前提条件由调用方自行满足：Relay Desk 需要有一个已经以 opt-in 方式启动的 macOS debug 实例在运行
（如何启动见上面的“开发者：编译”一节），然后再执行 CLI。
**CLI 不会启动应用，也不会重启应用。**

### 会话与保密

- 会话描述文件含 bearer token、权限为 600，属于凭据：不要上传、转发、贴进聊天或提交进仓库，
  也不要打印整个文件或其中的 token。
- `sessions` 只列出本地会话描述文件的路径、pid 与 endpoint，不发网络请求。
- 同时运行多个开发实例时，必须在子命令**之前**用 `--session` 指定某一个会话文件，
  或用环境变量 `RELAY_DESK_SESSION`：

  ```bash
  ./relayctl --session /path/to/automation-xxxx.json state
  ```

  只有一个会话时才可以省略。

## 打包本身的验证方式

无需业务 UI 即可验证打包结果：

1. `bash -n tool/build_relayctl.sh`（语法检查）。
2. `bash tool/build_relayctl.sh --help`（离线、无产物）。
3. CLI 源码评审通过后再执行真实编译，然后直接运行产物自身的 `--help`
   （`build/relayctl/macos-arm64/relayctl --help`，不通过 `bash` 执行）。
4. 之后用假本地 HTTP server 做协议级测试（`capabilities` / `state` / 显式 ID / 认证失败 /
   未知 op），同样不需要启动真实应用，也不需要重启用户当前实例。

本轮已完成源码评审、静态分析、实际 ARM64 编译、产物 `--help` 运行和 SHA256SUMS 校验。
压缩包确认仅包含可执行文件、README.md 与 SHA256SUMS；可执行文件在移除 Homebrew/Dart 路径的 PATH 下正常打印帮助。
阶段收尾已用同一套 16 项协议用例分别验证 Python 参考入口和编译后的独立 ARM64 CLI，均通过。
测试使用临时 loopback 服务，未连接真实应用接口或操作业务页面；真实应用运行态验收仍待完成。
