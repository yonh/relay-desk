"""Offline protocol tests for the reference CLI or standalone relayctl.

Set RELAYCTL_BIN to the compiled executable to exercise the distributed CLI.

Every request goes to a throwaway loopback server; no test touches the live
Relay Desk app, a real session file on this machine, or any external site.
"""

import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


RELAYCTL = Path(__file__).resolve().parents[2] / 'tool' / 'relayctl.py'
TOKEN = 'offline-test-token-2f8c1d'
SELECTOR_CASES = (
    ('project', '--project', 'proj-7', 'projectId', 'proj-7'),
    ('identities', '--project', 'proj-7', 'projectId', 'proj-7'),
    ('identity', '--identity', 'ident-3', 'identityId', 'ident-3'),
    ('panels', '--project', 'proj-7', 'projectId', 'proj-7'),
    ('panel', '--identity', 'ident-3', 'identityId', 'ident-3'),
    ('window', '--window', '42', 'windowId', 42),
    ('workspaces', '--project', 'proj-7', 'projectId', 'proj-7'),
    ('workspace', '--workspace', 'ws-9', 'workspaceId', 'ws-9'),
    ('media', '--identity', 'ident-3', 'identityId', 'ident-3'),
)
SELECTION_CASES = ('capabilities', 'state', 'projects', 'identities', 'identity',
                   'panels', 'panel', 'windows', 'window', 'workspaces', 'workspace')
REMOVED_CASES = (
    ('eval', ['--identity', 'ident-3', '--file', 'x.js']),
    ('navigate', ['--identity', 'ident-3', '--url', 'https://example.com']),
    ('reload', ['--identity', 'ident-3']),
    ('snapshot', ['--identity', 'ident-3']),
)

# A complete 1x1 transparent PNG (67 bytes), the smallest real capture.
TINY_PNG = bytes.fromhex(
    '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489'
    '0000000d4944415478da63fcffff3f030005fe02fea72d99400000000049454e44ae426082'
)


class _Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    def do_POST(self):
        fake = self.server.fake
        if self.headers.get('Transfer-Encoding', '').lower() == 'chunked':
            chunks = []
            while True:
                size = int(self.rfile.readline().split(b';', 1)[0].strip(), 16)
                if size == 0:
                    while self.rfile.readline() not in (b'\r\n', b'\n', b''):
                        pass
                    break
                chunks.append(self.rfile.read(size))
                if self.rfile.read(2) != b'\r\n':
                    raise ValueError('Malformed chunk terminator')
            body = b''.join(chunks)
        else:
            body = self.rfile.read(int(self.headers.get('Content-Length') or 0))
        fake.record({
            'method': 'POST',
            'path': self.path,
            'headers': {key.lower(): value for key, value in self.headers.items()},
            'body': body,
        })
        self.respond(fake.status, fake.headers, fake.payload)

    def do_GET(self):
        fake = self.server.fake
        fake.record({'method': 'GET', 'path': self.path,
                     'headers': {key.lower(): value for key, value in self.headers.items()},
                     'body': b''})
        self.respond(fake.status, fake.headers, fake.payload)

    def respond(self, status, headers, payload):
        self.send_response(status)
        for key, value in headers.items():
            self.send_header(key, value)
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


class _FakeServer:
    """A loopback stand-in for the app's automation transport."""

    def __init__(self):
        self.requests = []
        self.status = 200
        self.headers = {'Content-Type': 'application/json'}
        self.payload = json.dumps({'ok': True, 'data': {'projects': []}}).encode()
        self._lock = threading.Lock()
        self._server = ThreadingHTTPServer(('127.0.0.1', 0), _Handler)
        self._server.daemon_threads = True
        self._server.fake = self
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()

    @property
    def endpoint(self):
        host, port = self._server.server_address[:2]
        return 'http://%s:%d' % (host, port)

    def record(self, request):
        with self._lock:
            self.requests.append(request)

    def seen(self):
        with self._lock:
            return list(self.requests)

    def respond(self, payload, status=200, headers=None):
        self.status = status
        self.headers = headers or {'Content-Type': 'application/json'}
        self.payload = payload if isinstance(payload, bytes) else json.dumps(payload).encode()

    def close(self):
        self._server.shutdown()
        self._server.server_close()
        self._thread.join(timeout=5)


