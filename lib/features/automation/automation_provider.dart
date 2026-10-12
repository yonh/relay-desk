import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../platform/webview/macos_profiled_webview_adapter.dart';
import '../workspace/workspace_controller.dart';
import 'automation_queries.dart';
import 'automation_server.dart';

/// This transport is opt-in for a macOS development build. Ordinary release
/// builds never bind a port or create a credential file.
final automationServerProvider = FutureProvider<AutomationServer?>((ref) async {
  if (!kDebugMode ||
      !const bool.fromEnvironment('RELAY_DESK_AUTOMATION') ||
      !Platform.isMacOS) {
    return null;
  }
  final adapter = ref.read(webviewAdapterProvider);
  if (adapter is! MacosProfiledWebviewAdapter) return null;

  // Repositories are awaited once at startup so a dispatch never suspends on
  // database initialization; UI selection and workspace state are read
  // lazily per request so every command observes the current values.
  final queries = AutomationQueries(
    projects: await ref.read(projectRepositoryProvider.future),
    identities: await ref.read(identityRepositoryProvider.future),
    workspaces: await ref.read(workspaceRepositoryProvider.future),
    readWorkspace: () => ref.read(workspaceControllerProvider),
    readSelectedProjectId: () => ref.read(selectedProjectIdProvider),
    readNativeWindows: adapter.windowInventory,
    captureScreenshot: adapter.takeSnapshot,
    sampleMedia: adapter.sampleMedia,
    drainJsErrors: adapter.drainJsErrors,
    probeDom: adapter.probeDom,
    domFind: adapter.domFind,
    domInspect: adapter.domInspect,
    domClick: adapter.domClick,
    domInput: adapter.domInput,
    domKey: adapter.domKey,
    domScroll: adapter.domScroll,
    // The same provider call the project sidebar makes — activation keeps
    // the UI's own semantics (layout restore, panel sync, selection).
    selectProject: (projectId) =>
        ref.read(selectedProjectIdProvider.notifier).select(projectId),
    // The same ensurePanel the workspace sync calls — identity entry,
    // session and display rules are the UI's own.
    ensurePanel: (identity, project) => ref
        .read(workspaceControllerProvider.notifier)
        .ensurePanel(identity, project),
    awaitFrame: () => SchedulerBinding.instance.endOfFrame,
    // The same navigate the address bar calls — URL normalization and the
    // panel loading flag stay on the app's own path (issue #23).
    navigatePanel: (identityId, url) =>
        ref.read(workspaceControllerProvider.notifier).navigate(
              identityId,
              url,
            ),
    // The same reload the toolbar/Cmd+R path calls — WK reload() with
    // normal cache semantics (issue #28).
    reloadPanel: (identityId) =>
        ref.read(workspaceControllerProvider.notifier).reload(identityId),
    // The same goBack the toolbar/side-button path calls — WK
    // backForwardList traversal on the app's own path (issue #29).
    backPanel: (identityId) =>
        ref.read(workspaceControllerProvider.notifier).back(identityId),
    canGoBackPanel: (identityId) =>
        adapter.navInfoFor(identityId).canGoBack,
    forwardPanel: (identityId) =>
        ref.read(workspaceControllerProvider.notifier).forward(identityId),
    canGoForwardPanel: (identityId) =>
        adapter.navInfoFor(identityId).canGoForward,
    pullHistoryState: (identityId) => adapter.pullHistoryState(identityId),
    isNavigating: (identityId) => adapter.navInfoFor(identityId).loading,
    navigationEvents: () => adapter.events,
  );
  if (!ref.mounted) return null;

  final server = AutomationServer(dispatch: queries.dispatch);
  ref.onDispose(() => unawaited(server.close()));
  try {
    final support = await getApplicationSupportDirectory();
    if (!ref.mounted) return null;
    final directory = Directory('${support.path}/automation');
    await server.start(directory);
    if (!ref.mounted) {
      await server.close();
      return null;
    }
    debugPrint('Relay Desk automation session directory: ${directory.path}');
    return server;
  } catch (_) {
    debugPrint(
      'Relay Desk automation could not start; normal workspace remains available.',
    );
    return null;
  }
});
