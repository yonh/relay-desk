/// Offline transport tests for the P0 automation server
/// (design/automation-roadmap.md).
///
/// The server binds a real loopback port inside a temporary directory and is
/// spoken to by a real `HttpClient`, so authentication, Origin refusal, body
/// bounds and error mapping are verified on the wire rather than through
/// internal calls. Dispatch is a stub: this file covers the transport, while
/// the query layer is covered by automation_queries_test.dart.
///
/// Nothing here touches the native app, an external host, a global profile or
/// any environment file. Every server lives in its own temporary directory,
/// which is removed again when the test ends.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:relay_desk/features/automation/automation_server.dart';

/// A reply captured off the socket.
class _Reply {
  _Reply(this.status, this.headers, this.text);

  factory _Reply.from(HttpClientResponse response, String text) {
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values.join(', ');
    });
    return _Reply(response.statusCode, headers, text);
  }

  /// Parses a complete raw HTTP/1.1 response, the shape a socket read gives.
  factory _Reply.fromRaw(String response) {
    final split = response.indexOf('\r\n\r\n');
    final head = response.substring(0, split);
    final body = response.substring(split + 4);
    final status = int.parse(head.split('\r\n').first.split(' ')[1]);
    final text = head.toLowerCase().contains('transfer-encoding: chunked')
        ? _dechunk(body)
        : body;
    return _Reply(status, const <String, String>{}, text);
  }

  static String _dechunk(String body) {
    final out = StringBuffer();
    var rest = body;
    while (rest.isNotEmpty) {
      final eol = rest.indexOf('\r\n');
      if (eol < 0) break;
      final size = int.parse(
        rest.substring(0, eol).split(';').first,
        radix: 16,
      );
      if (size == 0) break;
      final start = eol + 2;
      out.write(rest.substring(start, start + size));
      rest = rest.substring(start + size + 2);
    }
    return out.toString();
  }

  final int status;
  final Map<String, String> headers;
  final String text;

  Map<String, dynamic> get json => jsonDecode(text) as Map<String, dynamic>;

  /// `error.code` of a failure envelope, or null when the call succeeded.
  String? get code {
    final decoded = jsonDecode(text);
    if (decoded is! Map || decoded['ok'] != false) return null;
    final error = decoded['error'];
    return error is Map ? error['code'] as String? : null;
  }

  Map<String, dynamic> get error =>
      (json['error'] as Map).cast<String, dynamic>();

  @override
  String toString() => '$status $text';
}

/// A started server, its session descriptor and one loopback client.
class _Transport {
  _Transport._({
    required this.directory,
    required this.server,
    required this.sessionFile,
    required this.descriptor,
    required this.client,
  });

  final Directory directory;
  final AutomationServer server;
  File sessionFile;
  Map<String, dynamic> descriptor;
  final HttpClient client;

  String get endpoint => descriptor['endpoint'] as String;
  String get token => descriptor['token'] as String;

  /// A second client, for talking to a restarted server without reusing a
  /// pooled connection that the previous session destroyed.
  HttpClient newClient() {
    final created = HttpClient();
    addTearDown(() => created.close(force: true));
    return created;
  }

  /// Re-reads the descriptor, which carries a new port and token per start.
  Future<void> refreshSession() async {
    final files = directory.listSync().whereType<File>().toList();
    expect(files, hasLength(1), reason: 'exactly one descriptor is published');
    sessionFile = files.single;
    descriptor =
        jsonDecode(await sessionFile.readAsString()) as Map<String, dynamic>;
  }

