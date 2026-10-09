/// Relay Desk automation CLI (`relayctl`) — SDK-only standalone entrypoint.
///
/// `dart compile exe` turns this one file into a self-contained macOS
/// executable (see tool/build_relayctl.sh), so the recipient needs neither
/// Python, nor Dart, nor Flutter installed. Only dart:async, dart:convert and
/// dart:io are imported: no `package:` imports, no pubspec dependency, no
/// Python execution and no Flutter at runtime.
///
/// Scope is protocol v2 (design/automation-roadmap.md): the read-only
/// operations plus the whitelisted writes `activate_project` (issue #31)
/// and `open_panel` (issue #32), and the local `sessions` listing. No other mutable operation is exposed. An
/// absent selector defers to the backend's current selection — this CLI
/// never guesses a project, identity, window or workspace and never
/// inspects AppKit. `screenshot`, `media` and `errors` are the exceptions
/// to the absent-selector rule: each requires an explicit --identity
/// (screenshot also a local --output path), because a page-level read
/// without a named target would silently sample whatever happens to be
/// selected; `dom` is held to the same rule. `activate_project` likewise requires an explicit --project —
/// switching "whatever is selected" by name would hit the wrong project.
///
/// Session descriptors are credentials. Only `file`, `pid` and `endpoint` are
/// ever printed; the bearer token is neither logged nor included in errors.
///
/// [runRelayctl] takes its sinks and environment as arguments so the CLI can be
/// exercised offline. `main` only wires them to stdout, stderr and
/// Platform.environment and copies the returned exit code into `exitCode`;
/// nothing in this file ever mutates the process environment.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Wire bound shared with the server's request check.
const int _commandLimitBytes = 64 * 1024;

/// Bound on the whole request/response exchange, not on each chunk.
const Duration _transportTimeout = Duration(seconds: 13);

const String _sessionVariable = 'RELAY_DESK_SESSION';

/// `sessions` reads local descriptors only; it must never touch a server.
const String _sessionsOp = 'sessions';

const JsonEncoder _prettyEncoder = JsonEncoder.withIndent('  ');

class _Selector {
  const _Selector(
    this.flag,
    this.field,
    this.help, {
    this.integer = false,
    this.local = false,
    this.required = false,
  });

  /// Command-line flag, for example `--project`.
  final String flag;

  /// Request field the value is forwarded as, for example `projectId`.
  final String field;

  final String help;

  /// Whether the raw value must parse as an integer before dispatch.
  final bool integer;

  /// Local CLI argument consumed by the client itself (e.g. `--output`):
  /// validated here but never forwarded into the command JSON, so the server
  /// never receives a local filesystem path to write to.
  final bool local;

  /// Whether omitting the flag is a usage error.
  final bool required;
}

class _Command {
  const _Command(this.op, this.summary, [this.selectors = const <_Selector>[]]);

  final String op;
  final String summary;
  final List<_Selector> selectors;
}

const _projectSelector = _Selector(
  '--project',
  'projectId',
  'Exact projectId; omit for the current project',
);
const _identitySelector = _Selector(
  '--identity',
  'identityId',
  'Exact identityId; omit for the selected identity',
);
const _windowSelector = _Selector(
  '--window',
  'windowId',
  'Exact native windowId; omit for the key window',
  integer: true,
);
const _workspaceSelector = _Selector(
  '--workspace',
  'workspaceId',
  'Exact workspaceId; omit for the current workspace',
);
const _outputSelector = _Selector(
  '--output',
  'outputPath',
  'Local file path for the PNG; required, never sent to the app',
  local: true,
  required: true,
);
const _requiredIdentitySelector = _Selector(
  '--identity',
  'identityId',
  'Exact identityId; required, no selection fallback',
  required: true,
);
const _requiredProjectSelector = _Selector(
  '--project',
  'projectId',
  'Exact projectId; required, no name matching',
  required: true,
);

