import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// Tooltip for the create-project button and title of the create-project dialog.
  ///
  /// In en, this message translates to:
  /// **'New Project'**
  String get newProject;

  /// Title of the edit-project dialog.
  ///
  /// In en, this message translates to:
  /// **'Edit Project'**
  String get editProject;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Relay Desk'**
  String get welcomeTitle;

  /// No description provided for @welcomeDescription.
  ///
  /// In en, this message translates to:
  /// **'Create your first project to start managing isolated WebView identities.'**
  String get welcomeDescription;

  /// No description provided for @createProject.
  ///
  /// In en, this message translates to:
  /// **'Create Project'**
  String get createProject;

  /// No description provided for @editProjectTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit project'**
  String get editProjectTooltip;

  /// No description provided for @deleteProjectTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete project'**
  String get deleteProjectTooltip;

  /// No description provided for @errorMessage.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorMessage(String error);

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fieldName;

  /// No description provided for @fieldTargetUrl.
  ///
  /// In en, this message translates to:
  /// **'Target URL'**
  String get fieldTargetUrl;

  /// No description provided for @allowPrivateNetwork.
  ///
  /// In en, this message translates to:
  /// **'Allow private network'**
  String get allowPrivateNetwork;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String deleteProjectTitle(String name);

  /// No description provided for @deleteProjectBody.
  ///
  /// In en, this message translates to:
  /// **'This deletes the project, all its identities and saved workspaces (cascade). Browser profiles are not removed.'**
  String get deleteProjectBody;

  /// No description provided for @identitiesTitle.
  ///
  /// In en, this message translates to:
  /// **'Identities'**
  String get identitiesTitle;

  /// No description provided for @newIdentity.
  ///
  /// In en, this message translates to:
  /// **'New Identity'**
  String get newIdentity;

  /// No description provided for @editIdentity.
  ///
  /// In en, this message translates to:
  /// **'Edit Identity'**
  String get editIdentity;

  /// No description provided for @noIdentitiesTitle.
  ///
  /// In en, this message translates to:
  /// **'No Identities'**
  String get noIdentitiesTitle;

  /// No description provided for @noIdentitiesDescription.
  ///
  /// In en, this message translates to:
  /// **'Create an identity to open an isolated WebView panel for this project.'**
  String get noIdentitiesDescription;

  /// No description provided for @createIdentity.
  ///
  /// In en, this message translates to:
  /// **'Create Identity'**
  String get createIdentity;

  /// No description provided for @editIdentityTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit identity'**
  String get editIdentityTooltip;

  /// No description provided for @deleteIdentityTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete identity'**
  String get deleteIdentityTooltip;

  /// No description provided for @fieldIsolation.
  ///
  /// In en, this message translates to:
  /// **'Isolation'**
  String get fieldIsolation;

  /// No description provided for @fieldDevicePreset.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get fieldDevicePreset;

  /// No description provided for @devicePresetTooltip.
  ///
  /// In en, this message translates to:
  /// **'Device emulation'**
  String get devicePresetTooltip;

  /// No description provided for @fieldColor.
  ///
  /// In en, this message translates to:
  /// **'Color (#RRGGBB)'**
  String get fieldColor;

  /// No description provided for @fieldStartPath.
  ///
  /// In en, this message translates to:
  /// **'Start path'**
  String get fieldStartPath;

  /// No description provided for @sharedSessionWarning.
  ///
  /// In en, this message translates to:
  /// **'Shared Session is NOT isolated. All identities share one data store.'**
  String get sharedSessionWarning;

  /// No description provided for @deleteIdentityTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete identity {name}?'**
  String deleteIdentityTitle(String name);

  /// No description provided for @deleteIdentityBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the identity row. Use \"Clear identity data\" in the panel header to wipe the browser profile/data store.'**
  String get deleteIdentityBody;

  /// No description provided for @isolationNativeProfile.
  ///
  /// In en, this message translates to:
  /// **'Native Profile'**
  String get isolationNativeProfile;

  /// No description provided for @isolationOriginProxy.
  ///
  /// In en, this message translates to:
  /// **'Origin Proxy'**
  String get isolationOriginProxy;

  /// No description provided for @isolationSharedSession.
  ///
  /// In en, this message translates to:
  /// **'Shared Session (not isolated)'**
  String get isolationSharedSession;

  /// No description provided for @languageMenuTooltip.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageMenuTooltip;

  /// No description provided for @languageFollowSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get languageFollowSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get languageChinese;

  /// No description provided for @noProjectSelectedTitle.
  ///
  /// In en, this message translates to:
  /// **'No Project Selected'**
  String get noProjectSelectedTitle;

  /// No description provided for @noProjectSelectedDescription.
  ///
  /// In en, this message translates to:
  /// **'Select a project from the sidebar, or create a new one to start opening isolated WebView panels.'**
  String get noProjectSelectedDescription;

  /// No description provided for @projectNotFound.
  ///
  /// In en, this message translates to:
  /// **'Project not found'**
  String get projectNotFound;

  /// No description provided for @noIdentitiesInProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'No Identities in {name}'**
  String noIdentitiesInProjectTitle(String name);

  /// No description provided for @noIdentitiesInProjectDescription.
  ///
  /// In en, this message translates to:
  /// **'Create an identity in the sidebar to open an isolated WebView panel.'**
  String get noIdentitiesInProjectDescription;

  /// No description provided for @noPanelsTitle.
  ///
  /// In en, this message translates to:
  /// **'No Panels'**
  String get noPanelsTitle;

  /// No description provided for @noPanelsDescription.
  ///
  /// In en, this message translates to:
  /// **'All panels are minimized. Restore one from the toolbar.'**
  String get noPanelsDescription;

  /// No description provided for @identityCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 identity} other{{count} identities}}'**
  String identityCount(int count);

  /// No description provided for @panelCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 panel} other{{count} panels}}'**
  String panelCount(int count);

  /// No description provided for @nativeProfilesAvailable.
  ///
  /// In en, this message translates to:
  /// **'Native profiles available (macOS 14+)'**
  String get nativeProfilesAvailable;

  /// No description provided for @nativeProfilesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Native profiles NOT available'**
  String get nativeProfilesUnavailable;

  /// No description provided for @layoutCanvas.
  ///
  /// In en, this message translates to:
  /// **'Canvas'**
  String get layoutCanvas;

  /// No description provided for @layoutGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get layoutGrid;

  /// No description provided for @layoutColumns.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get layoutColumns;

  /// No description provided for @layoutFocus.
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get layoutFocus;

  /// No description provided for @workspaceHint.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get workspaceHint;

  /// No description provided for @workspaceNone.
  ///
  /// In en, this message translates to:
  /// **'— none —'**
  String get workspaceNone;

  /// No description provided for @workspaceLoadError.
  ///
  /// In en, this message translates to:
  /// **'Workspace error'**
  String get workspaceLoadError;

  /// No description provided for @saveWorkspaceTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save workspace'**
  String get saveWorkspaceTooltip;

  /// No description provided for @deleteWorkspaceTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete workspace'**
  String get deleteWorkspaceTooltip;

  /// No description provided for @saveWorkspaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Save workspace'**
  String get saveWorkspaceTitle;

  /// No description provided for @notIsolatedBadge.
  ///
  /// In en, this message translates to:
  /// **'NOT ISOLATED'**
  String get notIsolatedBadge;

  /// No description provided for @detachToWindowTooltip.
  ///
  /// In en, this message translates to:
  /// **'Detach to window'**
  String get detachToWindowTooltip;

  /// No description provided for @clearIdentityDataTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear identity data'**
  String get clearIdentityDataTooltip;

  /// No description provided for @navBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get navBack;

  /// No description provided for @navForward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get navForward;

  /// No description provided for @navStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get navStop;

  /// No description provided for @navReload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get navReload;

  /// No description provided for @devtools.
  ///
  /// In en, this message translates to:
  /// **'DevTools'**
  String get devtools;

  /// No description provided for @devtoolsOpened.
  ///
  /// In en, this message translates to:
  /// **'Web Inspector enabled'**
  String get devtoolsOpened;

  /// No description provided for @devtoolsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'DevTools are only available in debug builds'**
  String get devtoolsUnavailable;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @qrCodeLink.
  ///
  /// In en, this message translates to:
  /// **'Link QR code'**
  String get qrCodeLink;

  /// No description provided for @qrLinkField.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get qrLinkField;

  /// No description provided for @muteMedia.
  ///
  /// In en, this message translates to:
  /// **'Mute media'**
  String get muteMedia;

  /// No description provided for @unmuteMedia.
  ///
  /// In en, this message translates to:
  /// **'Unmute media'**
  String get unmuteMedia;

  /// No description provided for @measureMode.
  ///
  /// In en, this message translates to:
  /// **'Measure mode (Esc to exit)'**
  String get measureMode;

  /// No description provided for @manageCustomSizes.
  ///
  /// In en, this message translates to:
  /// **'Custom sizes…'**
  String get manageCustomSizes;

  /// No description provided for @addCustomSize.
  ///
  /// In en, this message translates to:
  /// **'Add size'**
  String get addCustomSize;

  /// No description provided for @customSizeName.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get customSizeName;

  /// No description provided for @customSizeWidth.
  ///
  /// In en, this message translates to:
  /// **'Width (px)'**
  String get customSizeWidth;

  /// No description provided for @customSizeHeight.
  ///
  /// In en, this message translates to:
  /// **'Height (px)'**
  String get customSizeHeight;

  /// No description provided for @customSizeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Width/height must be {min}–{max} px'**
  String customSizeInvalid(int min, int max);

  /// No description provided for @fullscreenPanel.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen panel'**
  String get fullscreenPanel;

  /// No description provided for @closePanel.
  ///
  /// In en, this message translates to:
  /// **'Close panel'**
  String get closePanel;

  /// No description provided for @webviewNotSupported.
  ///
  /// In en, this message translates to:
  /// **'WebView not supported on {os} (NOT_TESTED)'**
  String webviewNotSupported(String os);

  /// No description provided for @stateClosed.
  ///
  /// In en, this message translates to:
  /// **'closed'**
  String get stateClosed;

  /// No description provided for @stateOpening.
  ///
  /// In en, this message translates to:
  /// **'opening'**
  String get stateOpening;

  /// No description provided for @stateEmbedded.
  ///
  /// In en, this message translates to:
  /// **'embedded'**
  String get stateEmbedded;

  /// No description provided for @stateDetaching.
  ///
  /// In en, this message translates to:
  /// **'detaching'**
  String get stateDetaching;

  /// No description provided for @stateDetached.
  ///
  /// In en, this message translates to:
  /// **'detached'**
  String get stateDetached;

  /// No description provided for @stateAttaching.
  ///
  /// In en, this message translates to:
  /// **'attaching'**
  String get stateAttaching;

  /// No description provided for @stateClosing.
  ///
  /// In en, this message translates to:
  /// **'closing'**
  String get stateClosing;

  /// No description provided for @stateFailed.
  ///
  /// In en, this message translates to:
  /// **'failed'**
  String get stateFailed;

  /// No description provided for @tagSelectedHint.
  ///
  /// In en, this message translates to:
  /// **'Selected · tap to locate'**
  String get tagSelectedHint;

  /// No description provided for @tagResidentHint.
  ///
  /// In en, this message translates to:
  /// **'Resident · tap to restore'**
  String get tagResidentHint;

  /// No description provided for @closeTabTooltip.
  ///
  /// In en, this message translates to:
  /// **'Close tab'**
  String get closeTabTooltip;

  /// No description provided for @newWindowError.
  ///
  /// In en, this message translates to:
  /// **'Unable to open new window: {error}'**
  String newWindowError(String error);

  /// No description provided for @residentQuickSitesLabel.
  ///
  /// In en, this message translates to:
  /// **'Resident quick sites'**
  String get residentQuickSitesLabel;

  /// No description provided for @releaseResidentTooltip.
  ///
  /// In en, this message translates to:
  /// **'Release resident {name}'**
  String releaseResidentTooltip(String name);

  /// No description provided for @quickSites.
  ///
  /// In en, this message translates to:
  /// **'Quick Sites'**
  String get quickSites;

  /// No description provided for @quickSitesSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search sites…'**
  String get quickSitesSearchHint;

  /// No description provided for @quickSitesRecent.
  ///
  /// In en, this message translates to:
  /// **'Recently used'**
  String get quickSitesRecent;

  /// No description provided for @quickSitesAll.
  ///
  /// In en, this message translates to:
  /// **'All sites'**
  String get quickSitesAll;

  /// No description provided for @quickSitesNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No matching sites'**
  String get quickSitesNoMatch;

  /// No description provided for @quickSitesClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get quickSitesClose;

  /// No description provided for @quickSitesKeepAlive.
  ///
  /// In en, this message translates to:
  /// **'Resident'**
  String get quickSitesKeepAlive;

  /// No description provided for @quickSitesOpenOverlay.
  ///
  /// In en, this message translates to:
  /// **'Open overlay'**
  String get quickSitesOpenOverlay;

  /// No description provided for @quickSitesDockRight.
  ///
  /// In en, this message translates to:
  /// **'Dock to right'**
  String get quickSitesDockRight;

  /// No description provided for @quickSitesOpenNewWindow.
  ///
  /// In en, this message translates to:
  /// **'Open in new window'**
  String get quickSitesOpenNewWindow;

  /// No description provided for @quickSiteHostUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Quick site host: {name}\nWebView not supported here (NOT_TESTED).'**
  String quickSiteHostUnsupported(String name);

  /// No description provided for @quickSiteLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {error}'**
  String quickSiteLoadFailed(String error);

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @reloadTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reload (⌘R)'**
  String get reloadTooltip;

  /// No description provided for @closeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeTooltip;

  /// No description provided for @diagnosticsLogTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy diagnostics log path'**
  String get diagnosticsLogTooltip;

  /// No description provided for @diagnosticsLogCopied.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics log path copied: {path}'**
  String diagnosticsLogCopied(String path);

  /// No description provided for @diagnosticsLogUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No diagnostics log on this platform'**
  String get diagnosticsLogUnavailable;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @appIconTitle.
  ///
  /// In en, this message translates to:
  /// **'App icon'**
  String get appIconTitle;

  /// No description provided for @appIconDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose your planet. Your selection is saved automatically.'**
  String get appIconDescription;

  /// No description provided for @iconA1.
  ///
  /// In en, this message translates to:
  /// **'Ember planet'**
  String get iconA1;

  /// No description provided for @iconA2.
  ///
  /// In en, this message translates to:
  /// **'Mars planet'**
  String get iconA2;

  /// No description provided for @iconB1.
  ///
  /// In en, this message translates to:
  /// **'Ocean blue'**
  String get iconB1;

  /// No description provided for @iconB2.
  ///
  /// In en, this message translates to:
  /// **'Mint ice'**
  String get iconB2;

  /// No description provided for @iconC1.
  ///
  /// In en, this message translates to:
  /// **'Blue pearl'**
  String get iconC1;

  /// No description provided for @iconC3.
  ///
  /// In en, this message translates to:
  /// **'Ice crystal'**
  String get iconC3;

  /// No description provided for @defaultIcon.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultIcon;

  /// No description provided for @restoreDefaultIcon.
  ///
  /// In en, this message translates to:
  /// **'Restore B2 default'**
  String get restoreDefaultIcon;

  /// No description provided for @settingsDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get settingsDone;

  /// No description provided for @iconSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update the icon. Please try again.'**
  String get iconSaveFailed;

  /// No description provided for @appIconPlatformNote.
  ///
  /// In en, this message translates to:
  /// **'The app logo and macOS Dock icon update immediately. Finder uses the bundled B2 icon.'**
  String get appIconPlatformNote;

  /// No description provided for @dockIconMenu.
  ///
  /// In en, this message translates to:
  /// **'Switch Icon'**
  String get dockIconMenu;

  /// No description provided for @updateSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get updateSectionTitle;

  /// No description provided for @updateAutoCheck.
  ///
  /// In en, this message translates to:
  /// **'Check for updates automatically'**
  String get updateAutoCheck;

  /// No description provided for @updateAutoDownload.
  ///
  /// In en, this message translates to:
  /// **'Download updates automatically'**
  String get updateAutoDownload;

  /// No description provided for @updateCheckNow.
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get updateCheckNow;

  /// No description provided for @updateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get updateChecking;

  /// No description provided for @updateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Relay Desk is up to date'**
  String get updateUpToDate;

  /// No description provided for @updateAvailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Update available: v{version}'**
  String updateAvailableTitle(String version);

  /// No description provided for @updateDownloadedTitle.
  ///
  /// In en, this message translates to:
  /// **'Update ready: v{version}'**
  String updateDownloadedTitle(String version);

  /// No description provided for @updateVersionTransition.
  ///
  /// In en, this message translates to:
  /// **'{current} → v{latest}'**
  String updateVersionTransition(String current, String latest);

  /// No description provided for @updateWhatsNew.
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get updateWhatsNew;

  /// No description provided for @updateDownload.
  ///
  /// In en, this message translates to:
  /// **'Download update'**
  String get updateDownload;

  /// No description provided for @updateDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading… {percent}%'**
  String updateDownloading(String percent);

  /// No description provided for @updateVerifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying download…'**
  String get updateVerifying;

  /// No description provided for @updateInstalling.
  ///
  /// In en, this message translates to:
  /// **'Installing…'**
  String get updateInstalling;

  /// No description provided for @updateReadyHint.
  ///
  /// In en, this message translates to:
  /// **'The update has been downloaded. Relay Desk quits and relaunches to finish installing.'**
  String get updateReadyHint;

  /// No description provided for @updateInstallRestart.
  ///
  /// In en, this message translates to:
  /// **'Install & relaunch'**
  String get updateInstallRestart;

  /// No description provided for @updateLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get updateLater;

  /// No description provided for @updateSkipVersion.
  ///
  /// In en, this message translates to:
  /// **'Skip this version'**
  String get updateSkipVersion;

  /// No description provided for @updateSkippedVersion.
  ///
  /// In en, this message translates to:
  /// **'Skipped version {version}'**
  String updateSkippedVersion(String version);

  /// No description provided for @updateClearSkip.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get updateClearSkip;

  /// No description provided for @updateCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel download'**
  String get updateCancel;

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed: {error}'**
  String updateFailed(String error);

  /// No description provided for @updateRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get updateRetry;

  /// No description provided for @updateOpenReleasePage.
  ///
  /// In en, this message translates to:
  /// **'Open download page'**
  String get updateOpenReleasePage;

  /// No description provided for @updateNoAsset.
  ///
  /// In en, this message translates to:
  /// **'No installable package for this platform.'**
  String get updateNoAsset;

  /// No description provided for @updateViewPrompt.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get updateViewPrompt;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
