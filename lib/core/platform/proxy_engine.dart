/// Proxy engine contract per rewrite-plan §4.6 and §4.9.
/// Not implemented in Gate 0 / Stage 1; reserved for Stage 3.
library;

import 'domain.dart';

class ProxySession {
  final String identityId;
  final int port;
  final String secret;

  const ProxySession({
    required this.identityId,
    required this.port,
    required this.secret,
  });
}

class ProxyDiagnostic {
  final String identityId;
  final String level;
  final String message;
  final DateTime timestamp;

  const ProxyDiagnostic({
    required this.identityId,
    required this.level,
    required this.message,
    required this.timestamp,
  });
}

/// Origin Proxy engine. Stage 3 scope — not implemented in Gate 0 / Stage 1.
abstract interface class ProxyEngine {
  Future<ProxySession> start(Project project, Identity identity);
  Future<void> stop(String identityId);
  Stream<ProxyDiagnostic> get diagnostics;
}