/// The automation surface: read-only ops plus the whitelisted writes
/// (issue #31). Insertion order is the help listing order.
const List<_Command> _commands = <_Command>[
  _Command(
    'sessions',
    'List local session descriptors; never contacts a server',
  ),
  _Command(
    'capabilities',
    'Protocol version, supported operations and limitations',
  ),
  _Command(
    'state',
    'Current selection plus native focus, captured in one response',
  ),
  _Command('projects', 'Every project in the database'),
  _Command('project', 'One project, or the current project', <_Selector>[
    _projectSelector,
  ]),
  _Command(
    'identities',
    'Identities of one project, or of the current project',
    <_Selector>[_projectSelector],
  ),
  _Command(
    'identity',
    'One identity, or the currently selected identity',
    <_Selector>[_identitySelector],
  ),
  _Command(
    'panels',
    'Resident panels, optionally filtered to one project',
    <_Selector>[_projectSelector],
  ),
  _Command('panel', 'One panel, or the currently selected panel', <_Selector>[
    _identitySelector,
  ]),
  _Command('windows', 'Every application NSWindow and native web view'),
  _Command(
    'window',
    'One window, or the key window; no main-window fallback',
    <_Selector>[_windowSelector],
  ),
  _Command(
    'workspaces',
    'Saved layouts of one project, or of the current project',
    <_Selector>[_projectSelector],
  ),
  _Command(
    'workspace',
    'One saved layout, or the current named layout',
    <_Selector>[_workspaceSelector],
  ),
  _Command(
    'screenshot',
    'Viewport PNG of one identity panel; --identity and --output required',
    <_Selector>[_requiredIdentitySelector, _outputSelector],
  ),
  _Command(
    'media',
    'Media-element state of one identity panel; --identity required',
    <_Selector>[_requiredIdentitySelector],
  ),
  _Command(
    'errors',
    'Buffered page JS errors of one identity panel; --identity required',
    <_Selector>[_requiredIdentitySelector],
  ),
  _Command(
    'activate_project',
    'Switch the app to an existing project; --project required',
    <_Selector>[_requiredProjectSelector],
  ),
  _Command(
    'open_panel',
    'Open the panel of an existing identity; --identity required',
    <_Selector>[_requiredIdentitySelector],
  ),
  _Command(
    'navigate',
    'Navigate an open panel to a URL; --identity and --url required',
    <_Selector>[
      _requiredIdentitySelector,
      _Selector(
        '--url',
        'url',
        'http(s) URL; bare hosts normalize like the address bar',
        required: true,
      ),
    ],
  ),
  _Command(
    'reload',
    'Reload an open panel\'s current URL; --identity required',
    <_Selector>[_requiredIdentitySelector],
  ),
  _Command(
    'dom',
    'Bounded DOM summary of one identity panel; --identity required',
    <_Selector>[_requiredIdentitySelector],
  ),
  _Command(
    'dom_find',
    'Find elements by text/role/selector; --identity plus one criterion',
    <_Selector>[
      _requiredIdentitySelector,
      _Selector('--text', 'text', 'Visible text to find; use with --match'),
      _Selector('--role', 'role', 'ARIA role to find (e.g. button, link)'),
      _Selector('--name', 'name', 'Accessible name filter for --role'),
      _Selector('--selector', 'selector', 'CSS selector to find'),
      _Selector('--match', 'match', "exact or contains (default contains)"),
      _Selector('--frame', 'frame', 'Frame label to search (main, f0, …)'),
    ],
  ),
  _Command(
    'dom_inspect',
    'Inspect one element by ref; --identity --ref --document-id required',
    <_Selector>[
      _requiredIdentitySelector,
      _Selector('--ref', 'ref', 'Element ref <frame>.<position> from dom/dom_find'),
      _Selector('--document-id', 'documentId', 'documentId that issued the ref'),
    ],
  ),
];

