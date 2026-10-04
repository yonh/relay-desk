/// Normalizes a URL typed by the user (address bar, project target URL).
///
/// Bare hosts get a scheme: `example.com` -> `https://example.com`, while
/// local/private hosts (`localhost:3000`, `192.168.1.5`, `*.local`) default to
/// `http://` because dev servers rarely speak TLS. Inputs that already carry a
/// scheme are kept as-is. Returns null when the input cannot be a URL.
String? normalizeUrlInput(String input) {
  final text = input.trim();
  if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;

  if (_hasExplicitScheme(text)) {
    final uri = Uri.tryParse(text);
    return uri == null ? null : text;
  }

  final withoutSlashes = text.startsWith('//') ? text.substring(2) : text;
  final probe = Uri.tryParse('http://$withoutSlashes');
  if (probe == null || probe.host.isEmpty || !_looksLikeHost(probe.host)) {
    return null;
  }
  final scheme = _isLocalHost(probe.host) ? 'http' : 'https';
  return '$scheme://$withoutSlashes';
}

final _schemePrefix = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');
const _schemesWithoutSlashes = {'about', 'data', 'javascript', 'mailto'};

bool _hasExplicitScheme(String text) {
  if (_schemePrefix.hasMatch(text)) return true;
  final colon = text.indexOf(':');
  if (colon <= 0) return false;
  return _schemesWithoutSlashes.contains(
    text.substring(0, colon).toLowerCase(),
  );
}

final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

bool _looksLikeHost(String host) =>
    host == 'localhost' ||
    host.contains('.') ||
    host.contains(':'); // IPv6 literal

bool _isLocalHost(String host) {
  if (host == 'localhost' || host.endsWith('.localhost')) return true;
  if (host.endsWith('.local')) return true;
  if (host == '::1' || host == '[::1]') return true;
  if (!_ipv4.hasMatch(host)) return false;
  final parts = host.split('.').map(int.parse).toList();
  return parts[0] == 127 ||
      parts[0] == 10 ||
      (parts[0] == 192 && parts[1] == 168) ||
      (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) ||
      (parts[0] == 169 && parts[1] == 254);
}
