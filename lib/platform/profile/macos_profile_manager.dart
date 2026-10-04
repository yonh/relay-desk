/// Concrete ProfileManager for macOS 14+ backed by the thin native adapter.
///
/// Probes isolation availability via the native `probe` call; acquire returns a
/// handle whose profilePath is the on-disk WKWebsiteDataStore directory; clear
/// delegates to native `clearIdentityData` which removes data from that one
/// identity's store only (E-001 behaviour).
library;

import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/platform/domain.dart';
import '../../core/platform/profile_manager.dart';

const _methodChannelName = 'profiled_webview';

class MacosProfileManager implements ProfileManager {
  MacosProfileManager() : _channel = const MethodChannel(_methodChannelName);

  final MethodChannel _channel;

  @override
  Future<IsolationCapability> probe(IsolationMode mode) async {
    if (!Platform.isMacOS) {
      return IsolationCapability(
        mode: mode,
        available: false,
        persistent: false,
        reason: 'not macOS',
      );
    }
    switch (mode) {
      case IsolationMode.nativeProfile:
        try {
          final res = await _channel.invokeMapMethod<String, dynamic>('probe');
          final ok = res?['nativeProfiles'] as bool? ?? false;
          return IsolationCapability(
            mode: mode,
            available: ok,
            persistent: ok,
            reason: ok
                ? null
                : 'macOS 14+ required for WKWebsiteDataStore(forIdentifier:)',
          );
        } on PlatformException {
          return IsolationCapability(
            mode: mode,
            available: false,
            persistent: false,
            reason: 'native probe failed',
          );
        }
      case IsolationMode.originProxy:
        // Stage 3 scope; not implemented in this slice.
        return IsolationCapability(
          mode: mode,
          available: false,
          persistent: false,
          reason: 'Origin Proxy not implemented (Stage 3)',
        );
      case IsolationMode.sharedSession:
        // SharedSession is always available but explicitly NOT isolated.
        return IsolationCapability(
          mode: mode,
          available: true,
          persistent: true,
          reason: 'NOT ISOLATED — shared WKWebsiteDataStore.default()',
        );
    }
  }

  @override
  Future<ProfileHandle> acquire(String projectId, String identityId) async {
    String? path;
    try {
      path = await _channel.invokeMethod<String>('dataStorePath', {
        'identityId': identityId,
      });
    } on PlatformException {
      path = null;
    }
    return ProfileHandle(
      identityId: identityId,
      mode: IsolationMode.nativeProfile,
      profilePath: path,
    );
  }

  @override
  Future<void> clear(String projectId, String identityId) async {
    try {
      await _channel.invokeMethod('clearIdentityData', {
        'identityId': identityId,
      });
    } on PlatformException {
      // ignore
    }
  }
}