/// A validated descriptor. [token] is a credential and never reaches output.
typedef _Descriptor = ({
  String file,
  int pid,
  String endpoint,
  Uri uri,
  String token,
});

/// A parse result: never both a command and a help request.
class _Invocation {
  const _Invocation(this.command, this.selectors, this.session);

  final _Command command;

  /// Raw selector values, keyed by flag, in the order they were given.
  final Map<String, String> selectors;

  /// Explicit `--session` value, if one was given.
  final String? session;
}

class _UsageError implements Exception {
  const _UsageError(this.message);

  final String message;
}

class _HelpRequested implements Exception {
  const _HelpRequested(this.command);

  /// `null` asks for the global help, otherwise the command's own help.
  final _Command? command;
}

/// A client-side failure: reported as `client_error` on stderr with exit 1.
class _ClientError implements Exception {
  const _ClientError(this.message);

  /// Must stay free of descriptor content and credentials.
  final String message;
}

Future<void> main(List<String> args) async {
  exitCode = await runRelayctl(args);
}

/// Runs the CLI and returns its exit code: 0 success, 1 client or server
/// error, 2 usage error.
Future<int> runRelayctl(
  List<String> args, {
  Map<String, String>? environment,
  StringSink? output,
  StringSink? errorOutput,
}) async {
  final out = output ?? stdout;
  final err = errorOutput ?? stderr;
  final env = environment ?? Platform.environment;
  try {
    final invocation = _parse(args);
    return await _execute(invocation, out, env);
  } on _HelpRequested catch (help) {
    final command = help.command;
    if (command == null) {
      _writeGlobalHelp(out);
    } else {
      _writeCommandHelp(out, command);
    }
    return 0;
  } on _UsageError catch (usage) {
    err.writeln('relayctl: ${usage.message}');
    err.writeln("run 'relayctl --help' for usage");
    return 2;
  } on _ClientError catch (failure) {
    _writeClientError(err, failure.message);
    return 1;
  } on FileSystemException catch (failure) {
    _writeClientError(err, _filesystemMessage(failure));
    return 1;
  } on SocketException {
    // The message can quote untrusted peer data, so it never reaches output.
    _writeClientError(err, 'Cannot reach the automation endpoint');
    return 1;
  } on HttpException {
    _writeClientError(err, 'The automation endpoint failed the request');
    return 1;
  } on TimeoutException {
    _writeClientError(
      err,
      'The automation endpoint did not answer within 13 seconds',
    );
    return 1;
  } on FormatException {
    _writeClientError(err, _unexpectedResponseMessage);
    return 1;
  }
}

Future<int> _execute(
  _Invocation invocation,
  StringSink out,
  Map<String, String> env,
) async {
  if (invocation.command.op == _sessionsOp) {
    // Discovery only reads local descriptors; it must not resolve a session
    // and must not open a connection.
    out.writeln(
      _prettyEncoder.convert(<String, Object?>{
        'sessions': _sessionSummaries(
          await _discoverDescriptors(_homeDirectory(env)),
        ),
      }),
    );
    return 0;
  }
  final session = await _resolveSession(invocation.session, env);
  final response = await _sendCommand(session, _buildCommand(invocation));
  if (invocation.command.op == _screenshotOp && response['ok'] == true) {
    await _writeScreenshot(response, invocation, out);
    return 0;
  }
  // Server envelopes are passed through verbatim, error envelopes included;
  // the exit code is the only thing this CLI decides.
  out.writeln(_prettyEncoder.convert(response));
  return response['ok'] == true ? 0 : 1;
}

const String _screenshotOp = 'screenshot';