  /// Starts a server in a fresh temporary directory and registers cleanup for
  /// the client, the server and the directory before anything can fail.
  static Future<_Transport> start({
    required AutomationDispatch dispatch,
    Duration commandTimeout = const Duration(seconds: 5),
    Duration requestTimeout = const Duration(seconds: 5),
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'relay-desk-automation-transport',
    );
    final server = AutomationServer(
      dispatch: dispatch,
      commandTimeout: commandTimeout,
      requestTimeout: requestTimeout,
    );
    addTearDown(() async {
      await server.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    await server.start(directory);

    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final files = directory.listSync().whereType<File>().toList();
    expect(
      files,
      hasLength(1),
      reason: 'start publishes exactly one session descriptor',
    );
    final descriptor =
        jsonDecode(await files.single.readAsString()) as Map<String, dynamic>;
    return _Transport._(
      directory: directory,
      server: server,
      sessionFile: files.single,
      descriptor: descriptor,
      client: client,
    );
  }

  /// Raw wire access; every default matches a well-behaved P0 client.
  /// A null [contentType] sends no Content-Type header at all.
  Future<_Reply> request({
    String path = '/v1/command',
    String method = 'POST',
    String? authorization,
    String? origin,
    String? contentType = 'application/json',
    List<int>? body,
    HttpClient? client,
  }) async {
    final request = await (client ?? this.client).openUrl(
      method,
      Uri.parse('$endpoint$path'),
    );
    if (authorization != null) {
      request.headers.set(HttpHeaders.authorizationHeader, authorization);
    }
    if (origin != null) request.headers.set('origin', origin);
    if (contentType != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, contentType);
    }
    if (body != null) request.add(body);
    final response = await request.close();
    final text = utf8.decode(
      await response.fold<List<int>>(
        <int>[],
        (all, chunk) => all..addAll(chunk),
      ),
    );
    return _Reply.from(response, text);
  }

  /// An authenticated `POST /v1/command` carrying [command].
  Future<_Reply> command(
    Map<String, dynamic> command, {
    String? bearer,
    String? origin,
    String? contentType = 'application/json',
    HttpClient? client,
  }) => request(
    authorization: 'Bearer ${bearer ?? token}',
    origin: origin,
    contentType: contentType,
    body: utf8.encode(jsonEncode(command)),
    client: client,
  );
}

/// Permission bits of [path], read through `stat` so the check does not trust
/// the Dart process' own umask bookkeeping.
Future<String?> _permissionBits(String path) async {
  if (Platform.isWindows) return null;
  final result = await Process.run('stat', [
    Platform.isMacOS ? '-f' : '-c',
    Platform.isMacOS ? '%Lp' : '%a',
    path,
  ]);
  expect(result.exitCode, 0, reason: 'stat ${result.stderr}');
  return (result.stdout as String).trim();
}

void main() {
  group('automation transport', () {
    test(
      'serves each whitelisted read once and never echoes the token',
      () async {
        final calls = <Map<String, dynamic>>[];
        final transport = await _Transport.start(
          dispatch: (command) async {
            calls.add(command);
            return switch (command['op']) {
              'project' => {'id': 'p-1', 'name': 'Alpha'},
              'state' => {
                'project': {'id': 'p-1'},
                'selectionConsistent': true,
              },
              _ => <String, dynamic>{},
            };
          },
        );

        final project = await transport.command({'op': 'project'});
        expect(project.status, 200);
        expect(project.json, {
          'ok': true,
          'data': {'id': 'p-1', 'name': 'Alpha'},
        });

        final state = await transport.command({'op': 'state'});
        expect(state.status, 200);
        expect(state.json['data'], {
          'project': {'id': 'p-1'},
          'selectionConsistent': true,
        });

        expect(calls.map((call) => call['op']), [
          'project',
          'state',
        ], reason: 'one request reaches dispatch exactly once');
        expect(calls.singleWhere((c) => c['op'] == 'project').keys, ['op']);

        expect(state.headers['content-type'], startsWith('application/json'));
        expect(state.headers['cache-control'], 'no-store');
        for (final reply in [project, state]) {
          expect(reply.text, isNot(contains(transport.token)));
          expect(reply.text, isNot(contains('"token"')));
          for (final value in reply.headers.values) {
            expect(value, isNot(contains(transport.token)));
          }
        }
      },
    );

    test('serves exactly the documented P0 read operations', () async {
      final transport = await _Transport.start(dispatch: (_) async => null);

      for (final op in automationReadOperations) {
        final reply = await transport.command({'op': op});
        expect(reply.code, isNot('unsupported_operation'), reason: op);
        expect(reply.status, 200, reason: op);
      }

      // The transport whitelist is the P0 protocol table, shared with the query
      // layer; a mutation must never appear in it.
      expect(automationReadOperations, {
        'capabilities',
        'state',
        'projects',
        'project',
        'identities',
        'identity',
        'panels',
        'panel',
        'screenshot',
        'windows',
        'window',
        'workspaces',
        'workspace',
      });
    });

    test('refuses missing, wrong and Origin-bearing credentials', () async {
      var dispatched = 0;
      final transport = await _Transport.start(
        dispatch: (_) async {
          dispatched++;
          return {'leaked': true};
        },
      );

      final anonymous = await transport.request(
        body: utf8.encode('{"op":"state"}'),
      );
      expect(anonymous.status, 401);
      expect(anonymous.code, 'unauthorized');
      expect(anonymous.json['ok'], false);

      final wrong = await transport.command({'op': 'state'}, bearer: 'nope');
      expect(wrong.status, 401);
      expect(wrong.code, 'unauthorized');

      for (final origin in <String>[
        'https://evil.example',
        'http://127.0.0.1',
        'null',
      ]) {
        final fromPage = await transport.command({
          'op': 'state',
        }, origin: origin);
        expect(
          fromPage.status,
          401,
          reason: 'a browser Origin must never drive this transport: $origin',
        );
        expect(fromPage.code, 'unauthorized');
      }

      expect(dispatched, 0, reason: 'authentication precedes dispatch');
      expect(anonymous.text, isNot(contains(transport.token)));
    });

    test('rejects mutation and unknown operations before dispatch', () async {
      var dispatched = 0;
      final transport = await _Transport.start(
        dispatch: (_) async {
          dispatched++;
          return null;
        },
      );

      for (final op in <String>[
        'eval',
        'navigate',
        'reload',
        'click',
        'console',
        'network',
        'capabilities ',
        'State',
        'unknown',
      ]) {
        final reply = await transport.command({
          'op': op,
          'identityId': 'id-a1',
          'script': 'fetch("/")',
        });
        expect(reply.status, 400, reason: op);
        expect(reply.code, 'unsupported_operation', reason: op);
        expect(reply.json['ok'], isFalse);
      }
      expect(dispatched, 0, reason: 'no rejected command may reach dispatch');
    });

    test('requires POST /v1/command with application/json', () async {
      var dispatched = 0;
      final transport = await _Transport.start(
        dispatch: (_) async {
          dispatched++;
          return null;
        },
      );
      final body = utf8.encode('{"op":"state"}');

      for (final route in <List<String>>[
        ['GET', '/v1/command'],
        ['GET', '/'],
        ['GET', '/v1/commands'],
        ['POST', '/'],
        ['POST', '/v1/commands'],
        ['PUT', '/v1/command'],
      ]) {
        final reply = await transport.request(
          method: route[0],
          path: route[1],
          authorization: 'Bearer ${transport.token}',
          body: route[0] == 'GET' ? null : body,
        );
        expect(reply.status, 404, reason: '${route[0]} ${route[1]}');
        expect(reply.code, 'not_found');
      }

      final wrongType = await transport.command({
        'op': 'state',
      }, contentType: 'text/plain');
      expect(wrongType.status, 415);
      expect(wrongType.code, 'content_type');

      final noType = await transport.request(
        authorization: 'Bearer ${transport.token}',
        contentType: null,
        body: body,
      );
      expect(noType.status, 415);
      expect(noType.code, 'content_type');

      expect(dispatched, 0);
    });

    test('rejects malformed, oversized and mistyped command bodies', () async {
      var dispatched = 0;
      final transport = await _Transport.start(
        dispatch: (_) async {
          dispatched++;
          return null;
        },
      );

      for (final malformed in <String>[
        '{"op":',
        'not json at all',
        '{"op":"state",}',
        '',
      ]) {
        final reply = await transport.request(
          authorization: 'Bearer ${transport.token}',
          body: utf8.encode(malformed),
        );
        expect(reply.status, 400, reason: malformed);
        expect(reply.code, 'invalid_json', reason: malformed);
      }

      for (final notAnObject in <String>['[]', '"state"', '42', 'null']) {
        final reply = await transport.request(
          authorization: 'Bearer ${transport.token}',
          body: utf8.encode(notAnObject),
        );
        expect(reply.status, 400, reason: notAnObject);
        expect(reply.code, 'invalid_command', reason: notAnObject);
      }

      for (final badOp in <String>['{"op":5}', '{"op":null}', '{}']) {
        final reply = await transport.request(
          authorization: 'Bearer ${transport.token}',
          body: utf8.encode(badOp),
        );
        expect(reply.status, 400, reason: badOp);
        expect(reply.code, 'invalid_argument', reason: badOp);
      }

      final oversized = utf8.encode('{"op":"state","pad":"${'x' * 70000}"}');
      expect(oversized.length, greaterThan(65536));
      final tooLarge = await transport.request(
        authorization: 'Bearer ${transport.token}',
        body: oversized,
      );
      expect(tooLarge.status, 413);
      expect(tooLarge.code, 'request_too_large');

      expect(dispatched, 0);
    });

    test('accepts a command body of exactly 64 KiB', () async {
      final transport = await _Transport.start(dispatch: (_) async => 'ok');
      const prefix = '{"op":"state","pad":"';
      const suffix = '"}';
      final padding = 'x' * (65536 - prefix.length - suffix.length);
      final body = '$prefix$padding$suffix';
      expect(body.length, 65536);

      final reply = await transport.request(
        authorization: 'Bearer ${transport.token}',
        body: utf8.encode(body),
      );
      expect(reply.status, 200);
      expect(reply.json, {'ok': true, 'data': 'ok'});
    });

    test('abandons a body that never completes as request_timeout', () async {
      var dispatched = 0;
      final transport = await _Transport.start(
        requestTimeout: const Duration(milliseconds: 50),
        dispatch: (_) async {
          dispatched++;
          return null;
        },
      );
      final port = Uri.parse(transport.endpoint).port;

      // A raw socket is the only way to declare more Content-Length than is
      // sent; `Connection: close` makes the reply the end of the stream.
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      final chunks = <int>[];
      try {
        socket.write(
          'POST /v1/command HTTP/1.1\r\n'
          'Host: 127.0.0.1:$port\r\n'
          'Authorization: Bearer ${transport.token}\r\n'
          'Content-Type: application/json\r\n'
          'Content-Length: 4096\r\n'
          'Connection: close\r\n'
          '\r\n'
          '{"op":"state"',
        );
        await for (final chunk in socket.timeout(const Duration(seconds: 5))) {
          chunks.addAll(chunk);
        }
      } finally {
        socket.destroy();
      }

      final reply = _Reply.fromRaw(utf8.decode(chunks));
      expect(reply.status, 408);
      expect(reply.code, 'request_timeout');
      expect(reply.json['ok'], isFalse);
      expect(
        reply.text,
        isNot(contains('mayHaveExecuted')),
        reason: 'a body that never arrived executed nothing',
      );
      expect(dispatched, 0, reason: 'a partial body must not reach dispatch');
    });

    test('propagates query failures and hides unexpected errors', () async {
      final transport = await _Transport.start(
        dispatch: (command) async {
          switch (command['op']) {
            case 'identity':
              throw const AutomationFailure(
                'not_found',
                'Requested identity does not exist',
                status: 404,
              );
            case 'window':
              throw const AutomationFailure(
                'invalid_argument',
                'windowId must be an integer',
              );
            case 'workspaces':
              throw StateError('sqlite://secret/table/identities');
          }
          return null;
        },
      );

      final missing = await transport.command({
        'op': 'identity',
        'identityId': 'missing',
      });
      expect(missing.status, 404);
      expect(missing.code, 'not_found');
      expect(missing.error['message'], 'Requested identity does not exist');
      expect(missing.json['ok'], isFalse);

      final badArgument = await transport.command({
        'op': 'window',
        'windowId': 'front',
      });
      expect(badArgument.status, 400);
      expect(badArgument.code, 'invalid_argument');
      expect(badArgument.error['message'], 'windowId must be an integer');

      final crashed = await transport.command({'op': 'workspaces'});
      expect(crashed.status, 500);
      expect(crashed.code, 'command_failed');
      expect(crashed.text, isNot(contains('sqlite')));
      expect(crashed.error['message'], isNot(contains('StateError')));
    });

    test('reports a timeout while the handler keeps running', () async {
      final entered = Completer<void>();
      final gate = Completer<String>();
      final transport = await _Transport.start(
        commandTimeout: const Duration(milliseconds: 50),
        dispatch: (_) {
          if (!entered.isCompleted) entered.complete();
          return gate.future;
        },
      );
      addTearDown(() {
        if (!gate.isCompleted) gate.complete('released by teardown');
      });

      final pending = transport.command({
        'op': 'state',
        'identityId': 'id-slow',
      });
      await entered.future;

      final timedOut = await pending;
      expect(timedOut.status, 504);
      expect(timedOut.code, 'timeout');
      expect(timedOut.error['mayHaveExecuted'], isTrue);
      expect(gate.isCompleted, isFalse, reason: 'the handler is still running');

      // A timeout cannot cancel the target, so the lock is still held.
      final duringRun = await transport.command({
        'op': 'state',
        'identityId': 'id-slow',
      });
      expect(duringRun.status, 409);
      expect(duringRun.code, 'panel_busy');

      // The lock is released only once the real dispatch settles.
      gate.complete('finished after the timeout');
      await pumpEventQueue();
      final retry = await transport.command({
        'op': 'state',
        'identityId': 'id-slow',
      });
      expect(retry.status, 200);
      expect(retry.json['data'], 'finished after the timeout');
    });

    test('locks one target until its dispatch finishes', () async {
      final entered = Completer<void>();
      final gate = Completer<String>();
      var dispatches = 0;
      final transport = await _Transport.start(
        dispatch: (command) {
          dispatches++;
          if (dispatches == 1) {
            if (!entered.isCompleted) entered.complete();
            return gate.future;
          }
          return Future<String>.value('second');
        },
      );

      final first = transport.command({'op': 'state', 'identityId': 'id-a1'});
      await entered.future;

      final sameTarget = await transport.command({
        'op': 'panel',
        'identityId': 'id-a1',
      });
      expect(sameTarget.status, 409);
      expect(sameTarget.code, 'panel_busy');

      final otherTarget = await transport.command({
        'op': 'state',
        'identityId': 'id-b2',
      });
      expect(otherTarget.status, 200);

      gate.complete('first finished');
      expect((await first).json, {'ok': true, 'data': 'first finished'});

      final released = await transport.command({
        'op': 'state',
        'identityId': 'id-a1',
      });
      expect(released.status, 200);
      expect(dispatches, 3);
    });

    test('a restart locks independently of the session it replaced', () async {
      final oldEntered = Completer<void>();
      final oldGate = Completer<String>();
      final newEntered = Completer<void>();
      final newGate = Completer<String>();
      var entries = 0;
      final transport = await _Transport.start(
        dispatch: (command) {
          entries++;
          switch (entries) {
            case 1:
              if (!oldEntered.isCompleted) oldEntered.complete();
              return oldGate.future;
            case 2:
              if (!newEntered.isCompleted) newEntered.complete();
              return newGate.future;
            default:
              return Future<String>.value('extra-$entries');
          }
        },
      );
      addTearDown(() {
        if (!oldGate.isCompleted) oldGate.complete('released by teardown');
        if (!newGate.isCompleted) newGate.complete('released by teardown');
      });

      const target = {'op': 'state', 'identityId': 'id-a1'};
      final oldSession = transport.command(target);
      // close() destroys the socket, so this reply never arrives.
      unawaited(
        oldSession.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      await oldEntered.future;
      final oldToken = transport.token;

      await transport.server.close();
      expect(
        transport.directory.listSync(),
        isEmpty,
        reason: 'close removed the descriptor of the session being replaced',
      );
      await transport.server.start(transport.directory);
      await transport.refreshSession();
      expect(transport.token, isNot(oldToken));
      // The old connection belongs to the port that just went away.
      final client = transport.newClient();

      // The target the replaced session is still holding must be free here.
      final newSession = transport.command(target, client: client);
      await newEntered.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () =>
            fail('a restarted server inherited a lock from the old session'),
      );

      // The replaced session's query finishing now must not unlock this one.
      oldGate.complete('old session finished');
      await pumpEventQueue();
      final stillLocked = await transport.command(target, client: client);
      expect(stillLocked.status, 409);
      expect(stillLocked.code, 'panel_busy');

      newGate.complete('new session finished');
      expect((await newSession).json, {
        'ok': true,
        'data': 'new session finished',
      });
      final released = await transport.command(target, client: client);
      expect(released.status, 200);
      expect(released.json['data'], 'extra-3');
    });

    test('publishes a private descriptor and removes it on close', () async {
      final directory = await Directory.systemTemp.createTemp(
        'relay-desk-automation-descriptor',
      );
      final server = AutomationServer(dispatch: (_) async => null);
      addTearDown(() async {
        await server.close();
        if (await directory.exists()) await directory.delete(recursive: true);
      });

      await server.start(directory);

      final files = directory.listSync().whereType<File>().toList();
      expect(files, hasLength(1));
      final file = files.single;
      final descriptor =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;

      expect(descriptor['version'], 1);
      expect(descriptor['pid'], pid);
      expect(descriptor['token'], isA<String>());
      expect((descriptor['token'] as String).length, greaterThanOrEqualTo(32));
      expect(
        descriptor['endpoint'],
        'http://127.0.0.1:${Uri.parse(descriptor['endpoint'] as String).port}',
      );
      expect(
        file.path,
        endsWith(
          'automation-${Uri.parse(descriptor['endpoint'] as String).port}.json',
        ),
      );
      expect(await _permissionBits(file.path), '600');

      // A neighbouring file must survive: close owns exactly one descriptor.
      final foreign = File('${directory.path}/unrelated-state.json');
      await foreign.writeAsString('{"keep":"me"}');

      // A second server must not reuse the credential.
      final other = AutomationServer(dispatch: (_) async => null);
      final otherDirectory = await Directory.systemTemp.createTemp(
        'relay-desk-automation-descriptor-2',
      );
      addTearDown(() async {
        await other.close();
        if (await otherDirectory.exists()) {
          await otherDirectory.delete(recursive: true);
        }
      });
      await other.start(otherDirectory);
      final otherDescriptor =
          jsonDecode(
                await otherDirectory
                    .listSync()
                    .whereType<File>()
                    .single
                    .readAsString(),
              )
              as Map<String, dynamic>;
      expect(otherDescriptor['token'], isNot(descriptor['token']));

      await server.close();
      expect(
        await file.exists(),
        isFalse,
        reason: 'close removes its own file',
      );
      expect(directory.listSync().whereType<File>().map((f) => f.path), [
        foreign.path,
      ], reason: 'close leaves unrelated files alone');
      expect(
        otherDirectory.listSync(),
        hasLength(1),
        reason: 'other server untouched',
      );
    });
  });
}
