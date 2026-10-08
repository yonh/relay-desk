#!/usr/bin/env python3
"""CLI for Relay Desk's opt-in, authenticated local automation transport.

P0 speaks metadata reads only. Absence of a selector means "the backend's
current selection": the CLI never guesses a project, identity, window or
workspace on the caller's behalf, and never inspects AppKit itself.
"""

import argparse
import glob
import json
import os
from pathlib import Path
import sys
import urllib.error
import urllib.parse
import urllib.request


# op -> ((flag, request field, type, help), ...)
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
}

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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--session', help='Session file; otherwise RELAY_DESK_SESSION or discovery')
    sub = parser.add_subparsers(dest='op', required=True)
    for op, selectors in COMMANDS.items():
        p = sub.add_parser(op, help=SELECTOR_HELP[op])
        for flag, _, kind, help in selectors:
            p.add_argument(flag, type=kind, help=help)
    return parser


def build_command(args):
    command = {'op': args.op}
    for flag, field, _, _ in COMMANDS[args.op]:
        value = getattr(args, flag.lstrip('-').replace('-', '_'))
        if value is not None:
            command[field] = value
    return command


def main():
    args = build_parser().parse_args()
    if args.op == 'sessions':
        print(json.dumps({'sessions': sessions()}, ensure_ascii=False, indent=2))
        return 0
    result = send(load_session(args.session), build_command(args))
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result.get('ok') else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print(json.dumps({'ok': False, 'error': {'code': 'client_error', 'message': str(error)}}, ensure_ascii=False), file=sys.stderr)
        sys.exit(1)