/// The PNG magic bytes every PNG file starts with. A payload that fails this
/// check is not an image and is never written to --output.
const List<int> _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// Writes a screenshot response: decode the base64 payload, prove it is a
/// PNG, then write --output. The decoded bytes are validated before any file
/// is touched, so a malformed or oversized reply never leaves a corrupt file
/// behind; on a filesystem failure the partial file is removed.
Future<void> _writeScreenshot(
  Map<String, dynamic> response,
  _Invocation invocation,
  StringSink out,
) async {
  final data = response['data'];
  final output = invocation.selectors[_outputSelector.flag];
  if (data is! Map<String, dynamic> || output == null) {
    throw const _ClientError(_unexpectedResponseMessage);
  }
  final encoded = data['pngBase64'];
  if (encoded is! String || encoded.isEmpty) {
    throw const _ClientError(_unexpectedResponseMessage);
  }
  final List<int> bytes;
  try {
    bytes = base64Decode(encoded);
  } on FormatException {
    throw const _ClientError(_unexpectedResponseMessage);
  }
  if (bytes.length < _pngMagic.length ||
      !_pngMagic.asMap().entries.every((e) => bytes[e.key] == e.value)) {
    throw const _ClientError(
      'The automation endpoint returned a non-PNG screenshot',
    );
  }
  final file = File(output);
  // Write to a unique sibling temp file first, then atomically rename onto
  // the target: a failed write can never truncate or delete an existing
  // capture — cleanup only ever touches the temp file this run created.
  final tmp = File(
    '${file.absolute.path}.relayctl-$pid-${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(output);
  } catch (_) {
    try {
      await tmp.delete();
    } catch (_) {}
    rethrow;
  }
  final reported = Map<String, Object?>.from(data)
    ..remove('pngBase64')
    ..['outputPath'] = await file.resolveSymbolicLinks()
    ..['byteLength'] = bytes.length;
  out.writeln(
    _prettyEncoder.convert(<String, Object?>{'ok': true, 'data': reported}),
  );
}

/// Accepts the global `--session` before or after the operation, per-command
/// selectors after it, and `-h`/`--help` anywhere. Nothing here touches the
/// filesystem or the network, so a bad command line stays offline.
_Invocation _parse(List<String> args) {
  _Command? command;
  String? session;
  final selectors = <String, String>{};
  var index = 0;
  while (index < args.length) {
    final token = args[index];
    if (token == '--help' || token == '-h') {
      throw _HelpRequested(command);
    }
    if (token == '--session' || token.startsWith('--session=')) {
      if (session != null) {
        throw const _UsageError('--session given more than once');
      }
      if (token.startsWith('--session=')) {
        session = _optionValue(
          token.substring('--session='.length),
          '--session',
        );
      } else {
        index += 1;
        if (index >= args.length) {
          throw const _UsageError('--session requires a file path');
        }
        session = _optionValue(args[index], '--session');
      }
    } else if (command == null) {
      if (token.startsWith('-')) {
        throw _UsageError("unknown option '$token'");
      }
      command = _commandNamed(token);
    } else {
      final selector = _selectorFor(command, token);
      if (selector == null) {
        if (token.startsWith('-')) {
          final known = _selectorForAnyCommand(token);
          throw _UsageError(
            known != null
                ? "option '$token' does not apply to '${command.op}'"
                : "unknown option '$token'",
          );
        }
        throw _UsageError("unexpected argument '$token'");
      }
      if (selectors.containsKey(selector.flag)) {
        throw _UsageError("option '${selector.flag}' given more than once");
      }
      index += 1;
      if (index >= args.length) {
        throw _UsageError("option '${selector.flag}' requires a value");
      }
      final raw = args[index];
      if (selector.integer) {
        // A negative window id is still an integer; an option token is not.
        if (int.tryParse(raw) == null) {
          throw _UsageError("option '${selector.flag}' requires an integer");
        }
      } else if (raw.isEmpty || raw.startsWith('-')) {
        throw _UsageError(
          "option '${selector.flag}' requires a value, not '$raw'",
        );
      }
      selectors[selector.flag] = raw;
    }
    index += 1;
  }
  final resolved = command;
  if (resolved == null) {
    throw const _UsageError('a command is required');
  }
  for (final selector in resolved.selectors) {
    if (selector.required && !selectors.containsKey(selector.flag)) {
      throw _UsageError(
        "option '${selector.flag}' is required for '${resolved.op}'",
      );
    }
  }
  return _Invocation(
    resolved,
    Map<String, String>.unmodifiable(selectors),
    session,
  );
}

