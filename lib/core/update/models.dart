import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

/// A single downloadable file attached to a GitHub release.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    this.sha256,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    // GitHub exposes integrity as `digest: "sha256:<hex>"`.
    final digest = json['digest'] as String?;
    String? sha256;
    if (digest != null && digest.startsWith('sha256:')) {
      sha256 = digest.substring('sha256:'.length);
    }
    return ReleaseAsset(
      name: json['name'] as String? ?? '',
      downloadUrl: json['browser_download_url'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      sha256: sha256,
    );
  }

  final String name;
  final String downloadUrl;
  final int size;

  /// Expected SHA-256 hex digest published by GitHub, when available.
  final String? sha256;
}

/// A GitHub release with a parsed semantic version.
class GithubRelease {
  const GithubRelease({
    required this.tag,
    required this.version,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.prerelease,
    required this.draft,
    required this.assets,
  });

  /// Parses the `/releases/latest` payload. Returns `null` when the tag is
  /// not a `v?X.Y.Z` version or the release is a draft/prerelease — those
  /// never trigger an update prompt.
  static GithubRelease? fromJson(Map<String, dynamic> json) {
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'] as String? ?? '';
    final version = versionFromTag(tag);
    // A tag carrying a semver pre-release suffix (v1.1.0-rc.1) is still a
    // pre-release even when the GitHub flag is unset — never offer it.
    if (version == null || version.isPreRelease) return null;
    final assets = <ReleaseAsset>[
      for (final raw in (json['assets'] as List? ?? const []))
        if (raw is Map<String, dynamic>) ReleaseAsset.fromJson(raw),
    ];
    return GithubRelease(
      tag: tag,
      version: version,
      name: json['name'] as String? ?? tag,
      body: json['body'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      prerelease: false,
      draft: false,
      assets: assets,
    );
  }

  final String tag;
  final Version version;
  final String name;
  final String body;
  final String htmlUrl;
  final bool prerelease;
  final bool draft;
  final List<ReleaseAsset> assets;
}

/// Parses `v1.2.3`/`1.2.3`-style tags. Build metadata (`+4`) is stripped —
/// GitHub releases carry no build-number concept.
Version? versionFromTag(String tag) {
  var value = tag.trim();
  if (value.startsWith('v') || value.startsWith('V')) {
    value = value.substring(1);
  }
  try {
    return Version.parse(value);
  } catch (_) {
    return null;
  }
}

/// Parses the pubspec-style `1.2.3+4` build string into `1.2.3`.
Version? versionFromPackage(String packageVersion) {
  final core = packageVersion.split('+').first.trim();
  try {
    return Version.parse(core);
  } catch (_) {
    return null;
  }
}

/// True when [remote] is strictly newer than [current]. A local dev build
/// ahead of the latest release is reported as up-to-date, never as an
/// "update".
bool isRemoteNewer(Version remote, Version current) => remote > current;

/// Whether [remote] should stay silent because the user skipped it. Skipping
/// covers the skipped version and anything older — a newer release always
/// prompts again.
bool isSkipped(Version remote, Version? skipped) =>
    skipped != null && remote <= skipped;

/// Picks the best update asset for [platform] (`macos`/`windows`/`linux`).
/// Prefers archive formats that script cleanly (zip/tar.gz); returns `null`
/// when no installable asset exists.
ReleaseAsset? selectAsset(List<ReleaseAsset> assets, String platform) {
  bool matches(ReleaseAsset a, String token, String ext) =>
      a.name.toLowerCase().contains(token) &&
      a.name.toLowerCase().endsWith(ext);
  switch (platform) {
    case 'macos':
      for (final a in assets) {
        if (matches(a, 'macos', '.zip')) return a;
      }
      return null;
    case 'windows':
      for (final a in assets) {
        if (matches(a, 'windows', '.zip')) return a;
      }
      return null;
    case 'linux':
      for (final a in assets) {
        if (matches(a, 'linux', '.tar.gz')) return a;
        if (matches(a, 'linux', '.zip')) return a;
      }
      return null;
    default:
      return null;
  }
}

/// Current platform token used for asset matching; testable via
/// [selectAsset]. Returns empty string on unsupported platforms.
String hostPlatformToken() {
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  return '';
}

/// Pipeline stage, surfaced in error states so the UI can offer a sensible
/// retry ("check again" vs "download again").
enum UpdateStage { check, download, verify, install }

/// High-level update lifecycle.
enum UpdatePhase {
  /// Nothing happening; no check performed yet this session.
  idle,

  /// A release request is in flight.
  checking,

  /// Checked and the running build is current (or remote was skipped).
  upToDate,

  /// A newer release exists; awaiting the user (or auto-download).
  available,

  /// Downloading the update package. [UpdateStatus.progress] is 0..1.
  downloading,

  /// Download finished; SHA-256 verification and extraction in progress.
  verifying,

  /// Package downloaded, verified and staged — ready to install+relaunch.
  ready,

  /// The installer hand-off is running; the app quits on success.
  installing,

  /// Something failed. [UpdateStatus.stage] says where.
  failed,
}

/// Immutable update state emitted by `UpdateController`.
class UpdateStatus {
  const UpdateStatus({
    this.phase = UpdatePhase.idle,
    this.release,
    this.asset,
    this.progress = 0,
    this.stage,
    this.error,
    this.latestVersion,
    this.currentVersion,
  });

  final UpdatePhase phase;

  /// The candidate release, set while the phase concerns one.
  final GithubRelease? release;

  /// The asset selected for this platform from [release].
  final ReleaseAsset? asset;

  /// Download progress 0..1 while [phase] is [UpdatePhase.downloading].
  final double progress;

  /// Failing stage when [phase] is [UpdatePhase.failed].
  final UpdateStage? stage;

  /// Short diagnostic for the failure (not localized; shown verbatim).
  final String? error;

  /// Latest version seen during the last successful check — kept even in
  /// [UpdatePhase.upToDate] so the settings row can show it.
  final Version? latestVersion;

  /// The running build's version — populated after each check so the UI can
  /// show "current → new" context.
  final Version? currentVersion;

  bool get busy =>
      phase == UpdatePhase.checking ||
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.verifying ||
      phase == UpdatePhase.installing;

  UpdateStatus copyWith({
    UpdatePhase? phase,
    GithubRelease? release,
    ReleaseAsset? asset,
    double? progress,
    UpdateStage? stage,
    String? error,
    Version? latestVersion,
    Version? currentVersion,
    bool clearRelease = false,
    bool clearError = false,
  }) {
    return UpdateStatus(
      phase: phase ?? this.phase,
      release: clearRelease ? null : (release ?? this.release),
      asset: clearRelease ? null : (asset ?? this.asset),
      progress: progress ?? this.progress,
      stage: clearError ? null : (stage ?? this.stage),
      error: clearError ? null : (error ?? this.error),
      latestVersion: latestVersion ?? this.latestVersion,
      currentVersion: currentVersion ?? this.currentVersion,
    );
  }
}
