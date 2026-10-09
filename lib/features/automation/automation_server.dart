/// Local control transport. It owns authentication and request bounds; the
/// workspace dispatch owns panel identity and platform capabilities.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

typedef AutomationDispatch = Future<Object?> Function(Map<String, dynamic>);

/// Read operations: pure snapshots, never mutate workspace, UI selection or
/// native state (design/automation-roadmap.md).
const automationReadOperations = <String>{
  'capabilities',
  'state',
  'projects',
  'project',
  'identities',
  'identity',
  'panels',
  'panel',
  'windows',
  'window',
  'workspaces',
  'workspace',
  'screenshot',
  'media',
  'errors',
  'dom',
  'dom_find',
  'dom_inspect',
};

/// Write operations admitted by this transport (issue #31). Each one mutates
/// exactly one existing resource through the same code path the UI uses —
/// never through data-layer shortcuts. Anything not listed here is rejected
/// before dispatch, so unlisted mutations can never reach an execution path.
const automationWriteOperations = <String>{
  'activate_project',
  'open_panel',
  'navigate',
  'reload',
  'click',
  'input',
  'key',
  'scroll',
  'back',
};

/// Every operation the transport serves.
const automationOperations = <String>{
  ...automationReadOperations,
  ...automationWriteOperations,
};

class AutomationFailure implements Exception {
  final String code;
  final String message;
  final int status;
  const AutomationFailure(this.code, this.message, {this.status = 400});
}

class AutomationServer {
  AutomationServer({
    required this.dispatch,
    this.commandTimeout = const Duration(seconds: 10),
    this.requestTimeout = const Duration(seconds: 5),
  });

  final AutomationDispatch dispatch;
  final Duration commandTimeout;

  /// How long a command body may take to arrive before the request is
  /// abandoned. Separate from [commandTimeout]: a body that never arrives ran
  /// nothing, so it is answered as a request failure, not an execution one.
  final Duration requestTimeout;

  /// Lock set for the current started server. [close] replaces it so a command
  /// still running from the previous session cannot lock or unlock this one.
  var _busy = <String>{};
  HttpServer? _server;
  File? _sessionFile;
  String? _token;