_Command _commandNamed(String token) {
  for (final command in _commands) {
    if (command.op == token) {
      return command;
    }
  }
  throw _UsageError("unknown command '$token'");
}

_Selector? _selectorFor(_Command command, String token) {
  for (final selector in command.selectors) {
    if (selector.flag == token) {
      return selector;
    }
  }
  return null;
}

_Selector? _selectorForAnyCommand(String token) {
  for (final command in _commands) {
    final selector = _selectorFor(command, token);
    if (selector != null) {
      return selector;
    }
  }
  return null;
}

/// A flag value must be present, non-empty and must not be an option token:
/// `--session --help` and `--identity --help` are usage errors, never a help
/// request and never an identifier.
String _optionValue(String value, String flag) {
  if (value.isEmpty || value.startsWith('-')) {
    throw _UsageError("option $flag requires a value, not '$value'");
  }
  return value;
}

Map<String, Object?> _buildCommand(_Invocation invocation) {
  final command = <String, Object?>{'op': invocation.command.op};
  for (final selector in invocation.command.selectors) {
    if (selector.local) {
      // Local options steer the CLI only; the server never sees them.
      continue;
    }
    final raw = invocation.selectors[selector.flag];
    if (raw == null) {
      continue;
    }
    command[selector.field] = selector.integer ? int.parse(raw) : raw;
  }
  return command;
}

String _homeDirectory(Map<String, String> env) {
  final home = env['HOME'];
  if (home == null || home.isEmpty) {
    throw const _ClientError('Cannot resolve the home directory');
  }
  return home;
}

Future<_Descriptor> _resolveSession(
  String? explicit,
  Map<String, String> env,
) async {
  final named = explicit ?? env[_sessionVariable];
  if (named != null && named.isNotEmpty) {
    return _loadDescriptor(_expandUser(named, env));
  }
  // Without an explicit choice this CLI refuses to guess between instances.
  final discovered = await _discoverDescriptors(_homeDirectory(env));
  if (discovered.length != 1) {
    throw const _ClientError(
      'Expected one running automation session; use sessions then --session FILE',
    );
  }
  return discovered.single;
}

String _expandUser(String name, Map<String, String> env) {
  if (name == '~') {
    return _homeDirectory(env);
  }
  if (name.startsWith('~/')) {
    return '${_homeDirectory(env)}/${name.substring(2)}';
  }
  return name;
}

/// Lists the two session roots the reference CLI globs, using `Directory`
/// listing rather than a shell glob, then sorts and de-duplicates the paths.
Future<List<String>> _descriptorPaths(String home) async {
  const directoryName = 'automation';
  const prefix = 'automation-';
  const suffix = '.json';
  final roots = <String>[
    '$home/Library/Containers/com.example.relayDesk/Data/Library/Application Support',
    '$home/Library/Application Support',
  ];
  final found = <String>{};
  for (final root in roots) {
    try {
      await for (final entity in Directory(root).list(followLinks: false)) {
        if (entity is! Directory) {
          continue;
        }
        final directory = Directory('${entity.path}/$directoryName');
        try {
          await for (final candidate in directory.list(followLinks: false)) {
            if (candidate is! File) {
              continue;
            }
            final name = candidate.path.split(Platform.pathSeparator).last;
            if (name.startsWith(prefix) && name.endsWith(suffix)) {
              found.add(candidate.path);
            }
          }
        } on FileSystemException {
          continue;
        }
      }
    } on FileSystemException {
      continue;
    }
  }
  final sorted = found.toList()..sort();
  return sorted;
}

