#!/usr/bin/env python3
"""CLI for Relay Desk's opt-in, authenticated local automation transport.

P0 speaks metadata reads plus the read-only `screenshot` and `media`
operations. Absence of a selector means "the backend's current selection":
the CLI never guesses a project, identity, window or workspace on the
caller's behalf, and never inspects AppKit itself. `screenshot` and `media`
are exceptions to the absent-selector rule: each requires an explicit
--identity (plus a local --output path for screenshot), because page-level
reads without a named target would silently sample whatever happens to be
selected.
"""

import argparse
import base64
import glob
import json
import os
from pathlib import Path
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request


# op -> ((flag, request field, type, help), ...)
# A `None` request field marks a CLI-local option: parsed and validated here
# but never forwarded into the command JSON, so the server never receives a
# local filesystem path to write to.
COMMANDS = {
    'sessions': (),
    'capabilities': (),
    'state': (),
    'projects': (),
    'project': (('--project', 'projectId', None, 'Exact projectId; omit for the current project'),),
    'identities': (('--project', 'projectId', None, 'Exact projectId; omit for the current project'),),
    'identity': (('--identity', 'identityId', None, 'Exact identityId; omit for the selected identity'),),
    'panels': (('--project', 'projectId', None, 'Exact projectId; omit for all resident panels'),),
    'panel': (('--identity', 'identityId', None, 'Exact identityId; omit for the selected panel'),),
    'windows': (),
    'window': (('--window', 'windowId', int, 'Exact native windowId; omit for the key window'),),
    'workspaces': (('--project', 'projectId', None, 'Exact projectId; omit for the current project'),),
    'workspace': (('--workspace', 'workspaceId', None, 'Exact workspaceId; omit for the current workspace'),),
    'screenshot': (
        ('--identity', 'identityId', None, 'Exact identityId; required, no selection fallback'),
        ('--output', None, None, 'Local file path for the PNG; required, never sent to the app'),
    ),
    'media': (
        ('--identity', 'identityId', None, 'Exact identityId; required, no selection fallback'),
    ),
    'errors': (
        ('--identity', 'identityId', None, 'Exact identityId; required, no selection fallback'),
    ),
    'activate_project': (
        ('--project', 'projectId', None, 'Exact projectId; required, no name matching'),
    ),
    'open_panel': (
        ('--identity', 'identityId', None, 'Exact identityId; required, no selection fallback'),
    ),
}

# The PNG magic bytes every PNG file starts with. A payload that fails this
# check is not an image and is never written to --output.
PNG_MAGIC = b'\x89PNG\r\n\x1a\n'

SELECTOR_HELP = {
    'sessions': 'List local session descriptors; never contacts a server',
    'capabilities': 'Protocol version, supported operations and limitations',
    'state': 'Current selection plus native focus, captured in one response',
    'projects': 'Every project in the database',
    'project': 'One project, or the current project',
    'identities': 'Identities of one project, or of the current project',
    'identity': 'One identity, or the currently selected identity',
    'panels': 'Resident panels, optionally filtered to one project',
    'panel': 'One panel, or the currently selected panel',
    'windows': 'Every application NSWindow and native web view',
    'window': 'One window, or the key window; no main-window fallback',
    'workspaces': 'Saved layouts of one project, or of the current project',
    'workspace': 'One saved layout, or the current named layout',
    'screenshot': 'Viewport PNG of one identity panel; --identity and --output required',
    'media': 'Media-element state of one identity panel; --identity required',
    'errors': 'Buffered page JS errors of one identity panel; --identity required',
    'activate_project': 'Switch the app to an existing project; --project required',
    'open_panel': 'Open the panel of an existing identity; --identity required',
}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise RuntimeError('Automation endpoint redirected; request refused')


def sessions():
    roots = [
        '~/Library/Containers/com.example.relayDesk/Data/Library/Application Support/*/automation/automation-*.json',
        '~/Library/Application Support/*/automation/automation-*.json',
    ]
    found = []
    for pattern in roots:
        for name in glob.glob(os.path.expanduser(pattern)):
            try:
                data = json.loads(Path(name).read_text())
                os.kill(int(data['pid']), 0)
                found.append({'file': name, 'pid': data['pid'], 'endpoint': data['endpoint']})
            except (OSError, ValueError, KeyError):
                continue
    return sorted(found, key=lambda s: s['file'])


