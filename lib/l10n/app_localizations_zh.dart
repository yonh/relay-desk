// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get newProject => '新建项目';

  @override
  String get editProject => '编辑项目';

  @override
  String get welcomeTitle => '欢迎使用 Relay Desk';

  @override
  String get welcomeDescription => '创建第一个项目，开始管理隔离的 WebView 身份。';

  @override
  String get createProject => '创建项目';

  @override
  String get editProjectTooltip => '编辑项目';

  @override
  String get deleteProjectTooltip => '删除项目';

  @override
  String errorMessage(String error) {
    return '错误：$error';
  }

  @override
  String get fieldName => '名称';

  @override
  String get fieldTargetUrl => '目标 URL';

  @override
  String get allowPrivateNetwork => '允许访问私有网络';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String deleteProjectTitle(String name) {
    return '删除 $name？';
  }

  @override
  String get deleteProjectBody => '将删除该项目及其所有身份和已保存的工作区（级联）。浏览器配置文件不会被移除。';

  @override
  String get identitiesTitle => '身份';

  @override
  String get newIdentity => '新建身份';

  @override
  String get editIdentity => '编辑身份';

  @override
  String get noIdentitiesTitle => '暂无身份';

  @override
  String get noIdentitiesDescription => '创建身份即可为此项目打开隔离的 WebView 面板。';

  @override
  String get createIdentity => '创建身份';

  @override
  String get editIdentityTooltip => '编辑身份';

  @override
  String get deleteIdentityTooltip => '删除身份';

  @override
  String get fieldIsolation => '隔离方式';

  @override
  String get fieldDevicePreset => '设备';

  @override
  String get devicePresetTooltip => '设备模拟';

  @override
  String get fieldColor => '颜色 (#RRGGBB)';

  @override
  String get fieldStartPath => '起始路径';

  @override
  String get sharedSessionWarning => 'Shared Session 不隔离。所有身份共享同一个数据存储。';

  @override
  String deleteIdentityTitle(String name) {
    return '删除身份 $name？';
  }

  @override
  String get deleteIdentityBody =>
      '仅删除该身份记录。如需清除浏览器配置文件/数据存储，请使用面板标题栏中的“清除身份数据”。';

  @override
  String get isolationNativeProfile => '原生配置文件';

  @override
  String get isolationOriginProxy => '源站代理';

  @override
  String get isolationSharedSession => '共享会话（不隔离）';

  @override
  String get languageMenuTooltip => '语言';

  @override
  String get languageFollowSystem => '跟随系统';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '简体中文';

  @override
  String get noProjectSelectedTitle => '未选择项目';

  @override
  String get noProjectSelectedDescription =>
      '从侧栏选择一个项目，或新建项目以打开隔离的 WebView 面板。';

  @override
  String get projectNotFound => '未找到项目';

  @override
  String noIdentitiesInProjectTitle(String name) {
    return '$name 暂无身份';
  }

  @override
  String get noIdentitiesInProjectDescription => '在侧栏创建身份即可打开隔离的 WebView 面板。';

  @override
  String get noPanelsTitle => '暂无面板';

  @override
  String get noPanelsDescription => '所有面板已最小化。请从工具栏恢复一个面板。';

  @override
  String identityCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个身份',
    );
    return '$_temp0';
  }

  @override
  String panelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个面板',
    );
    return '$_temp0';
  }

  @override
  String get nativeProfilesAvailable => '原生配置文件可用（macOS 14+）';

  @override
  String get nativeProfilesUnavailable => '原生配置文件不可用';

  @override
  String get layoutCanvas => '画布';

  @override
  String get layoutGrid => '网格';

  @override
  String get layoutColumns => '分栏';

  @override
  String get layoutFocus => '聚焦';

  @override
  String get workspaceHint => '工作区';

  @override
  String get workspaceNone => '— 无 —';

  @override
  String get workspaceLoadError => '工作区错误';

  @override
  String get saveWorkspaceTooltip => '保存工作区';

  @override
  String get deleteWorkspaceTooltip => '删除工作区';

  @override
  String get saveWorkspaceTitle => '保存工作区';

  @override
  String get notIsolatedBadge => '不隔离';

  @override
  String get detachToWindowTooltip => '分离到窗口';

  @override
  String get clearIdentityDataTooltip => '清除身份数据';

  @override
  String get navBack => '后退';

  @override
  String get navForward => '前进';

  @override
  String get navStop => '停止';

  @override
  String get navReload => '刷新';

  @override
  String get devtools => '开发者工具';

  @override
  String get devtoolsOpened => 'Web 检查器已启用';

  @override
  String get devtoolsUnavailable => '开发者工具仅在调试构建中可用';

  @override
  String get copyLink => '复制链接';

  @override
  String get muteMedia => '静音媒体';

  @override
  String get unmuteMedia => '取消静音';

  @override
  String get measureMode => '测量模式（Esc 退出）';

  @override
  String get manageCustomSizes => '自定义尺寸…';

  @override
  String get addCustomSize => '添加尺寸';

  @override
  String get customSizeName => '名称（可选）';

  @override
  String get customSizeWidth => '宽度（px）';

  @override
  String get customSizeHeight => '高度（px）';

  @override
  String customSizeInvalid(int min, int max) {
    return '宽高需在 $min–$max 像素之间';
  }

  @override
  String get fullscreenPanel => '全屏面板';

  @override
  String get closePanel => '关闭面板';

  @override
  String webviewNotSupported(String os) {
    return 'WebView 在 $os 上不受支持（NOT_TESTED）';
  }

  @override
  String get stateClosed => '已关闭';

  @override
  String get stateOpening => '打开中';

  @override
  String get stateEmbedded => '已嵌入';

  @override
  String get stateDetaching => '分离中';

  @override
  String get stateDetached => '已分离';

  @override
  String get stateAttaching => '附加中';

  @override
  String get stateClosing => '关闭中';

  @override
  String get stateFailed => '失败';

  @override
  String get tagSelectedHint => '当前选中 · 点击定位';

  @override
  String get tagResidentHint => '常驻中 · 点击恢复';

  @override
  String get closeTabTooltip => '关闭标签';

  @override
  String newWindowError(String error) {
    return '无法打开新窗口：$error';
  }

  @override
  String get residentQuickSitesLabel => '常驻快捷站点';

  @override
  String releaseResidentTooltip(String name) {
    return '关闭常驻 $name';
  }

  @override
  String get quickSites => '快捷站点';

  @override
  String get quickSitesSearchHint => '搜索站点…';

  @override
  String get quickSitesRecent => '最近使用';

  @override
  String get quickSitesAll => '所有站点';

  @override
  String get quickSitesNoMatch => '无匹配站点';

  @override
  String get quickSitesClose => '关闭';

  @override
  String get quickSitesKeepAlive => '常驻';

  @override
  String get quickSitesOpenOverlay => '打开浮层';

  @override
  String get quickSitesDockRight => '固定到右侧';

  @override
  String get quickSitesOpenNewWindow => '在新窗口打开';

  @override
  String quickSiteHostUnsupported(String name) {
    return '快捷站点宿主：$name\n此处不支持 WebView（NOT_TESTED）。';
  }

  @override
  String quickSiteLoadFailed(String error) {
    return '加载失败：$error';
  }

  @override
  String get retry => '重试';

  @override
  String get reloadTooltip => '重新加载';

  @override
  String get closeTooltip => '关闭';

  @override
  String get diagnosticsLogTooltip => '复制诊断日志路径';

  @override
  String diagnosticsLogCopied(String path) {
    return '诊断日志路径已复制：$path';
  }

  @override
  String get diagnosticsLogUnavailable => '当前平台没有诊断日志';

  @override
  String get settingsTitle => '设置';

  @override
  String get appIconTitle => '应用图标';

  @override
  String get appIconDescription => '选择你喜欢的星球图标，选择后自动保存。';

  @override
  String get iconA1 => '赤焰星球';

  @override
  String get iconA2 => '火星';

  @override
  String get iconB1 => '海蓝卫星';

  @override
  String get iconB2 => '薄荷冰星';

  @override
  String get iconC1 => '灰蓝珍珠';

  @override
  String get iconC3 => '冰晶星球';

  @override
  String get defaultIcon => '默认';

  @override
  String get restoreDefaultIcon => '恢复默认 B2';

  @override
  String get settingsDone => '完成';

  @override
  String get iconSaveFailed => '图标更新失败，请重试。';

  @override
  String get appIconPlatformNote =>
      '应用内 Logo 和 macOS Dock 图标即时更新；访达使用安装包默认的 B2 图标。';

  @override
  String get dockIconMenu => '切换图标';
}