  Future<void> start(Directory directory) async {
    if (_server != null) return;
    final random = Random.secure();
    _token = base64Url.encode(List.generate(32, (_) => random.nextInt(256)));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    try {
      await directory.create(recursive: true);
      final file = File('${directory.path}/automation-${server.port}.json');
      _sessionFile = file;
      // Create empty, restrict permissions, then write the credential.
      await file.create();
      if (!Platform.isWindows) {
        final result = await Process.run('chmod', ['600', file.path]);
        if (result.exitCode != 0) {
          throw const AutomationFailure(
            'session_permissions',
            'Cannot protect session file',
          );
        }
      }
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'endpoint': 'http://127.0.0.1:${server.port}',
          'token': _token,
          'pid': pid,
        }),
      );
      server.listen((request) => unawaited(_handle(request)));
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<void> _handle(HttpRequest request) async {
    // Bind this request to the lock set of the session that accepted it, so a
    // restart mid-flight keeps the two sessions independent.
    final busy = _busy;
    try {
      // A business page must not be able to drive this privileged transport.
      if (request.headers.value('origin') != null ||
          request.headers.value('authorization') != 'Bearer $_token') {
        throw const AutomationFailure(
          'unauthorized',
          'Local client authentication required',
          status: 401,
        );
      }
      if (request.method != 'POST' || request.uri.path != '/v1/command') {
        throw const AutomationFailure(
          'not_found',
          'Use POST /v1/command',
          status: 404,
        );
      }
      if (request.headers.contentType?.mimeType != 'application/json') {
        throw const AutomationFailure(
          'content_type',
          'Use application/json',
          status: 415,
        );
      }
      // The body is read through a future rather than `request.timeout(...)`: a
      // timed-out stream cancels the request, which tears the connection down
      // before a reply can be flushed, so the client would see a dropped socket
      // instead of the rejection. A future timeout leaves the read draining in
      // the background — still bounded by the 64 KiB check — while the caller
      // gets an answer.
      final bytes = <int>[];
      Future<void> readBody() async {
        await for (final chunk in request) {
          bytes.addAll(chunk);
          if (bytes.length > 65536) {
            throw const AutomationFailure(
              'request_too_large',
              'Command limit is 64 KiB',
              status: 413,
            );
          }
        }
      }

      try {
        await readBody().timeout(requestTimeout);
      } on TimeoutException {
        // The body never finished arriving, so nothing was dispatched. This is
        // deliberately not the execution-timeout envelope: there is no read to
        // observe. Any error the abandoned read raises later is consumed by the
        // future this already settled.
        //
        // The read is still open, so this connection has nothing left to say:
        // drop it instead of holding a half-sent body open until the client
        // gives up.
        request.response.persistentConnection = false;
        throw const AutomationFailure(
          'request_timeout',
          'Command body was not received in time',
          status: 408,
        );
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const AutomationFailure(
          'invalid_command',
          'Expected a JSON object',
        );
      }
      final op = decoded['op'];
      if (op is! String) {
        throw const AutomationFailure(
          'invalid_argument',
          'op must be a string',
        );
      }
      // Reject operations outside the read+write whitelist before they can
      // reach dispatch.
      if (!automationOperations.contains(op)) {
        throw const AutomationFailure(
          'unsupported_operation',
          'Operation is not on the automation whitelist',
        );
      }
      // Lock key per target kind. Project activation is serialized under one
      // key regardless of which project is requested: two concurrent
      // activations must not last-writer-wins silently, so the second gets
      // panel_busy rather than an ambiguous double success.
      final key = switch (op) {
        'activate_project' => '_project',
        // open_panel also mutates the project-scoped workspace (it writes
        // workspace.selectedProjectId via ensurePanel), so it must share
        // the project mutex with activate_project rather than locking on
        // the identity alone — otherwise an activation and a panel open
        // can interleave and split the UI/workspace project markers.
        'open_panel' => '_project',
        _ => decoded['identityId']?.toString() ?? '_inventory',
      };
      if (!busy.add(key)) {
        throw const AutomationFailure(
          'panel_busy',
          'A command is still running for this target',
          status: 409,
        );
      }
      final execution = Future<Object?>.sync(() => dispatch(decoded));
      // Keep the target locked until the query finishes, even if the HTTP
      // caller times out. A timeout cannot cancel a metadata read that has
      // already started.
      unawaited(
        execution.then<void>(
          (_) {
            busy.remove(key);
          },
          onError: (Object error, StackTrace stack) {
            busy.remove(key);
          },
        ),
      );
      final data = await execution.timeout(commandTimeout);
      _reply(request, 200, {'ok': true, 'data': data});
    } on AutomationFailure catch (error) {
      _reply(request, error.status, {
        'ok': false,
        'error': {'code': error.code, 'message': error.message},
      });
    } on TimeoutException {
      _reply(request, 504, {
        'ok': false,
        'error': {
          'code': 'timeout',
          'message': 'Execution may still be running; observe before retrying',
          'mayHaveExecuted': true,
        },
      });
    } on FormatException {
      _reply(request, 400, {
        'ok': false,
        'error': {'code': 'invalid_json', 'message': 'Invalid JSON command'},
      });
    } catch (_) {
      _reply(request, 500, {
        'ok': false,
        'error': {
          'code': 'command_failed',
          'message': 'Command failed; check local diagnostics',
        },
      });
    } finally {
      await request.response.close();
    }
  }

  void _reply(HttpRequest request, int status, Map<String, Object?> value) {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('Cache-Control', 'no-store');
    request.response.write(jsonEncode(value));
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
    // A later start must begin with no locks: handlers from the session that
    // just closed release the set they captured, never this new one.
    _busy = <String>{};
    final file = _sessionFile;
    if (file != null && await file.exists()) await file.delete();
    _sessionFile = null;
    _token = null;
  }
}