def load_session(name):
    name = name or os.environ.get('RELAY_DESK_SESSION')
    if not name:
        available = sessions()
        if len(available) != 1:
            raise RuntimeError('Expected one running automation session; use sessions then --session FILE')
        name = available[0]['file']
    file = Path(name).expanduser()
    if os.name != 'nt' and (file.stat().st_mode & 0o077):
        raise RuntimeError('Session file is not private; expected permissions 600')
    data = json.loads(file.read_text())
    endpoint = urllib.parse.urlsplit(data['endpoint'])
    if (endpoint.scheme != 'http' or endpoint.hostname != '127.0.0.1'
            or not endpoint.port or endpoint.path or endpoint.query or endpoint.fragment
            or endpoint.username or endpoint.password):
        raise RuntimeError('Session endpoint must be a loopback IPv4 HTTP server')
    return data


def send(session, command):
    encoded = json.dumps(command).encode()
    if len(encoded) > 65536:
        raise RuntimeError('Command limit is 64 KiB')
    request = urllib.request.Request(
        session['endpoint'] + '/v1/command', data=encoded,
        headers={'Authorization': 'Bearer ' + session['token'], 'Content-Type': 'application/json'},
    )
    # Bypass machine HTTP proxies for this local transport and never forward
    # its authentication header through a redirect.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        with opener.open(request, timeout=13) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        return json.load(error)


def build_parser():
    # allow_abbrev=False: a removed or mistyped flag (e.g. `--out`) must exit
    # 2 instead of prefix-matching a live option like `--output`.
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument('--session', help='Session file; otherwise RELAY_DESK_SESSION or discovery')
    sub = parser.add_subparsers(dest='op', required=True)
    for op, selectors in COMMANDS.items():
        p = sub.add_parser(op, help=SELECTOR_HELP[op], allow_abbrev=False)
        for flag, _, kind, help in selectors:
            # screenshot's two flags are required, as is media's --identity;
            # every other selector stays optional and defers to the
            # backend's current selection.
            p.add_argument(flag, type=kind, help=help,
                          required=op == 'screenshot' or (op in ('media', 'errors', 'open_panel') and flag == '--identity') or (op == 'activate_project' and flag == '--project'))
    return parser


def build_command(args):
    command = {'op': args.op}
    for flag, field, _, _ in COMMANDS[args.op]:
        if field is None:
            continue
        value = getattr(args, flag.lstrip('-').replace('-', '_'))
        if value is not None:
            command[field] = value
    return command


def write_screenshot(result, output):
    """Decode the base64 payload, prove it is a PNG, then write --output.

    The decoded bytes are validated before any file is touched, so a
    malformed or oversized reply never leaves a corrupt file behind; on a
    filesystem failure the partial file is removed.
    """
    data = result.get('data')
    encoded = data.get('pngBase64') if isinstance(data, dict) else None
    if not isinstance(encoded, str) or not encoded:
        raise RuntimeError('Unexpected response from automation endpoint')
    try:
        png = base64.b64decode(encoded, validate=True)
    except ValueError:
        raise RuntimeError('Unexpected response from automation endpoint')
    if not png.startswith(PNG_MAGIC):
        raise RuntimeError('The automation endpoint returned a non-PNG screenshot')
    path = Path(output).expanduser()
    # Write to a unique sibling temp file first, then atomically rename onto
    # the target: a failed write can never truncate or delete an existing
    # capture — cleanup only ever touches the temp file this run created.
    fd, tmp_name = tempfile.mkstemp(
        prefix=path.name + '.relayctl-', suffix='.tmp', dir=path.parent
    )
    try:
        with os.fdopen(fd, 'wb') as handle:
            handle.write(png)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_name, path)
    except OSError:
        Path(tmp_name).unlink(missing_ok=True)
        raise
    reported = dict(data)
    reported.pop('pngBase64', None)
    reported['outputPath'] = str(path.resolve())
    reported['byteLength'] = len(png)
    print(json.dumps({'ok': True, 'data': reported}, ensure_ascii=False, indent=2))


def main():
    args = build_parser().parse_args()
    if args.op == 'sessions':
        print(json.dumps({'sessions': sessions()}, ensure_ascii=False, indent=2))
        return 0
    result = send(load_session(args.session), build_command(args))
    if args.op == 'screenshot' and result.get('ok'):
        write_screenshot(result, args.output)
        return 0
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result.get('ok') else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print(json.dumps({'ok': False, 'error': {'code': 'client_error', 'message': str(error)}}, ensure_ascii=False), file=sys.stderr)
        sys.exit(1)