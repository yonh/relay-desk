/// Domain models matching the Tauri schema (field-level compatible).
/// See docs/rewrite-plan-comparison.md §4.7 Data Contract.
library;

/// Isolation mode for an identity.
/// - nativeProfile: per-identity persistent browser profile/data store.
/// - originProxy: origin-scoped isolation via local proxy (cross-platform fallback).
/// - sharedSession: NO isolation; explicitly marked "not isolated".
enum IsolationMode {
  nativeProfile,
  originProxy,
  sharedSession;

  String get dbValue => switch (this) {
    nativeProfile => 'nativeProfile',
    originProxy => 'originProxy',
    sharedSession => 'sharedSession',
  };

  static IsolationMode fromDb(String value) => switch (value) {
    'nativeProfile' => nativeProfile,
    'originProxy' => originProxy,
    'sharedSession' => sharedSession,
    _ => throw ArgumentError('invalid isolation mode: $value'),
  };

  String get displayName => switch (this) {
    nativeProfile => 'Native Profile',
    originProxy => 'Origin Proxy',
    sharedSession => 'Shared Session (not isolated)',
  };

  bool get isIsolated => this != sharedSession;
}

enum LayoutMode { canvas, grid, columns, focus }

extension LayoutModeDb on LayoutMode {
  String get dbValue => switch (this) {
    LayoutMode.canvas => 'canvas',
    LayoutMode.grid => 'grid',
    LayoutMode.columns => 'columns',
    LayoutMode.focus => 'focus',
  };

  static LayoutMode fromDb(String value) => switch (value) {
    'canvas' => LayoutMode.canvas,
    'grid' => LayoutMode.grid,
    'columns' => LayoutMode.columns,
    'focus' => LayoutMode.focus,
    _ => LayoutMode.grid,
  };
}

class Project {
  final String id;
  final String name;
  final String targetUrl;
  final bool allowPrivateNetwork;
  final int createdAt;
  final int updatedAt;

  /// Per-project default layout mode. New projects inherit the global
  /// default `grid`; the user's last choice is persisted so switching away
  /// and back (or restarting) restores it.
  final LayoutMode defaultLayoutMode;

  const Project({
    required this.id,
    required this.name,
    required this.targetUrl,
    this.allowPrivateNetwork = false,
    required this.createdAt,
    required this.updatedAt,
    this.defaultLayoutMode = LayoutMode.grid,
  });

  Project copyWith({
    String? name,
    String? targetUrl,
    bool? allowPrivateNetwork,
    int? updatedAt,
    LayoutMode? defaultLayoutMode,
  }) => Project(
    id: id,
    name: name ?? this.name,
    targetUrl: targetUrl ?? this.targetUrl,
    allowPrivateNetwork: allowPrivateNetwork ?? this.allowPrivateNetwork,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    defaultLayoutMode: defaultLayoutMode ?? this.defaultLayoutMode,
  );
}

class Identity {
  final String id;
  final String projectId;
  final String name;
  final String color;
  final IsolationMode isolationMode;
  final String? devicePresetId;
  final String startPath;

  const Identity({
    required this.id,
    required this.projectId,
    required this.name,
    required this.color,
    required this.isolationMode,
    this.devicePresetId,
    this.startPath = '/',
  });

  Identity copyWith({
    String? name,
    String? color,
    IsolationMode? isolationMode,
    String? devicePresetId,
    String? startPath,
  }) => Identity(
    id: id,
    projectId: projectId,
    name: name ?? this.name,
    color: color ?? this.color,
    isolationMode: isolationMode ?? this.isolationMode,
    devicePresetId: devicePresetId ?? this.devicePresetId,
    startPath: startPath ?? this.startPath,
  );
}

class PanelLayout {
  final String identityId;
  final double x;
  final double y;
  final double width;
  final double height;
  final int zIndex;
  final bool minimized;
  final bool detached;

  const PanelLayout({
    required this.identityId,
    this.x = 0,
    this.y = 0,
    this.width = 400,
    this.height = 300,
    this.zIndex = 0,
    this.minimized = false,
    this.detached = false,
  });

  PanelLayout copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    int? zIndex,
    bool? minimized,
    bool? detached,
  }) => PanelLayout(
    identityId: identityId,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    zIndex: zIndex ?? this.zIndex,
    minimized: minimized ?? this.minimized,
    detached: detached ?? this.detached,
  );
}

class WorkspaceLayout {
  final String id;
  final String projectId;
  final String name;
  final double viewportX;
  final double viewportY;
  final double zoom;
  final LayoutMode layoutMode;
  final int updatedAt;
  final List<PanelLayout> panels;

  const WorkspaceLayout({
    required this.id,
    required this.projectId,
    required this.name,
    this.viewportX = 0,
    this.viewportY = 0,
    this.zoom = 1,
    this.layoutMode = LayoutMode.canvas,
    required this.updatedAt,
    this.panels = const [],
  });
}

/// Result of [WebviewAdapter.openDevTools]. WKWebView has no programmatic
/// Chromium-style DevTools window, so the native side reports whether the
/// Web Inspector is enabled and how the user opens it.
class DevToolsReport {
  final bool opened;
  final bool available;
  final String? howToOpen;

  const DevToolsReport({
    this.opened = false,
    this.available = false,
    this.howToOpen,
  });
}

/// Platform capabilities probe result.
class RuntimeCapabilities {
  final bool devtools;
  final bool nativeProfiles;
  final bool customUserAgent;
  final bool deviceMetricsOverride;
  final bool touchEmulation;
  final bool networkThrottling;
  final bool clearProfileData;

  const RuntimeCapabilities({
    this.devtools = false,
    this.nativeProfiles = false,
    this.customUserAgent = false,
    this.deviceMetricsOverride = false,
    this.touchEmulation = false,
    this.networkThrottling = false,
    this.clearProfileData = false,
  });
}