class RelayCtlTest(unittest.TestCase):
    def setUp(self):
        self.server = _FakeServer()
        self.addCleanup(self.server.close)
        self.home = tempfile.TemporaryDirectory()
        self.addCleanup(self.home.cleanup)
        self.descriptor = self.write_descriptor(self.server.endpoint, mode=0o600)

    def write_descriptor(self, endpoint, mode=0o600, token=TOKEN, raw=None):
        path = Path(self.home.name) / 'automation-test.json'
        if raw is None:
            raw = json.dumps({'version': 1, 'endpoint': endpoint, 'token': token, 'pid': os.getpid()})
        path.write_text(raw)
        os.chmod(path, mode)
        return path

    def run_cli(self, *args, descriptor=None, env=None):
        environment = {key: value for key, value in os.environ.items()
                       if not key.lower().endswith('_proxy') and key != 'RELAY_DESK_SESSION'}
        # An empty HOME keeps local session discovery from touching real descriptors.
        environment['HOME'] = self.home.name
        environment.update(env or {})
        binary = os.environ.get('RELAYCTL_BIN')
        command = [binary] if binary else [sys.executable, str(RELAYCTL)]
        if descriptor is not False:
            command += ['--session', str(descriptor or self.descriptor)]
        return subprocess.run(command + list(args), capture_output=True, text=True,
                              env=environment, timeout=60)

    def assertNoCredentialLeak(self, done):
        combined = done.stdout + done.stderr
        self.assertNotIn(TOKEN, combined)
        self.assertNotIn('Bearer', combined)

    # --- request shape -------------------------------------------------

    def test_selectors_are_forwarded_in_the_json_command(self):
        for op, flag, raw, field, expected in SELECTOR_CASES:
            with self.subTest(op=op):
                self.server.requests.clear()
                self.server.respond({'ok': True, 'data': {'echo': field}})
                done = self.run_cli(op, flag, raw)
                self.assertEqual(done.returncode, 0, done.stderr)
                self.assertEqual(len(self.server.seen()), 1)
                request = self.server.seen()[0]
                self.assertEqual(request['method'], 'POST')
                self.assertEqual(request['path'], '/v1/command')
                self.assertEqual(request['headers']['content-type'].split(';', 1)[0],
                                 'application/json')
                self.assertEqual(request['headers']['authorization'], 'Bearer ' + TOKEN)
                self.assertEqual(json.loads(request['body']),
                                 {'op': op, field: expected})
                self.assertEqual(json.loads(done.stdout), {'ok': True, 'data': {'echo': field}})
                self.assertNoCredentialLeak(done)

    def test_omitted_selectors_defer_to_the_backends_selection(self):
        for op in SELECTION_CASES:
            with self.subTest(op=op):
                self.server.requests.clear()
                done = self.run_cli(op)
                self.assertEqual(done.returncode, 0, done.stderr)
                request = self.server.seen()[0]
                self.assertEqual(json.loads(request['body']), {'op': op})
                self.assertNoCredentialLeak(done)

    def test_non_integer_window_id_is_refused_before_any_request(self):
        done = self.run_cli('window', '--window', 'key')
        self.assertEqual(done.returncode, 2)
        self.assertEqual(self.server.seen(), [])
        self.assertNoCredentialLeak(done)

    # --- response handling ---------------------------------------------

    def test_denied_response_exits_one_and_passes_the_error_through(self):
        self.server.respond(
            {'ok': False, 'error': {'code': 'not_found', 'message': 'Requested identity does not exist'}},
            status=404)
        done = self.run_cli('identity', '--identity', 'missing')
        self.assertEqual(done.returncode, 1)
        self.assertEqual(json.loads(done.stdout),
                         {'ok': False, 'error': {'code': 'not_found',
                                                 'message': 'Requested identity does not exist'}})
        self.assertNoCredentialLeak(done)

    def test_state_response_is_not_interpreted_by_the_cli(self):
        payload = {
            'ok': True,
            'data': {'capturedAt': '2026-10-08T00:00:00Z', 'project': None, 'identity': None,
                     'panel': None, 'window': None, 'workspaceId': None,
                     'layoutMode': 'grid', 'selectedIdentityId': None, 'focusedIdentityId': None,
                     'selectionConsistent': False},
        }
        self.server.respond(payload)
        done = self.run_cli('state')
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(json.loads(done.stdout), payload)

    def test_window_without_a_key_window_is_not_backfilled(self):
        self.server.respond({'ok': True, 'data': {'currentWindowId': None, 'mainWindowId': 1,
                                                  'windows': [], 'views': []}})
        done = self.run_cli('window')
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIsNone(json.loads(done.stdout)['data']['currentWindowId'])

    # --- screenshot -----------------------------------------------------

    def _screenshot_payload(self, png):
        import base64
        return {'ok': True, 'data': {
            'identityId': 'ident-3', 'projectId': 'proj-7',
            'nativeViewId': 9, 'windowId': 83,
            'capturedAt': '2026-10-08T00:00:00Z', 'format': 'png',
            'width': 1, 'height': 1, 'url': 'https://a.example.com/',
            'pngBase64': base64.b64encode(png).decode(),
        }}

    def test_screenshot_writes_the_validated_png_and_reports_metadata(self):
        output = Path(self.home.name) / 'shot.png'
        self.server.respond(self._screenshot_payload(TINY_PNG))
        done = self.run_cli('screenshot', '--identity', 'ident-3',
                            '--output', str(output))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(output.read_bytes(), TINY_PNG)
        reply = json.loads(done.stdout)
        self.assertTrue(reply['ok'])
        self.assertEqual(reply['data']['byteLength'], len(TINY_PNG))
        self.assertEqual(reply['data']['outputPath'], str(output.resolve()))
        self.assertNotIn('pngBase64', reply['data'])
        request = self.server.seen()[0]
        # --output is CLI-local: the wire carries only the explicit identity.
        self.assertEqual(json.loads(request['body']),
                         {'op': 'screenshot', 'identityId': 'ident-3'})
        self.assertNoCredentialLeak(done)

    def test_media_requires_an_explicit_identity(self):
        done = self.run_cli('media')
        self.assertEqual(done.returncode, 2)
        self.assertEqual(self.server.seen(), [])
        self.assertNoCredentialLeak(done)

    def test_screenshot_requires_an_explicit_identity(self):
        done = self.run_cli('screenshot', '--output',
                            str(Path(self.home.name) / 'x.png'))
        self.assertEqual(done.returncode, 2)
        self.assertEqual(self.server.seen(), [])
        self.assertNoCredentialLeak(done)

    def test_screenshot_requires_an_output_path(self):
        done = self.run_cli('screenshot', '--identity', 'ident-3')
        self.assertEqual(done.returncode, 2)
        self.assertEqual(self.server.seen(), [])
        self.assertNoCredentialLeak(done)

    def test_screenshot_refuses_a_non_png_payload_without_writing(self):
        output = Path(self.home.name) / 'shot.png'
        self.server.respond(self._screenshot_payload(b'not-a-png-at-all'))
        done = self.run_cli('screenshot', '--identity', 'ident-3',
                            '--output', str(output))
        self.assertEqual(done.returncode, 1)
        self.assertFalse(output.exists())
        self.assertNoCredentialLeak(done)

    def test_screenshot_error_envelope_passes_through(self):
        self.server.respond(
            {'ok': False, 'error': {'code': 'target_changed',
                                    'message': 'Target changed during capture'}},
            status=409)
        output = Path(self.home.name) / 'shot.png'
        done = self.run_cli('screenshot', '--identity', 'ident-3',
                            '--output', str(output))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(json.loads(done.stdout)['error']['code'], 'target_changed')
        self.assertFalse(output.exists())
        self.assertNoCredentialLeak(done)

    def test_screenshot_refuses_the_removed_out_flag(self):
        # `--out` was the pre-release flag name; an unknown option must not
        # silently select a different spelling or fire a request.
        done = self.run_cli('screenshot', '--identity', 'ident-3',
                            '--out', str(Path(self.home.name) / 'x.png'))
        self.assertEqual(done.returncode, 2)
        self.assertEqual(self.server.seen(), [])
        self.assertNoCredentialLeak(done)

    def _tmp_litter(self, output):
        # Temp files from the atomic-write path must never survive the run.
        return list(Path(output).parent.glob(output.name + '.relayctl-*'))

    def test_screenshot_replaces_an_existing_output_file(self):
        output = Path(self.home.name) / 'shot.png'
        output.write_bytes(b'SENTINEL-OLD-CAPTURE')
        self.server.respond(self._screenshot_payload(TINY_PNG))
        done = self.run_cli('screenshot', '--identity', 'ident-3',
                            '--output', str(output))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(output.read_bytes(), TINY_PNG)
        self.assertEqual(self._tmp_litter(output), [])
        self.assertNoCredentialLeak(done)

    def test_screenshot_rejected_payload_preserves_an_existing_output(self):
        output = Path(self.home.name) / 'shot.png'
        output.write_bytes(b'SENTINEL-OLD-CAPTURE')
        self.server.respond(self._screenshot_payload(b'not-a-png-at-all'))
        done = self.run_cli('screenshot', '--identity', 'ident-3',
                            '--output', str(output))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(output.read_bytes(), b'SENTINEL-OLD-CAPTURE')
        self.assertEqual(self._tmp_litter(output), [])
        self.assertNoCredentialLeak(done)

    def test_screenshot_write_failure_preserves_an_existing_output(self):
        # A write-phase failure (rename onto an existing directory) must
        # leave the pre-existing target untouched — the direct-write path
        # used to truncate it, then delete it in cleanup.
        output = Path(self.home.name) / 'shot.png'
        output.mkdir()
        self.server.respond(self._screenshot_payload(TINY_PNG))
        done = self.run_cli('screenshot', '--identity', 'ident-3',
                            '--output', str(output))
        self.assertEqual(done.returncode, 1)
        self.assertTrue(output.is_dir())
        self.assertEqual(self._tmp_litter(output), [])
        self.assertNoCredentialLeak(done)

    # --- unsupported actions -------------------------------------------

    def test_removed_actions_are_rejected_without_a_request(self):
        for op, extra in REMOVED_CASES:
            with self.subTest(op=op):
                self.server.requests.clear()
                done = self.run_cli(op, *extra)
                self.assertEqual(done.returncode, 2)
                self.assertEqual(self.server.seen(), [])
                self.assertNoCredentialLeak(done)

    # --- descriptor trust ----------------------------------------------

    def test_malformed_descriptor_transmits_nothing(self):
        descriptor = self.write_descriptor(None, raw='{"endpoint": "http://127.0.0.1:1"')
        done = self.run_cli('capabilities', descriptor=descriptor)
        self.assertEqual(done.returncode, 1)
        self.assertEqual(json.loads(done.stderr)['error']['code'], 'client_error')
        self.assertEqual(self.server.seen(), [])
        self.assertNoCredentialLeak(done)

    def test_non_loopback_descriptor_transmits_nothing(self):
        descriptor = self.write_descriptor('http://192.0.2.10:8080')
        done = self.run_cli('capabilities', descriptor=descriptor)
        self.assertEqual(done.returncode, 1)
        self.assertIn('loopback', json.loads(done.stderr)['error']['message'])
        self.assertEqual(self.server.seen(), [])
        self.assertNoCredentialLeak(done)

    def test_descriptor_with_credentials_in_the_url_is_refused(self):
        descriptor = self.write_descriptor('http://user:secret@127.0.0.1:8080')
        done = self.run_cli('capabilities', descriptor=descriptor)
        self.assertEqual(done.returncode, 1)
        self.assertIn('loopback', json.loads(done.stderr)['error']['message'])
        self.assertEqual(self.server.seen(), [])

    def test_world_readable_descriptor_is_refused(self):
        descriptor = self.write_descriptor(self.server.endpoint, mode=0o644)
        done = self.run_cli('capabilities', descriptor=descriptor)
        self.assertEqual(done.returncode, 1)
        self.assertIn('private', json.loads(done.stderr)['error']['message'])
        self.assertEqual(self.server.seen(), [])
        self.assertNoCredentialLeak(done)

    def test_missing_descriptor_is_reported_without_a_request(self):
        done = self.run_cli('capabilities', descriptor=Path(self.home.name) / 'absent.json')
        self.assertEqual(done.returncode, 1)
        self.assertEqual(self.server.seen(), [])

    def test_redirect_does_not_forward_credentials(self):
        trap = _FakeServer()
        self.addCleanup(trap.close)
        self.server.respond(b'', status=307, headers={'Location': trap.endpoint + '/v1/command'})
        done = self.run_cli('capabilities')
        self.assertEqual(done.returncode, 1)
        self.assertIn('redirected', json.loads(done.stderr)['error']['message'])
        self.assertEqual(len(self.server.seen()), 1)
        self.assertEqual(trap.seen(), [])
        self.assertNoCredentialLeak(done)

    # --- session selection ---------------------------------------------

    def test_session_environment_variable_is_a_fallback(self):
        done = self.run_cli('capabilities', descriptor=False,
                            env={'RELAY_DESK_SESSION': str(self.descriptor)})
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(len(self.server.seen()), 1)

    def test_sessions_lists_local_descriptors_without_contacting_a_server(self):
        done = self.run_cli('sessions', descriptor=False)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(json.loads(done.stdout), {'sessions': []})
        self.assertEqual(self.server.seen(), [])
        self.assertNoCredentialLeak(done)

    def test_help_remains_available(self):
        done = self.run_cli('--help', descriptor=False)
        self.assertEqual(done.returncode, 0)
        for op in ('sessions', 'capabilities', 'state', 'projects', 'project', 'identities',
                   'identity', 'panels', 'panel', 'windows', 'window', 'workspaces', 'workspace',
                   'screenshot'):
            self.assertIn(op, done.stdout)


if __name__ == '__main__':
    unittest.main()
