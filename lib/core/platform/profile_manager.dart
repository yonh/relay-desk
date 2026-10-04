/// Profile manager contract per rewrite-plan §4.6.
library;

import 'domain.dart';

/// Result of probing an isolation mode's availability.
class IsolationCapability {
  final IsolationMode mode;
  final bool available;
  final bool persistent;
  final String? reason;

  const IsolationCapability({
    required this.mode,
    required this.available,
    required this.persistent,
    this.reason,
  });

  bool get isIsolated => mode.isIsolated && available;
}

/// Handle to an acquired profile/data store.
class ProfileHandle {
  final String identityId;
  final IsolationMode mode;
  final String? profilePath;

  const ProfileHandle({
    required this.identityId,
    required this.mode,
    this.profilePath,
  });
}

/// Manages per-identity browser profiles / data stores.
abstract interface class ProfileManager {
  Future<IsolationCapability> probe(IsolationMode mode);
  Future<ProfileHandle> acquire(String projectId, String identityId);
  Future<void> clear(String projectId, String identityId);
}
