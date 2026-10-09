/// Normalizes a URL typed by the user (address bar, project target URL).
///
/// Bare hosts get a scheme: `example.com` -> `https://example.com`, while
/// local/private hosts (`localhost:3000`, `192.168.1.5`, `*.local`) default to
/// `http://` because dev servers rarely speak TLS. Inputs that already carry a
/// scheme are kept as-is. Returns null when the input cannot be a URL.
String? normalizeUrlInput(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  if (_hasExplicitScheme(text)) {
    final uri = Uri.tryParse(text);
    return uri == null ? null : text;
  }

  final withoutSlashes = text.startsWith('//') ? text.substring(2) : text;
  final authorityEnd = withoutSlashes.indexOf(RegExp(r'[/?#]'));
  final authority = authorityEnd < 0
      ? withoutSlashes
      : withoutSlashes.substring(0, authorityEnd);
  if (authority.contains(RegExp(r'\s'))) return null;
  final probe = Uri.tryParse('http://$withoutSlashes');
  if (probe == null || probe.host.isEmpty || !_looksLikeHost(probe.host)) {
    return null;
  }
  final scheme = _isLocalHost(probe.host) ? 'http' : 'https';
  return '$scheme://$withoutSlashes';
}

final _schemeColon = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):(.*)$', dotAll: true);
final _portAndRest = RegExp(r'^\d+([/?#].*)?$', dotAll: true);

/// `scheme:...` unless it is `host:port` (`localhost:3000`, `example.com:8443`).
bool _hasExplicitScheme(String text) {
  final match = _schemeColon.firstMatch(text);
  if (match == null) return false;
  final head = match.group(1)!;
  if (head.toLowerCase() == 'localhost') return false;
  return !_looksLikeHost(head) || !_portAndRest.hasMatch(match.group(2)!);
}

/// Whether [host] is a loopback/private/link-local address — the same rule
/// the address-bar normalization uses for its `http://` default, exported so
/// the automation interface can gate private-network navigation on the
/// project's `allowPrivateNetwork` flag.
bool isLocalNetworkHost(String host) => _isLocalHost(host);

final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

bool _looksLikeHost(String host) =>
    host == 'localhost' ||
    host.contains('.') ||
    host.contains(':'); // IPv6 literal

bool _isLocalHost(String host) {
  var h = host.toLowerCase();
  // `localhost.` / `127.0.0.1.` — a trailing dot is still the same host.
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);
  if (h == 'localhost' || h.endsWith('.localhost')) return true;
  if (h.endsWith('.local')) return true;
  if (h.contains(':')) return _isLocalIpv6(h);
  // inet_aton denotations: single integer, hex, octal, short dotted forms
  // (`2130706433`, `0x7f000001`, `0177.0.0.1`, `127.1`) are all IPv4 too.
  final numeric = _numericIpv4(h);
  if (numeric != null) return _isPrivateIpv4(numeric);
  if (!_ipv4.hasMatch(h)) return false;
  return _isPrivateIpv4(h.split('.').map(int.parse).toList());
}

bool _isPrivateIpv4(List<int> parts) =>
    parts[0] == 127 ||
    parts[0] == 10 ||
    (parts[0] == 192 && parts[1] == 168) ||
    (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) ||
    (parts[0] == 169 && parts[1] == 254);

/// Non-canonical IPv4 denotations per inet_aton rules: 1-4 numeric parts
/// (decimal, `0x` hex, leading-`0` octal); the last part spans the
/// remaining bytes (`127.1` == 127.0.0.1). Returns the 4 octets or null.
/// A plain 4-decimal address returns null — `_ipv4` covers it already.
List<int>? _numericIpv4(String host) {
  final parts = host.split('.');
  if (parts.length > 4) return null;
  var sawNonDecimal = false;
  final values = <int>[];
  for (final part in parts) {
    int? v;
    if (part.startsWith('0x') || part.startsWith('0X')) {
      v = int.tryParse(part.substring(2), radix: 16);
      sawNonDecimal = true;
    } else if (part.length > 1 && part.startsWith('0')) {
      v = int.tryParse(part, radix: 8);
      sawNonDecimal = true;
    } else {
      v = int.tryParse(part);
    }
    if (v == null || v < 0) return null;
    values.add(v);
  }
  if (values.length == 4 && !sawNonDecimal) return null;
  var addr = 0;
  for (var i = 0; i < values.length - 1; i++) {
    if (values[i] > 0xff) return null;
    addr |= values[i] << (8 * (3 - i));
  }
  final lastBits = 8 * (5 - values.length);
  if (values.last >= (1 << lastBits)) return null;
  addr |= values.last;
  return [
    (addr >> 24) & 0xff,
    (addr >> 16) & 0xff,
    (addr >> 8) & 0xff,
    addr & 0xff,
  ];
}

/// Loopback, unique-local (fc00::/7), link-local (fe80::/10) and
/// IPv4-mapped (::ffff:a.b.c.d) addresses.
bool _isLocalIpv6(String host) {
  final address = host.replaceAll('[', '').replaceAll(']', '').toLowerCase();
  if (address == '::1') return true;
  // IPv4-mapped IPv6 — `[::ffff:127.0.0.1]` or the hex form `[::ffff:7f00:1]`
  // — is the same private host with a different notation. Everything before
  // the `ffff:` group must be zeros and separators (`::` or `0:0:...:`).
  final fIdx = address.indexOf('ffff:');
  final isMapped = fIdx >= 0 &&
      RegExp(r'^[0:]+$').hasMatch(address.substring(0, fIdx));
  if (isMapped) {
    final tail = address.substring(fIdx + 5);
    if (tail.contains('.')) {
      final ipv4 = _numericIpv4(tail) ??
          (_ipv4.hasMatch(tail)
              ? tail.split('.').map(int.parse).toList()
              : null);
      return ipv4 != null && _isPrivateIpv4(ipv4);
    }
    final groups = tail.split(':');
    if (groups.length == 2) {
      final hi = int.tryParse(groups[0], radix: 16);
      final lo = int.tryParse(groups[1], radix: 16);
      if (hi != null && lo != null) {
        return _isPrivateIpv4([
          (hi >> 8) & 0xff,
          hi & 0xff,
          (lo >> 8) & 0xff,
          lo & 0xff,
        ]);
      }
    }
    return false;
  }
  final first = int.tryParse(address.split(':').first, radix: 16);
  if (first == null) return false;
  return (first & 0xfe00) == 0xfc00 || (first & 0xffc0) == 0xfe80;
}