/// Live descriptors only: unreadable, insecure, malformed and dead ones are
/// omitted rather than reported.
Future<List<_Descriptor>> _discoverDescriptors(String home) async {
  final found = <_Descriptor>[];
  for (final path in await _descriptorPaths(home)) {
    try {
      final descriptor = _loadDescriptor(path);
      if (await _isRunning(descriptor.pid)) {
        found.add(descriptor);
      }
    } on _ClientError {
      continue;
    } on FileSystemException {
      continue;
    }
  }
  return found;
}

/// `file`, `pid` and `endpoint` only — never the token.
List<Map<String, Object?>> _sessionSummaries(List<_Descriptor> descriptors) =>
    <Map<String, Object?>>[
      for (final descriptor in descriptors)
        <String, Object?>{
          'file': descriptor.file,
          'pid': descriptor.pid,
          'endpoint': descriptor.endpoint,
        },
    ];

/// Positive liveness probe on the given pid, using the operating system
/// `kill -0` rather than anything inside this process.
Future<bool> _isRunning(int pid) async {
  try {
    final result = await Process.run('/bin/kill', <String>['-0', '$pid']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

_Descriptor _loadDescriptor(String path) {
  final file = File(path);
  final FileStat stat;
  try {
    stat = file.statSync();
  } on FileSystemException catch (failure) {
    throw _ClientError(
      'Cannot read the session file: ${_filesystemMessage(failure)}',
    );
  }
  // 0x3f is the group and other permission bits: the descriptor holds a
  // bearer token, so anything wider than owner-only is refused before it is
  // read or transmitted.
  if (stat.mode & 0x3f != 0) {
    throw const _ClientError(
      'Session file is not private; expected permissions 600',
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException {
    throw const _ClientError('Session file is not a JSON descriptor');
  } on FileSystemException catch (failure) {
    throw _ClientError(
      'Cannot read the session file: ${_filesystemMessage(failure)}',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw const _ClientError('Session file is not a JSON descriptor');
  }
  if (decoded['version'] != 1) {
    throw const _ClientError('Unsupported session descriptor version');
  }
  final token = decoded['token'];
  if (token is! String || token.isEmpty) {
    throw const _ClientError('Session file carries no token');
  }
  final pid = decoded['pid'];
  if (pid is! int || pid <= 0) {
    throw const _ClientError('Session file carries no usable pid');
  }
  final uri = _loopbackEndpoint(decoded['endpoint']);
  if (uri == null) {
    throw const _ClientError(
      'Session endpoint must be a loopback IPv4 HTTP server',
    );
  }
  return (
    file: path,
    pid: pid,
    endpoint: uri.toString(),
    uri: uri,
    token: token,
  );
}

/// Accepts only `http://127.0.0.1:<port>` with no path, query, fragment or
/// userinfo, so a descriptor cannot steer this CLI at a remote host or embed
/// credentials of its own.
Uri? _loopbackEndpoint(Object? raw) {
  if (raw is! String || raw.isEmpty) {
    return null;
  }
  try {
    final uri = Uri.parse(raw);
    if (uri.scheme != 'http' || uri.host != '127.0.0.1') {
      return null;
    }
    if (!uri.hasPort) {
      return null;
    }
    final port = uri.port;
    if (port < 1 || port > 65535) {
      return null;
    }
    if (uri.path.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  } on FormatException {
    return null;
  }
}

Future<Map<String, dynamic>> _sendCommand(
  _Descriptor session,
  Map<String, Object?> command,
) async {
  final encoded = utf8.encode(jsonEncode(command));
  if (encoded.length > _commandLimitBytes) {
    throw const _ClientError('Command limit is 64 KiB');
  }
  final client = HttpClient();
  // The transport is local and must not travel through a machine proxy.
  client.findProxy = (_) => 'DIRECT';
  client.connectionTimeout = _transportTimeout;
  try {
    return await _exchange(client, session, encoded).timeout(_transportTimeout);
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> _exchange(
  HttpClient client,
  _Descriptor session,
  List<int> encoded,
) async {
  final request = await client.postUrl(
    session.uri.replace(path: '/v1/command'),
  );
  // Refuse redirects rather than replay the bearer header elsewhere.
  request.followRedirects = false;
  request.headers.contentType = ContentType(
    'application',
    'json',
    charset: 'utf-8',
  );
  request.headers.set(
    HttpHeaders.authorizationHeader,
    'Bearer ${session.token}',
  );
  request.add(encoded);
  final response = await request.close();
  final status = response.statusCode;
  // Every 3xx is refused before the body is read, so the redirect target is
  // never contacted and the bearer header is never replayed there.
  if (status >= 300 && status < 400) {
    throw const _ClientError('Automation endpoint redirected; request refused');
  }
  final body = await response.transform(utf8.decoder).join();
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const _ClientError(_unexpectedResponseMessage);
  }
  if (decoded is! Map<String, dynamic> || decoded['ok'] is! bool) {
    throw const _ClientError(_unexpectedResponseMessage);
  }
  // A success flag on a failed status is not trustworthy, so it never becomes
  // exit 0. A valid `ok: false` envelope is preserved either way and decides
  // the exit code.
  if (decoded['ok'] == true && (status < 200 || status >= 300)) {
    throw const _ClientError(
      'The automation endpoint reported a success with a failed status',
    );
  }
  return decoded;
}

String _filesystemMessage(FileSystemException failure) =>
    failure.osError?.message ?? failure.message;

/// Curated, stable and free of anything the peer sent.
const String _unexpectedResponseMessage =
    'The automation endpoint returned an unexpected response';

void _writeClientError(StringSink err, String message) {
  err.writeln(
    jsonEncode(<String, Object?>{
      'ok': false,
      'error': <String, Object?>{'code': 'client_error', 'message': message},
    }),
  );
}

void _writeGlobalHelp(StringSink out) {
  final listing = _commands
      .map((command) => '  ${command.op.padRight(13)}${command.summary}')
      .join('\n');
  out.writeln('''
usage: relayctl [--session FILE] <command> [selector ...]

Relay Desk's opt-in, authenticated local automation transport, protocol v1.

P0 speaks metadata reads only. Absence of a selector means "the backend's
current selection": this CLI never guesses a project, identity, window or
workspace on the caller's behalf, and never inspects AppKit itself.

Options:
  --session FILE  Session file; otherwise RELAY_DESK_SESSION or discovery
  -h, --help      Show this help and exit

Commands:
$listing

Sessions only exist while a macOS debug build runs with
--dart-define=RELAY_DESK_AUTOMATION=true. Run 'relayctl sessions' to list local
descriptors by file, pid and endpoint; the token inside them is never printed.
Exit status: 0 success, 1 client or server error, 2 usage error.''');
}

void _writeCommandHelp(StringSink out, _Command command) {
  final buffer = StringBuffer()
    ..writeln('usage: relayctl [--session FILE] ${command.op} [selector ...]')
    ..writeln()
    ..writeln('${command.summary}.')
    ..writeln();
  if (command.op == _sessionsOp) {
    buffer.writeln('This command never contacts a server.');
  } else if (command.selectors.isEmpty) {
    buffer.writeln('This command takes no selector.');
  } else {
    buffer.writeln('Selectors:');
    for (final selector in command.selectors) {
      final value = selector.integer ? 'WINDOW_ID' : 'VALUE';
      buffer.writeln('  ${selector.flag} $value'.padRight(24) + selector.help);
    }
    buffer
      ..writeln()
      ..writeln(
        'Omit every selector to defer to the backend\'s current selection.',
      );
  }
  buffer
    ..writeln()
    ..writeln("Run 'relayctl --help' for the full command list.");
  out.write(buffer.toString());
}
