// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get newProject => 'New Project';

  @override
  String get editProject => 'Edit Project';

  @override
  String get welcomeTitle => 'Welcome to Relay Desk';

  @override
  String get welcomeDescription =>
      'Create your first project to start managing isolated WebView identities.';

  @override
  String get createProject => 'Create Project';

  @override
  String get editProjectTooltip => 'Edit project';

  @override
  String get deleteProjectTooltip => 'Delete project';

  @override
  String errorMessage(String error) {
    return 'Error: $error';
  }

  @override
  String get fieldName => 'Name';

  @override
  String get fieldTargetUrl => 'Target URL';

  @override
  String get allowPrivateNetwork => 'Allow private network';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String deleteProjectTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get deleteProjectBody =>
      'This deletes the project, all its identities and saved workspaces (cascade). Browser profiles are not removed.';

  @override
  String get identitiesTitle => 'Identities';

  @override
  String get newIdentity => 'New Identity';

  @override
  String get editIdentity => 'Edit Identity';

  @override
  String get noIdentitiesTitle => 'No Identities';

  @override
  String get noIdentitiesDescription =>
      'Create an identity to open an isolated WebView panel for this project.';

  @override
  String get createIdentity => 'Create Identity';

  @override
  String get editIdentityTooltip => 'Edit identity';

  @override
  String get deleteIdentityTooltip => 'Delete identity';

  @override
  String get fieldIsolation => 'Isolation';

  @override
  String get fieldDevicePreset => 'Device';

  @override
  String get devicePresetTooltip => 'Device emulation';

  @override
  String get fieldColor => 'Color (#RRGGBB)';

  @override
  String get fieldStartPath => 'Start path';

  @override
  String get sharedSessionWarning =>
      'Shared Session is NOT isolated. All identities share one data store.';

  @override
  String deleteIdentityTitle(String name) {
    return 'Delete identity $name?';
  }

  @override
  String get deleteIdentityBody =>
      'This removes the identity row. Use \"Clear identity data\" in the panel header to wipe the browser profile/data store.';

  @override
  String get isolationNativeProfile => 'Native Profile';

  @override
  String get isolationOriginProxy => 'Origin Proxy';

  @override
  String get isolationSharedSession => 'Shared Session (not isolated)';

  @override
  String get languageMenuTooltip => 'Language';

  @override
  String get languageFollowSystem => 'Follow system';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '简体中文';

  @override
  String get noProjectSelectedTitle => 'No Project Selected';

  @override
  String get noProjectSelectedDescription =>
      'Select a project from the sidebar, or create a new one to start opening isolated WebView panels.';

  @override
  String get projectNotFound => 'Project not found';

  @override
  String noIdentitiesInProjectTitle(String name) {
    return 'No Identities in $name';
  }

  @override
  String get noIdentitiesInProjectDescription =>
      'Create an identity in the sidebar to open an isolated WebView panel.';

  @override
  String get noPanelsTitle => 'No Panels';

  @override
  String get noPanelsDescription =>
      'All panels are minimized. Restore one from the toolbar.';

  @override
  String identityCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count identities',
      one: '1 identity',
    );
    return '$_temp0';
  }

  @override
  String panelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count panels',
      one: '1 panel',
    );
    return '$_temp0';
  }

  @override
  String get nativeProfilesAvailable => 'Native profiles available (macOS 14+)';

  @override
  String get nativeProfilesUnavailable => 'Native profiles NOT available';

  @override
  String get layoutCanvas => 'Canvas';

  @override
  String get layoutGrid => 'Grid';

  @override
  String get layoutColumns => 'Columns';

  @override
  String get layoutFocus => 'Focus';

  @override
  String get workspaceHint => 'Workspace';

  @override
  String get workspaceNone => '— none —';

  @override
  String get workspaceLoadError => 'Workspace error';

  @override
  String get saveWorkspaceTooltip => 'Save workspace';

  @override
  String get deleteWorkspaceTooltip => 'Delete workspace';

  @override
  String get saveWorkspaceTitle => 'Save workspace';

  @override
  String get notIsolatedBadge => 'NOT ISOLATED';

  @override
  String get detachToWindowTooltip => 'Detach to window';

  @override
  String get clearIdentityDataTooltip => 'Clear identity data';

  @override
  String get navBack => 'Back';

  @override
  String get navForward => 'Forward';

  @override
  String get navStop => 'Stop';

  @override
  String get navReload => 'Reload';

  @override
  String get devtools => 'DevTools';

  @override
  String get devtoolsOpened => 'Web Inspector enabled';

  @override
  String get devtoolsUnavailable =>
      'DevTools are only available in debug builds';

  @override
  String get copyLink => 'Copy link';

  @override
  String get muteMedia => 'Mute media';

  @override
  String get unmuteMedia => 'Unmute media';

  @override
  String get measureMode => 'Measure mode (Esc to exit)';

  @override
  String get manageCustomSizes => 'Custom sizes…';

  @override
  String get addCustomSize => 'Add size';

  @override
  String get customSizeName => 'Name (optional)';

  @override
  String get customSizeWidth => 'Width (px)';

  @override
  String get customSizeHeight => 'Height (px)';

  @override
  String customSizeInvalid(int min, int max) {
    return 'Width/height must be $min–$max px';
  }

  @override
  String get fullscreenPanel => 'Fullscreen panel';

  @override
  String get closePanel => 'Close panel';

  @override
  String webviewNotSupported(String os) {
    return 'WebView not supported on $os (NOT_TESTED)';
  }

  @override
  String get stateClosed => 'closed';

  @override
  String get stateOpening => 'opening';

  @override
  String get stateEmbedded => 'embedded';

  @override
  String get stateDetaching => 'detaching';

  @override
  String get stateDetached => 'detached';

  @override
  String get stateAttaching => 'attaching';

  @override
  String get stateClosing => 'closing';

  @override
  String get stateFailed => 'failed';

  @override
  String get tagSelectedHint => 'Selected · tap to locate';

  @override
  String get tagResidentHint => 'Resident · tap to restore';

  @override
  String get closeTabTooltip => 'Close tab';

  @override
  String newWindowError(String error) {
    return 'Unable to open new window: $error';
  }

  @override
  String get residentQuickSitesLabel => 'Resident quick sites';

  @override
  String releaseResidentTooltip(String name) {
    return 'Release resident $name';
  }

  @override
  String get quickSites => 'Quick Sites';

  @override
  String get quickSitesSearchHint => 'Search sites…';

  @override
  String get quickSitesRecent => 'Recently used';

  @override
  String get quickSitesAll => 'All sites';

  @override
  String get quickSitesNoMatch => 'No matching sites';

  @override
  String get quickSitesClose => 'Close';

  @override
  String get quickSitesKeepAlive => 'Resident';

  @override
  String get quickSitesOpenOverlay => 'Open overlay';

  @override
  String get quickSitesDockRight => 'Dock to right';

  @override
  String get quickSitesOpenNewWindow => 'Open in new window';

  @override
  String quickSiteHostUnsupported(String name) {
    return 'Quick site host: $name\nWebView not supported here (NOT_TESTED).';
  }

  @override
  String quickSiteLoadFailed(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get retry => 'Retry';

  @override
  String get reloadTooltip => 'Reload';

  @override
  String get closeTooltip => 'Close';

  @override
  String get diagnosticsLogTooltip => 'Copy diagnostics log path';

  @override
  String diagnosticsLogCopied(String path) {
    return 'Diagnostics log path copied: $path';
  }

  @override
  String get diagnosticsLogUnavailable => 'No diagnostics log on this platform';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get appIconTitle => 'App icon';

  @override
  String get appIconDescription =>
      'Choose your planet. Your selection is saved automatically.';

  @override
  String get iconA1 => 'Ember planet';

  @override
  String get iconA2 => 'Mars planet';

  @override
  String get iconB1 => 'Ocean blue';

  @override
  String get iconB2 => 'Mint ice';

  @override
  String get iconC1 => 'Blue pearl';

  @override
  String get iconC3 => 'Ice crystal';

  @override
  String get defaultIcon => 'Default';

  @override
  String get restoreDefaultIcon => 'Restore B2 default';

  @override
  String get settingsDone => 'Done';

  @override
  String get iconSaveFailed => 'Could not update the icon. Please try again.';

  @override
  String get appIconPlatformNote =>
      'The app logo and macOS Dock icon update immediately. Finder uses the bundled B2 icon.';

  @override
  String get dockIconMenu => 'Switch Icon';
}
