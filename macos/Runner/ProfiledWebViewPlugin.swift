import Cocoa
import FlutterMacOS
import WebKit

// Thin native adapter (ADR-0002): creates per-identity persistent
// WKWebsiteDataStore(forIdentifier:) on macOS 14+ and embeds the WKWebView
// as a Flutter PlatformView. flutter_inappwebview does not expose this API,
// so this minimal adapter is the permitted approach per the rewrite plan.
//
// The adapter is the platform boundary for the formal flutter_app/. It owns:
//   - per-identity persistent data stores
//   - per-viewId WKWebView embedded in a container NSView (so the WebView can
//     be moved into a detached child window and back without breaking the
//     Flutter platform view)
//   - navigation (back/forward/stop/reload), bounds, devtools capability
//   - an event channel that writes platform state back to Dart so the
//     embedded/detached/closed state machine is event-driven, not guessed
//     by the UI (rewrite-plan §4.8).
//
// Remote business pages never receive a JavaScript/Method Channel handle.
final class ProfiledWebViewPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, WKScriptMessageHandler {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "profiled_webview",
            binaryMessenger: registrar.messenger
        )
        let instance = ProfiledWebViewPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
        let eventChannel = FlutterEventChannel(
            name: "profiled_webview_events",
            binaryMessenger: registrar.messenger
        )
        eventChannel.setStreamHandler(instance)
        registrar.register(
            ProfiledWebViewFactory(plugin: instance),
            withId: "profiled_webview"
        )
        DiagnosticsLog.shared.log("pluginRegistered")
    }

    private let channel: FlutterMethodChannel?
    private var eventSink: FlutterEventSink?

    // viewId -> container NSView that Flutter embeds.
    private(set) var containers: [Int64: NSView] = [:]
    // viewId -> WKWebView (subview of containers[viewId]).
    private(set) var webViews: [Int64: WKWebView] = [:]
    // viewId -> observation of the browser's current URL. WKNavigationDelegate
    // does not report History API changes made by single-page applications.
    private var urlObservers: [Int64: NSKeyValueObservation] = [:]
    // Per-WebView, one-way route reporters injected at document start. These
    // report URLs to the native event stream only; they expose no Flutter
    // method channel or native command surface to business pages.
    private var routeHandlerNames: [Int64: String] = [:]
    private var routeHandlerIdentities: [String: String] = [:]
    private var fullscreenHandlerIdentities: [String: String] = [:]
    private var fullscreenHosts: [String: InAppFullscreenHostView] = [:]
    // identityId -> viewId (current embedded view).
    private(set) var viewIdByIdentity: [String: Int64] = [:]
    // identityId -> WKWebsiteDataStore (for clear/restart verification).
    // Only per-identity stores are recorded here; a sharedSession view uses
    // WKWebsiteDataStore.default() which is deliberately NOT cleared by
    // clearIdentityData (doing so would wipe every shared identity's data).
    private(set) var dataStores: [String: WKWebsiteDataStore] = [:]
    // identityId -> UUID used for the data store.
    private(set) var identityUuids: [String: UUID] = [:]
    /// Which data-store kind a live view was created with. Crosses the
    /// method-channel boundary as "shared" / "perIdentity" only for the
    /// evidence-harness `storeKind` call; internally a real enum so the
    /// reuse/clear paths can't drift on a string typo.
    enum StoreKind: String {
        case shared
        case perIdentity
    }

    // identityId -> which store kind the live view was created with.
    // Used to refuse reuse across an isolation-mode switch.
    private(set) var identityStoreKinds: [String: StoreKind] = [:]
    // identityId -> runtime config fingerprint the live view was created with.
    // Reuse paths (reparent, detached reclaim) only fire when it matches.
    private var identityFingerprints: [String: String] = [:]
    // identityId -> detached window controller (when detached).
    private(set) var detachedWindows: [String: DetachedWindowController] = [:]
    // identityId -> emulated CSS viewport size from the active device preset.
    // Stored at view creation and read by `detach` to size the window. For
    // `custom` (viewportFollowsSurface) `setBounds` keeps it tracking the
    // live view surface so the detached window matches the panel's current
    // size instead of a stale creation-time value.
    private(set) var identityViewports: [String: CGSize] = [:]
    // Identities whose detached window should follow the live view surface
    // (`custom` preset) rather than a fixed emulated viewport.
    private var identityViewportFollows: Set<String> = []
    // viewIds with the in-page measure-mode overlay armed. Membership
    // outlives navigation: didFinish re-installs the overlay while the view
    // stays in this set, so reloads don't silently drop measure mode.
    private var measureModeViewIds: Set<Int64> = []
    // viewId -> whether the overlay draws its rulers in-page (detached
    // views) or the Flutter side provides the ruler chrome (embedded).
    private var measureModeRulers: [Int64: Bool] = [:]
    // handlerName -> identityId for the measure-mode exit channel (the
    // overlay's own Escape/destroy path posts here so Dart state stays in
    // sync without a round-trip).
    private var measureHandlerIdentities: [String: String] = [:]
    // viewId -> count of provisional navigations started on that view. The
    // read-only snapshot path binds a request to this generation: a bump
    // between capture start and completion means the page moved and the
    // pixels can no longer be attributed to the recorded target.
    private var navigationGenerations: [Int64: Int] = [:]
    // viewId -> count of navigations committed on that view. A navigation
    // can already be in flight when a snapshot binds itself; binding the
    // commit generation too catches that nav landing mid-capture (including
    // same-URL reloads, which leave webView.url unchanged).
    private var navigationCommitGenerations: [Int64: Int] = [:]
    // Pixel budgets, PNG byte budget, and the one-shot deadline live in
    // SnapshotPolicy.swift (pure Swift, exercised by test/fixtures/snapshot).
    // The deadline stays below the transport's 10 s command bound so the
    // timeout error still reaches the client, and below the adapter's 9 s
    // safety net.
    // viewId -> pending load watchdog. WKWebView can wedge (dead WebContent
    // process, hung per-store network process, view-out-of-window suspension)
    // without ever calling a terminal navigation delegate method; the watchdog
    // fires a synthetic loadFailed so the UI cannot spin forever and the log
    // records the webview's live state for diagnosis.
    private var loadWatchdogs: [Int64: DispatchWorkItem] = [:]

    /// How long a navigation may run without ANY terminal delegate callback
    /// before the watchdog emits loadFailed. Above the default 60s
    /// NSURLRequest timeout so a merely slow server times out for real first.
    static let loadWatchdogInterval: TimeInterval = 75

    /// Maps the Dart IsolationMode.dbValue to the store the view must use.
    /// sharedSession -> shared default store (persistent, not isolated).
    /// Everything else (nativeProfile, originProxy, unknown/missing) falls
    /// back to the per-identity store: fail toward isolation, never toward
    /// silent sharing.
    static func storeKind(for isolationMode: String?) -> StoreKind {
        isolationMode == "sharedSession" ? .shared : .perIdentity
    }

    init(channel: FlutterMethodChannel? = nil) {
        self.channel = channel
    }

    // MARK: - FlutterStreamHandler (platform -> Dart event writeback)

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        DiagnosticsLog.shared.log("eventSinkAttached")
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        DiagnosticsLog.shared.log("eventSinkDetached")
        return nil
    }

    func emit(_ payload: [String: Any]) {
        if eventSink == nil {
            // Events dropped while no Dart listener is attached are invisible
            // forever — exactly the kind of silent loss that leaves the Dart
            // loading flag stuck. Record them.
            DiagnosticsLog.shared.log("eventDroppedNoSink", fields: [
                "event": payload["event"] as? String ?? "?",
                "identityId": payload["identityId"] as? String ?? "",
            ])
        }
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(payload)
        }
    }

    // MARK: - Load watchdog

    /// Reverse lookup: which platform viewId currently owns [webView]. The
    /// NavigationDelegate only carries identityId; the live viewId can change
    /// when a view is re-keyed during reparent/reattach. Detached views stay
    /// in `webViews` until close, so this covers them too.
    func viewId(of webView: WKWebView) -> Int64? {
        webViews.first(where: { $0.value === webView })?.key
    }

    /// (Re)arm the load watchdog for a view. Called when a load is requested
    /// (loadUrl/reload/back/forward) and again at didStartProvisionalNavigation
    /// so a request that never reaches the web content process is also covered.
    func armLoadWatchdog(viewId: Int64, identityId: String, reason: String) {
        loadWatchdogs[viewId]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.loadWatchdogFired(viewId: viewId, identityId: identityId, reason: reason)
        }
        loadWatchdogs[viewId] = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.loadWatchdogInterval,
            execute: item
        )
    }

    func disarmLoadWatchdog(viewId: Int64) {
        loadWatchdogs.removeValue(forKey: viewId)?.cancel()
    }

    private func loadWatchdogFired(viewId: Int64, identityId: String, reason: String) {
        loadWatchdogs.removeValue(forKey: viewId)
        guard let webView = webViews[viewId] else { return }
        DiagnosticsLog.shared.log("loadWatchdogFired", fields: [
            "viewId": viewId,
            "identityId": identityId,
            "reason": reason,
            "isLoading": webView.isLoading,
            "estimatedProgress": webView.estimatedProgress,
            "url": webView.url?.absoluteString ?? "",
            "hasWindow": webView.window != nil,
            "hasSuperview": webView.superview != nil,
            "canGoBack": webView.canGoBack,
            "canGoForward": webView.canGoForward,
        ])
        // Unlatch the Dart-side loading flag. The navigation itself is NOT
        // cancelled — if it eventually completes, didFinish still reports.
        emit([
            "event": "loadFailed",
            "identityId": identityId,
            "url": webView.url?.absoluteString ?? "",
            "error": "watchdog-timeout (no navigation callback within \(Int(Self.loadWatchdogInterval))s)",
            "code": "WATCHDOG",
            "isLoading": webView.isLoading,
        ])
    }

    private func emitState(identityId: String, state: String) {
        emit(["event": "stateChanged", "identityId": identityId, "state": state])
    }

    private func observeUrl(of webView: WKWebView, viewId: Int64, identityId: String) {
        urlObservers[viewId] = webView.observe(\.url, options: [.new]) { [weak self, weak webView] _, _ in
            guard let self, let webView, let url = webView.url?.absoluteString,
                  !url.isEmpty else { return }
            self.emit([
                "event": "urlChanged",
                "identityId": identityId,
                "url": url,
                "canGoBack": webView.canGoBack,
                "canGoForward": webView.canGoForward,
            ])
        }
    }

    private func addRouteReporter(
        to configuration: WKWebViewConfiguration,
        viewId: Int64,
        identityId: String
    ) {
        let handlerName = "relayDeskRoute_\(viewId)"
        routeHandlerNames[viewId] = handlerName
        routeHandlerIdentities[handlerName] = identityId
        configuration.userContentController.add(self, name: handlerName)
        let source = """
        (() => {
          const reporter = window.webkit && window.webkit.messageHandlers
            ? window.webkit.messageHandlers['\(handlerName)']
            : null;
          if (!reporter) return;
          const report = () => reporter.postMessage(window.location.href);
          for (const method of ['pushState', 'replaceState']) {
            const original = history[method];
            History.prototype[method] = function (...args) {
              const result = original.apply(this, args);
              setTimeout(report, 0);
              return result;
            };
          }
          addEventListener('popstate', report);
          addEventListener('hashchange', report);
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
    }

    private func addInAppFullscreenBridge(
        to configuration: WKWebViewConfiguration,
        viewId: Int64,
        identityId: String
    ) {
        let handlerName = "relayDeskFullscreen_\(viewId)"
        fullscreenHandlerIdentities[handlerName] = identityId
        let source = """
        (() => {
          const handler = window.webkit && window.webkit.messageHandlers
            ? window.webkit.messageHandlers['\(handlerName)']
            : null;
          if (!handler) return;
          const notify = action => handler.postMessage(action);
          let activeElement = null;
          let activeStyle = null;
          let activeDocumentStyle = null;
          let activeBodyStyle = null;
          const fullscreenClass = 'relay-desk-in-app-fullscreen';
          const enter = element => {
            if (activeElement) return;
            activeElement = element;
            activeStyle = element.getAttribute('style');
            activeDocumentStyle = document.documentElement.getAttribute('style');
            activeBodyStyle = document.body ? document.body.getAttribute('style') : null;
            element.classList.add(fullscreenClass);
            element.style.setProperty('position', 'fixed', 'important');
            element.style.setProperty('inset', '0', 'important');
            element.style.setProperty('width', '100vw', 'important');
            element.style.setProperty('height', '100vh', 'important');
            element.style.setProperty('max-width', 'none', 'important');
            element.style.setProperty('max-height', 'none', 'important');
            element.style.setProperty('margin', '0', 'important');
            element.style.setProperty('transform', 'none', 'important');
            element.style.setProperty('z-index', '2147483647', 'important');
            element.style.setProperty('background-color', 'black', 'important');
            document.documentElement.style.setProperty('overflow', 'hidden', 'important');
            if (document.body) document.body.style.setProperty('overflow', 'hidden', 'important');
            notify('enter');
            document.dispatchEvent(new Event('fullscreenchange'));
          };
          const exit = () => {
            if (!activeElement) return;
            const element = activeElement;
            if (activeStyle === null) element.removeAttribute('style');
            else element.setAttribute('style', activeStyle);
            if (activeDocumentStyle === null) document.documentElement.removeAttribute('style');
            else document.documentElement.setAttribute('style', activeDocumentStyle);
            if (document.body) {
              if (activeBodyStyle === null) document.body.removeAttribute('style');
              else document.body.setAttribute('style', activeBodyStyle);
            }
            element.classList.remove(fullscreenClass);
            activeElement = null;
            activeStyle = null;
            notify('exit');
            document.dispatchEvent(new Event('fullscreenchange'));
          };
          const bindVideo = video => {
            if (video.dataset.relayDeskFullscreenBound) return;
            video.dataset.relayDeskFullscreenBound = '1';
            video.addEventListener('webkitbeginfullscreen', () => {
              // Native macOS video controls bypass requestFullscreen(). Move
              // that request back into the page viewport immediately.
              try { video.webkitExitFullscreen(); } catch (_) {}
              enter(video);
            }, true);
            video.addEventListener('webkitendfullscreen', () => {
              if (activeElement === video) exit();
            }, true);
          };
          const bindVideos = root => {
            if (!root || !root.querySelectorAll) return;
            root.querySelectorAll('video').forEach(bindVideo);
          };
          bindVideos(document);
          new MutationObserver(() => bindVideos(document)).observe(document, {
            childList: true,
            subtree: true
          });
          try {
            Object.defineProperty(document, 'fullscreenEnabled', {
              configurable: true,
              get: () => true
            });
            Object.defineProperty(document, 'fullscreenElement', {
              configurable: true,
              get: () => activeElement
            });
            Object.defineProperty(document, 'webkitFullscreenEnabled', {
              configurable: true,
              get: () => true
            });
            Object.defineProperty(document, 'webkitFullscreenElement', {
              configurable: true,
              get: () => activeElement
            });
          } catch (_) {}
          const requestInAppFullscreen = function () {
            enter(this);
            return Promise.resolve();
          };
          Element.prototype.requestFullscreen = requestInAppFullscreen;
          // Older Safari/WebKit player code uses both spellings.
          Element.prototype.webkitRequestFullscreen = requestInAppFullscreen;
          Element.prototype.webkitRequestFullScreen = requestInAppFullscreen;
          if (window.HTMLVideoElement) {
            HTMLVideoElement.prototype.webkitEnterFullscreen = function () {
              enter(this);
            };
          }
          document.exitFullscreen = function () {
            exit();
            return Promise.resolve();
          };
          document.webkitExitFullscreen = document.exitFullscreen;
          window.addEventListener('keydown', event => {
            if (event.key === 'Escape') exit();
          }, true);
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(self, name: handlerName)
    }

    private func removeRouteReporter(for viewId: Int64, webView: WKWebView) {
        guard let handlerName = routeHandlerNames.removeValue(forKey: viewId) else { return }
        routeHandlerIdentities.removeValue(forKey: handlerName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: handlerName)
    }

    /// Document-start script that emulates the JS touch-detection surface for
    /// mobile device presets: `navigator.maxTouchPoints` and
    /// `'ontouchstart' in window`. Property overrides only — no
    /// WKScriptMessageHandler, so it exposes no channel to business pages
    /// (same constraint as the route reporter). It cannot emulate
    /// `(pointer: coarse)` media queries or real touch events; sites that
    /// branch on UA or JS touch detection (the common mobile-serving cases)
    /// are covered.
    private func addTouchEmulationScript(to configuration: WKWebViewConfiguration) {
        let source = """
        (() => {
          try {
            Object.defineProperty(Navigator.prototype, 'maxTouchPoints', {
              configurable: true,
              get: () => 5
            });
            if (!('ontouchstart' in window)) {
              Object.defineProperty(window, 'ontouchstart', {
                configurable: true,
                writable: true,
                value: null
              });
            }
          } catch (_) {}
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
    }

    /// Installs the bounded in-page error buffer the automation `errors` op
    /// reads (issue #17). A `WKUserScript` at document start in every frame —
    /// same-origin iframes get their own buffer, which the drain script then
    /// reads frame-by-frame; cross-origin frames stay unreachable and are
    /// reported as such.
    ///
    /// The buffer lives inside the page document: it starts recording at
    /// injection time (honest `collectedAt` — no history before that exists),
    /// dies with the document on navigation or panel teardown, and a fresh
    /// `bufferId` per document marks the navigation batch. Capped at 200
    /// entries with an overflow counter; message/stack are truncated, and a
    /// rejection's non-Error `reason` is reduced to its type tag — arbitrary
    /// payloads are never serialized. Listeners only observe; they neither
    /// swallow errors nor alter propagation.
    private func addErrorCaptureScript(to configuration: WKWebViewConfiguration) {
        let source = """
        (function () {
          try {
            if (window.__relayErrors) return;
            var MAX = 200;
            var buf = {
              v: 1,
              bufferId: 'b' + Math.random().toString(36).slice(2) + '-' + Date.now(),
              startedAt: new Date().toISOString(),
              overflow: 0,
              entries: []
            };
            function clip(s, n) {
              if (s === null || s === undefined) return null;
              s = String(s);
              return s.length > n ? s.slice(0, n) + '\\u2026[' + (s.length - n) + ' chars]' : s;
            }
            function push(kind, message, source, line, col, stack) {
              if (buf.entries.length >= MAX) { buf.overflow++; return; }
              buf.entries.push({
                t: new Date().toISOString(), kind: kind,
                message: clip(message, 1024), source: clip(source, 512),
                line: line || null, col: col || null, stack: clip(stack, 4096)
              });
            }
            Object.defineProperty(window, '__relayErrors', {
              configurable: true, enumerable: false, writable: false, value: buf
            });
            window.addEventListener('error', function (e) {
              try {
                push('error', e.message, e.filename, e.lineno, e.colno,
                     e.error && e.error.stack);
              } catch (_) {}
            });
            window.addEventListener('unhandledrejection', function (e) {
              try {
                var r = e.reason, msg, stack = null;
                if (r instanceof Error) { msg = r.message; stack = r.stack; }
                else { msg = (typeof r === 'object' && r !== null)
                  ? Object.prototype.toString.call(r) : String(r); }
                push('unhandledrejection', msg, null, null, null, stack);
              } catch (_) {}
            });
          } catch (_) {}
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
    }

    private func removeInAppFullscreenBridge(for viewId: Int64, webView: WKWebView) {
        let handlerName = "relayDeskFullscreen_\(viewId)"
        fullscreenHandlerIdentities.removeValue(forKey: handlerName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: handlerName)
    }

    /// Registers the `relayDeskMeasure_<viewId>` message channel the
    /// measure-mode overlay uses to report its own teardown (Escape key).
    /// The overlay itself is installed lazily via `setMeasureMode` — this
    /// only wires the exit channel so `window.webkit.messageHandlers` has a
    /// valid entry whenever the script runs.
    private func addMeasureModeBridge(
        to configuration: WKWebViewConfiguration,
        viewId: Int64,
        identityId: String
    ) {
        let handlerName = "relayDeskMeasure_\(viewId)"
        measureHandlerIdentities[handlerName] = identityId
        configuration.userContentController.add(self, name: handlerName)
    }

    private func removeMeasureModeBridge(for viewId: Int64, webView: WKWebView) {
        let handlerName = "relayDeskMeasure_\(viewId)"
        measureHandlerIdentities.removeValue(forKey: handlerName)
        measureModeViewIds.remove(viewId)
        measureModeRulers.removeValue(forKey: viewId)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: handlerName)
    }

    /// The in-page measure overlay (element highlight + W×H badge + viewport
    /// rulers), installed/removed via evaluateJavaScript. Configuration is
    /// read from `window.__relayMeasureCfg` (enabled, handler) set by the
    /// caller — keeping the body free of interpolation so it can be shared
    /// between the toggle and the didFinish re-arm paths.
    ///
    /// Every overlay style carries `!important` because pages apply global
    /// CSS (e.g. `canvas { width: ... !important }`) that otherwise resizes
    /// our ruler canvases; inline `!important` wins over author `!important`.
    private static let measureOverlayScript = """
    (() => {
      const K = '__relayDeskMeasure';
      const cfg = window.__relayMeasureCfg || {};
      if (window[K]) { try { window[K].destroy(); } catch (e) {} window[K] = null; }
      if (!cfg.enabled) return { active: false };
      const doc = document;
      const R = 20, accent = '#2f80ed';
      const I = ' !important';
      const mk = (t, c) => { const el = doc.createElement(t); el.style.cssText = c; return el; };
      const root = mk('div', 'position:fixed' + I + ';inset:0' + I + ';z-index:2147483646' + I + ';pointer-events:none' + I + ';');
      root.id = '__relay_measure';
      const hl = mk('div', 'position:fixed' + I + ';display:none' + I + ';border:1.5px solid ' + accent + I + ';background:rgba(47,128,237,.13)' + I + ';box-sizing:border-box' + I + ';');
      const badge = mk('div', 'position:fixed' + I + ';display:none' + I + ';background:' + accent + I + ';color:#fff' + I + ';font:11px/1.45 -apple-system,Menlo,monospace' + I + ';padding:3px 7px' + I + ';border-radius:3px' + I + ';white-space:nowrap' + I + ';');
      root.append(hl, badge);
      // In-page rulers only when the view is detached — the embedded panel
      // draws its rulers on the Flutter side instead, keeping page UI clear.
      const showChrome = cfg.rulers === true;
      let rulers = null, vp = null, corner = null;
      if (showChrome) {
        rulers = doc.createElement('canvas');
        rulers.style.cssText = 'position:fixed' + I + ';left:0' + I + ';top:0' + I + ';pointer-events:none' + I + ';';
        vp = mk('div', 'position:fixed' + I + ';left:' + (R + 6) + 'px' + I + ';top:' + (R + 6) + 'px' + I + ';background:rgba(0,0,0,.72)' + I + ';color:#fff' + I + ';font:11px/1.4 -apple-system,Menlo,monospace' + I + ';padding:3px 7px' + I + ';border-radius:3px' + I + ';');
        corner = mk('div', 'position:fixed' + I + ';left:0' + I + ';top:0' + I + ';width:' + R + 'px' + I + ';height:' + R + 'px' + I + ';background:#1b1b1f' + I + ';');
        root.append(rulers, corner, vp);
      }
      (doc.documentElement || doc.body).appendChild(root);
      const draw = () => {
        if (!rulers) return;
        // One full-viewport canvas draws both rulers — explicit pixel sizes
        // with `!important`, so page-level `canvas` rules cannot squeeze it.
        const dpr = window.devicePixelRatio || 1;
        const w = innerWidth, h = innerHeight;
        rulers.style.setProperty('width', w + 'px', 'important');
        rulers.style.setProperty('height', h + 'px', 'important');
        rulers.width = Math.round(w * dpr);
        rulers.height = Math.round(h * dpr);
        const g = rulers.getContext('2d');
        g.scale(dpr, dpr);
        g.clearRect(0, 0, w, h);
        g.fillStyle = '#1b1b1f';
        g.fillRect(0, 0, w, R);
        g.fillRect(0, 0, R, h);
        g.fillStyle = '#9a9aa0';
        g.strokeStyle = '#55555c';
        g.font = '9px Menlo, monospace';
        g.lineWidth = 1;
        for (let x = 0; x <= w; x += 10) {
          const major = x % 100 === 0, mid = x % 50 === 0;
          const tick = major ? 11 : (mid ? 7 : 4);
          g.beginPath();
          g.moveTo(x + .5, R); g.lineTo(x + .5, R - tick);
          if (major) g.fillText(String(x), x + 3, 9);
          g.stroke();
        }
        for (let y = 0; y <= h; y += 10) {
          const major = y % 100 === 0, mid = y % 50 === 0;
          const tick = major ? 11 : (mid ? 7 : 4);
          g.beginPath();
          g.moveTo(R, y + .5); g.lineTo(R - tick, y + .5);
          if (major) { g.save(); g.translate(9, y + 2); g.rotate(-Math.PI / 2); g.fillText(String(y), 0, 0); g.restore(); }
          g.stroke();
        }
        vp.textContent = w + 'px \\u00d7 ' + h + 'px';
      };
      let current = null;
      const sel = (el) => {
        let s = String(el.tagName || '').toLowerCase();
        if (el.id) s += '#' + el.id;
        const cn = typeof el.className === 'string' ? el.className : (el.className && el.className.baseVal) || '';
        const cls = cn.split(' ').filter(Boolean).slice(0, 3);
        if (cls.length) s += '.' + cls.join('.');
        return s.length > 48 ? s.slice(0, 48) : s;
      };
      const set = (el, k, v) => el.style.setProperty(k, v, 'important');
      // Badge clearance always respects the 20px ruler strip — embedded
      // mode has the Flutter-side rulers covering that same edge band.
      const edge = R;
      const place = (r, el) => {
        set(hl, 'display', 'block');
        set(hl, 'left', r.left + 'px'); set(hl, 'top', r.top + 'px');
        set(hl, 'width', r.width + 'px'); set(hl, 'height', r.height + 'px');
        set(badge, 'display', 'block');
        badge.textContent = sel(el) + '  ' + Math.round(r.width) + ' \\u00d7 ' + Math.round(r.height);
        const bw = badge.offsetWidth, bh = badge.offsetHeight;
        let bx = r.left, by = r.top - bh - 2;
        if (by < edge + 4) by = r.bottom + 2;
        if (bx + bw > innerWidth - 4) bx = innerWidth - bw - 4;
        if (bx < edge + 4) bx = edge + 4;
        set(badge, 'left', bx + 'px'); set(badge, 'top', by + 'px');
      };
      const hide = () => {
        set(hl, 'display', 'none'); set(badge, 'display', 'none');
      };
      const onMove = (e) => {
        const el = doc.elementFromPoint(e.clientX, e.clientY);
        if (!el || root.contains(el)) { hide(); current = null; return; }
        current = el;
        place(el.getBoundingClientRect(), el);
      };
      const onRefresh = () => {
        draw();
        if (current && doc.contains(current)) place(current.getBoundingClientRect(), current);
      };
      const api = {
        active: true,
        destroy() {
          if (!api.active) return;
          api.active = false;
          doc.removeEventListener('mousemove', onMove, true);
          doc.removeEventListener('keydown', onKey, true);
          doc.removeEventListener('click', onClick, true);
          window.removeEventListener('resize', onRefresh);
          doc.removeEventListener('scroll', onRefresh, true);
          root.remove();
          window[K] = null;
          try { window.webkit.messageHandlers[cfg.handler].postMessage('exit'); } catch (e) {}
        },
      };
      const onKey = (e) => { if (e.key === 'Escape') api.destroy(); };
      const onClick = (e) => {
        // While measuring, a click selects — it must not navigate.
        if (e.button === 0) { e.preventDefault(); e.stopPropagation(); }
      };
      doc.addEventListener('mousemove', onMove, true);
      doc.addEventListener('keydown', onKey, true);
      doc.addEventListener('click', onClick, true);
      window.addEventListener('resize', onRefresh);
      doc.addEventListener('scroll', onRefresh, true);
      draw();
      window[K] = api;
      return { active: true };
    })()
    """

    private func measureModeConfigScript(enabled: Bool, viewId: Int64, inPageRulers: Bool = false) -> String {
        "window.__relayMeasureCfg={enabled:\(enabled ? "true" : "false"),handler:'relayDeskMeasure_\(viewId)',rulers:\(inPageRulers ? "true" : "false")};"
    }

    /// Installs or removes the measure overlay and keeps bookkeeping in
    /// sync: armed views are tracked in `measureModeViewIds` (didFinish
    /// re-arms after navigations) and the applied state is reported to Dart
    /// via `measureModeChanged` so UI state follows the platform, not the
    /// button press.
    private func setMeasureMode(
        viewId: Int64,
        webView: WKWebView,
        enabled: Bool,
        inPageRulers: Bool,
        result: @escaping FlutterResult
    ) {
        webView.evaluateJavaScript(
            measureModeConfigScript(enabled: enabled, viewId: viewId, inPageRulers: inPageRulers) + Self.measureOverlayScript
        ) { [weak self] value, error in
            if let error {
                result(FlutterError(code: "js_error", message: error.localizedDescription, details: nil))
                return
            }
            let active = (value as? [String: Any])?["active"] as? Bool ?? false
            if let self {
                if active {
                    self.measureModeViewIds.insert(viewId)
                    self.measureModeRulers[viewId] = inPageRulers
                } else {
                    self.measureModeViewIds.remove(viewId)
                    self.measureModeRulers.removeValue(forKey: viewId)
                }
                if let identityId = self.identityIdFor(viewId: viewId) {
                    self.emit([
                        "event": "measureModeChanged",
                        "identityId": identityId,
                        "enabled": active,
                    ])
                }
            }
            result(active)
        }
    }

    /// Re-installs the overlay after a navigation for views whose measure
    /// mode is still armed (the page context — and our injected DOM — is
    /// reset by every full load).
    func rearmMeasureMode(viewId: Int64, webView: WKWebView) {
        guard measureModeViewIds.contains(viewId) else { return }
        webView.evaluateJavaScript(
            measureModeConfigScript(
                enabled: true,
                viewId: viewId,
                inPageRulers: measureModeRulers[viewId] ?? false
            ) + Self.measureOverlayScript,
            completionHandler: nil
        )
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let identityId = fullscreenHandlerIdentities[message.name],
           let action = message.body as? String {
            // The page element is made fullscreen by the injected DOM bridge.
            // Do not move the WKWebView itself; that would fullscreen the page
            // shell and leave site-specific sidebars visible.
            emit([
                "event": "fullscreenChanged",
                "identityId": identityId,
                "isFullscreen": action == "enter",
            ])
            return
        }
        if let identityId = measureHandlerIdentities[message.name] {
            // The page overlay tore itself down (Escape) — sync Dart's
            // button state and stop re-arming on later navigations.
            if let viewId = viewIdByIdentity[identityId] {
                measureModeViewIds.remove(viewId)
            }
            emit([
                "event": "measureModeChanged",
                "identityId": identityId,
                "enabled": false,
            ])
            return
        }
        guard let identityId = routeHandlerIdentities[message.name],
              let url = message.body as? String,
              !url.isEmpty else { return }
        emit([
            "event": "urlChanged",
            "identityId": identityId,
            "url": url,
        ])
    }

    // MARK: - Method channel

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "probe":
            var available = false
            if #available(macOS 14.0, *) {
                available = true
            }
            var devtoolsAvailable = false
            #if DEBUG
            devtoolsAvailable = available
            #endif
            result([
                "nativeProfiles": available,
                "devtools": devtoolsAvailable,
                // WKWebView.customUserAgent is set per-view from creationParams.
                "customUserAgent": true,
                // No CDP-style Emulation.setDeviceMetricsOverride exists on
                // WKWebView for macOS; mobile viewport emulation is done by
                // sizing the view/window (Dart-side clamp + detached window
                // content size), which is honest, not an inner-viewport
                // override. Report false rather than claim the API.
                "deviceMetricsOverride": false,
                // Implemented as a document-start user script overriding
                // navigator.maxTouchPoints / window.ontouchstart (the JS
                // detection surface); (pointer: coarse) media queries and
                // real touch input are NOT emulated.
                "touchEmulation": true,
                "networkThrottling": false,
                "clearProfileData": true,
                "macosVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            ] as [String: Any])
        case "evaluateJs":
            let viewId = (args["viewId"] as? NSNumber)?.int64Value ?? 0
            let js = args["js"] as? String ?? ""
            guard let webView = webViews[viewId] else {
                result(FlutterError(code: "no_webview", message: "viewId \(viewId)", details: nil))
                return
            }
            webView.evaluateJavaScript(js) { value, error in
                if let error = error {
                    result(FlutterError(code: "js_error", message: error.localizedDescription, details: nil))
                } else {
                    result(value)
                }
            }
        case "callAsync":
            // Uses WKWebView.callAsyncJavaScript (macOS 11+) to await promises.
            // Required for IndexedDB / Cache Storage / Service Worker operations.
            let viewId = (args["viewId"] as? NSNumber)?.int64Value ?? 0
            let body = args["body"] as? String ?? ""
            let jsArgs = args["arguments"] as? [String: Any] ?? [:]
            guard let webView = webViews[viewId] else {
                result(FlutterError(code: "no_webview", message: "viewId \(viewId)", details: nil))
                return
            }
            if #available(macOS 11.0, *) {
                webView.callAsyncJavaScript(body, arguments: jsArgs, in: nil, in: .page) { res in
                    switch res {
                    case .success(let value):
                        result(value)
                    case .failure(let error):
                        result(FlutterError(code: "async_js_error", message: error.localizedDescription, details: nil))
                    }
                }
            } else {
                result(FlutterError(code: "unsupported", message: "callAsyncJavaScript requires macOS 11+", details: nil))
            }
        case "appendLog":
            // Dart-side breadcrumbs (navigate/reload/stop calls, received
            // events) are appended to the same diagnostics file so one
            // timeline covers both sides of the channel.
            let event = args["event"] as? String ?? "dart"
            var fields = args
            fields.removeValue(forKey: "event")
            DiagnosticsLog.shared.log("dart.\(event)", fields: fields)
            result(nil)
        case "logPath":
            result(DiagnosticsLog.shared.path)
        case "loadUrl":
            let viewId = (args["viewId"] as? NSNumber)?.int64Value ?? 0
            let urlString = args["url"] as? String ?? ""
            let identityId = identityIdFor(viewId: viewId)
            guard let webView = webViews[viewId],
                  let url = URL(string: urlString) else {
                DiagnosticsLog.shared.log("loadUrlRejected", fields: [
                    "viewId": viewId,
                    "identityId": identityId ?? "",
                    "url": urlString,
                    "hasView": webViews[viewId] != nil,
                ])
                // Emit loadFailed too: the Dart adapter treats the returned
                // error as a channel failure and unlatches `loading`, but the
                // native event also covers callers that ignore the result.
                if let identityId {
                    emit([
                        "event": "loadFailed",
                        "identityId": identityId,
                        "url": urlString,
                        "error": "no live webview for viewId \(viewId)",
                        "code": "NO_WEBVIEW",
                    ])
                }
                result(FlutterError(code: "bad_args", message: "loadUrl", details: nil))
                return
            }
            DiagnosticsLog.shared.log("loadUrl", fields: [
                "viewId": viewId,
                "identityId": identityId ?? "",
                "url": urlString,
            ])
            armLoadWatchdog(viewId: viewId, identityId: identityId ?? "", reason: "loadUrl")
            webView.load(URLRequest(url: url))
            result(nil)
        case "goBack":
            result(tryNavigate(args, action: "goBack") { $0.goBack() })
        case "goForward":
            result(tryNavigate(args, action: "goForward") { $0.goForward() })
        case "stopLoading":
            result(tryNavigate(args, action: "stopLoading") { $0.stopLoading() })
        case "reload":
            result(tryNavigate(args, action: "reload") { $0.reload() })
        case "canGoBack":
            result(webViews[(args["viewId"] as? NSNumber)?.int64Value ?? 0]?.canGoBack ?? false)
        case "canGoForward":
            result(webViews[(args["viewId"] as? NSNumber)?.int64Value ?? 0]?.canGoForward ?? false)
        case "currentUrl":
            result(webViews[(args["viewId"] as? NSNumber)?.int64Value ?? 0]?.url?.absoluteString ?? "")
        case "openDevTools":
            // WKWebView has no programmatic Chromium-style DevTools window. On
            // macOS, the Web Inspector is enabled via developerExtrasEnabled
            // (set in registerWebView under DEBUG) and opened by the user via
            // right-click -> Inspect Element. We report the capability status
            // so the UI can show an accurate DevTools state per rewrite-plan.
            let viewId = (args["viewId"] as? NSNumber)?.int64Value ?? 0
            guard let webView = webViews[viewId] else {
                result(FlutterError(code: "no_webview", message: "viewId \(viewId)", details: nil))
                return
            }
            let enabled: Bool
            #if DEBUG
            enabled = (webView.configuration.preferences.value(forKey: "developerExtrasEnabled") as? Bool) ?? false
            #else
            enabled = false
            #endif
            result([
                "opened": false,
                "available": enabled,
                "howToOpen": "Right-click the WebView and choose Inspect Element (Safari Web Inspector).",
            ] as [String: Any])
        case "toggleMute":
            let viewId = (args["viewId"] as? NSNumber)?.int64Value ?? 0
            guard let webView = webViews[viewId] else {
                result(FlutterError(code: "no_webview", message: "viewId \(viewId)", details: nil))
                return
            }
            webView.evaluateJavaScript("""
            (() => {
              const media = Array.from(document.querySelectorAll('video, audio'));
              const shouldMute = media.some(element => !element.muted);
              for (const element of media) element.muted = shouldMute;
              return shouldMute;
            })()
            """) { value, error in
                if let error = error {
                    result(FlutterError(code: "js_error", message: error.localizedDescription, details: nil))
                } else {
                    result(value)
                }
            }
        case "setMeasureMode":
            let viewId = (args["viewId"] as? NSNumber)?.int64Value ?? 0
            guard let webView = webViews[viewId] else {
                result(FlutterError(code: "no_webview", message: "viewId \(viewId)", details: nil))
                return
            }
            setMeasureMode(
                viewId: viewId,
                webView: webView,
                enabled: args["enabled"] as? Bool ?? false,
                inPageRulers: args["inPageRulers"] as? Bool ?? false,
                result: result
            )
        case "toggleInAppFullscreen":
            let identityId = args["identityId"] as? String ?? ""
            toggleInAppFullscreen(identityId: identityId, result: result)
        case "clearIdentityData":
            let identityId = args["identityId"] as? String ?? ""
            clearIdentityData(identityId: identityId, result: result)
        case "dataStoreExists":
            let identityId = args["identityId"] as? String ?? ""
            result(checkDataStoreExists(identityId: identityId))
        case "dataStorePath":
            let identityId = args["identityId"] as? String ?? ""
            result(dataStorePath(identityId: identityId))
        case "storeKind":
            // "shared" | "perIdentity" | "none" — which store kind the
            // identity's most recent view was created with. Evidence harness
            // only; identityStoreKinds is written at view creation and always
            // reflects the newest view for the identity.
            let identityId = args["identityId"] as? String ?? ""
            result(identityStoreKinds[identityId]?.rawValue ?? "none")
        case "setCookie":
            // Evidence harness: write a cookie directly into the identity's
            // live WKWebsiteDataStore so isolation/sharing can be verified
            // without depending on page scripts.
            let identityId = args["identityId"] as? String ?? ""
            let name = args["name"] as? String ?? ""
            let value = args["value"] as? String ?? ""
            let domain = args["domain"] as? String ?? "127.0.0.1"
            let expires = (args["expiresSeconds"] as? NSNumber)?.doubleValue
            setCookie(identityId: identityId, name: name, value: value, domain: domain, expiresSeconds: expires, result: result)
        case "deleteCookie":
            let identityId = args["identityId"] as? String ?? ""
            let name = args["name"] as? String ?? ""
            let domain = args["domain"] as? String ?? "127.0.0.1"
            deleteCookie(identityId: identityId, name: name, domain: domain, result: result)
        case "documentsDir":
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            result(docsDir?.path)
        case "getCookieString":
            let viewId = (args["viewId"] as? NSNumber)?.int64Value ?? 0
            guard let webView = webViews[viewId] else {
                result(FlutterError(code: "no_webview", message: "viewId \(viewId)", details: nil))
                return
            }
            let store = webView.configuration.websiteDataStore
            store.httpCookieStore.getAllCookies { cookies in
                let cookieString = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                result(cookieString)
            }
        case "getProcessInfo":
            // Report app RSS and webview count for resource evidence.
            var info = mach_task_basic_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
            let kerr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            var rss: UInt64 = 0
            if kerr == KERN_SUCCESS {
                rss = info.resident_size
            }
            result([
                "rssBytes": rss,
                "webviewCount": webViews.count,
                "dataStoreCount": dataStores.count,
            ] as [String: Any])
        case "windowInventory":
            // handle() is invoked on the main thread, so AppKit window and
            // responder state can be sampled directly here. Pure read: no
            // window is activated or focused and no web content is touched.
            result(windowInventory())
        case "takeSnapshot":
            takeSnapshot(args, result: result)
        case "sampleMedia":
            sampleMedia(args, result: result)
        case "drainJsErrors":
            drainJsErrors(args, result: result)
        case "setBounds":
            // The Flutter AppKitView/PlatformView container is already placed
            // by Flutter from Positioned(left/top/width/height) in Canvas
            // coordinates. The incoming x/y describe that outer Canvas
            // position; applying them to the child WKWebView inside the
            // container double-translates the content and leaves the page
            // offset by the panel's prior/Canvas coordinates after a drag or
            // resize. The child WebView must simply fill its container, with
            // its origin at (0,0) and size matching the container's local
            // bounds (which Flutter manages). Width/height from the call are
            // not used to force a conflicting outer position.
            let viewId = (args["viewId"] as? NSNumber)?.int64Value ?? 0
            guard let webView = webViews[viewId] else {
                result(FlutterError(code: "no_webview", message: "viewId \(viewId)", details: nil))
                return
            }
            let container = webView.superview
            let containerBounds = container?.bounds ?? .zero
            // `custom` preset: keep the remembered viewport tracking the live
            // view surface so `detach` opens at the panel's current size.
            if let identityId = identityIdFor(viewId: viewId),
               identityViewportFollows.contains(identityId),
               containerBounds.width > 0, containerBounds.height > 0 {
                identityViewports[identityId] = containerBounds.size
            }
            // Child fills the container; origin is local (0,0).
            webView.frame = CGRect(origin: .zero, size: containerBounds.size)
            // Ensure the WKWebView's internal scrollview re-lays-out to the
            // new viewport immediately (avoids stale offset until the next
            // AppKit layout pass).
            container?.needsLayout = true
            container?.layoutSubtreeIfNeeded()
            // Report the local child frame plus the requested Canvas rect for
            // inspection. The child origin is always (0,0); the requested
            // x/y/width/height are echoed back so callers can verify the
            // Canvas coordinate stream is intact.
            let reqX = (args["x"] as? NSNumber)?.doubleValue ?? 0
            let reqY = (args["y"] as? NSNumber)?.doubleValue ?? 0
            let reqWidth = (args["width"] as? NSNumber)?.doubleValue ?? 0
            let reqHeight = (args["height"] as? NSNumber)?.doubleValue ?? 0
            result([
                "x": webView.frame.origin.x,
                "y": webView.frame.origin.y,
                "width": webView.frame.width,
                "height": webView.frame.height,
                "superviewWidth": containerBounds.width,
                "superviewHeight": containerBounds.height,
                "requestedX": reqX,
                "requestedY": reqY,
                "requestedWidth": reqWidth,
                "requestedHeight": reqHeight,
            ] as [String: Any])
        case "getBounds":
            let viewId = (args["viewId"] as? NSNumber)?.int64Value ?? 0
            guard let webView = webViews[viewId] else {
                result(FlutterError(code: "no_webview", message: "viewId \(viewId)", details: nil))
                return
            }
            result([
                "x": webView.frame.origin.x,
                "y": webView.frame.origin.y,
                "width": webView.frame.width,
                "height": webView.frame.height,
            ] as [String: Any])
        case "detach":
            let identityId = args["identityId"] as? String ?? ""
            detach(identityId: identityId, result: result)
        case "attach":
            let identityId = args["identityId"] as? String ?? ""
            attach(identityId: identityId, result: result)
        case "close":
            let viewId = (args["viewId"] as? NSNumber)?.int64Value ?? 0
            let identityId = args["identityId"] as? String ?? ""
            close(viewId: viewId, identityId: identityId, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func identityIdFor(viewId: Int64) -> String? {
        viewIdByIdentity.first(where: { $0.value == viewId })?.key
    }

    /// One-shot inventory of AppKit windows and this plugin's live webviews
    /// for the read-only automation transport. Everything is sampled from
    /// NSApp and the plugin's own maps on the main thread — no WebKit calls.
    private func windowInventory() -> [String: Any] {
        let appActive = NSApp.isActive
        var windows: [[String: Any]] = []
        for window in NSApp.windows {
            let frame = window.frame
            windows.append([
                "windowId": window.windowNumber,
                "title": window.title,
                "isKey": window.isKeyWindow,
                "isMain": window.isMainWindow,
                "isVisible": window.isVisible,
                "isMiniaturized": window.isMiniaturized,
                "bounds": [
                    "x": frame.origin.x,
                    "y": frame.origin.y,
                    "width": frame.size.width,
                    "height": frame.size.height,
                ],
            ])
        }
        var views: [[String: Any]] = []
        for (viewId, webView) in webViews {
            let window = webView.window
            // A webview owns keyboard focus only while the app is active,
            // its window is key, and the window's first responder is the
            // webView or a descendant — Flutter chrome (address bar,
            // sidebar) holding the responder reports no focused view.
            var hasKeyboardFocus = false
            if appActive,
               let window,
               window.isKeyWindow,
               let responder = window.firstResponder as? NSView {
                hasKeyboardFocus = responder === webView || responder.isDescendant(of: webView)
            }
            views.append([
                "viewId": viewId,
                "identityId": identityIdFor(viewId: viewId) ?? "",
                "windowId": orNull(window?.windowNumber),
                "hasKeyboardFocus": hasKeyboardFocus,
            ])
        }
        // currentWindowId is the key window only while the app is active.
        // AppKit can keep an isKey window while inactive; an inactive app
        // reports null rather than falling back to mainWindow.
        return [
            "currentWindowId": appActive ? orNull(NSApp.keyWindow?.windowNumber) : NSNull(),
            "mainWindowId": orNull(NSApp.mainWindow?.windowNumber),
            "windows": windows,
            "views": views,
        ]
    }

    /// Read-only viewport snapshot for the automation transport.
    ///
    /// The request binds to (viewId, expectedIdentityId, the live WKWebView
    /// instance, the window it sits in, and both navigation generations —
    /// provisional starts and commits). takeSnapshot is asynchronous, so all
    /// factors are re-verified when the capture completes: a
    /// destroyed/replaced view, a remapped identity, a closed window, or a
    /// navigation started — or an already in-flight one committed —
    /// mid-capture fails `target_changed` rather than returning pixels under
    /// the originally recorded target. Comparing the finished webView.url is
    /// deliberately not the check: a same-URL reload changes the document
    /// without touching the URL. A nil `webView.window` likewise fails.
    ///
    /// The capture rect is the view's own bounds: exactly the page viewport
    /// of that one WKWebView — no window chrome, no neighbouring panels.
    /// The bounds are validated by `SnapshotPolicy.validate` before any
    /// native pixel allocation: the viewport must be finite and positive,
    /// and scaled by the window's backing scale it must stay within the
    /// per-side and total pixel budgets — oversized targets fail
    /// `snapshot_too_large` instead of driving unbounded TIFF/bitmap/PNG
    /// allocations. The encoded PNG is re-checked against the byte budget
    /// for the same reason.
    ///
    /// The request completes exactly once via `SnapshotCompletionGate`:
    /// either the capture finishes, or `SnapshotPolicy.deadline` elapses and
    /// a `snapshot_timeout` error is delivered. A WebKit callback that
    /// arrives late fails the gate claim and returns before touching the
    /// image — no double result, no post-timeout transcoding, and the
    /// transport's per-target busy marker is freed so the target stays
    /// queryable.
    private func takeSnapshot(_ args: [String: Any], result: @escaping FlutterResult) {
        guard let viewId = (args["viewId"] as? NSNumber)?.int64Value,
              let expectedIdentityId = args["expectedIdentityId"] as? String else {
            result(FlutterError(code: "invalid_argument", message: "viewId and expectedIdentityId are required", details: nil))
            return
        }
        guard let webView = webViews[viewId],
              identityIdFor(viewId: viewId) == expectedIdentityId else {
            result(FlutterError(code: "target_changed", message: "Target is not bound to a live web view", details: nil))
            return
        }
        guard let initialWindowNumber = webView.window?.windowNumber else {
            result(FlutterError(code: "target_changed", message: "Target view is not in a window", details: nil))
            return
        }
        let bounds = webView.bounds
        let scale = webView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        switch SnapshotPolicy.validate(bounds: bounds.size, scale: scale) {
        case .notMeasurable:
            result(FlutterError(code: "snapshot_failed", message: "Target viewport is not measurable", details: nil))
            return
        case .tooLarge(let pixelsWide, let pixelsHigh):
            result(FlutterError(
                code: "snapshot_too_large",
                message: "Viewport is too large to snapshot (\(SnapshotPolicy.describePixels(pixelsWide, pixelsHigh)) px)",
                details: nil,
            ))
            return
        case .ok:
            break
        }
        let binding = SnapshotTargetBinding(
            viewId: viewId,
            identityId: expectedIdentityId,
            instanceId: ObjectIdentifier(webView),
            provisionalGeneration: navigationGenerations[viewId] ?? 0,
            commitGeneration: navigationCommitGenerations[viewId] ?? 0,
            windowNumber: initialWindowNumber,
        )
        // All channel calls on this plugin run on the main thread, so the
        // gate is a plain flag on one serial context — the deadline and the
        // WebKit callback can never interleave.
        let gate = SnapshotCompletionGate()
        DispatchQueue.main.asyncAfter(deadline: .now() + SnapshotPolicy.deadline) {
            if gate.claim() {
                result(FlutterError(
                    code: "snapshot_timeout",
                    message: "Snapshot did not complete within \(Int(SnapshotPolicy.deadline)) s",
                    details: nil,
                ))
            }
        }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = bounds
        webView.takeSnapshot(with: configuration) { [weak self, weak webView] image, error in
            // A callback arriving after the deadline returns here — before
            // any binding re-check, transcoding, or success result.
            guard gate.claim() else { return }
            guard let self else { return }
            if let error {
                result(FlutterError(code: "snapshot_failed", message: error.localizedDescription, details: nil))
                return
            }
            guard let image else {
                result(FlutterError(code: "snapshot_failed", message: "Snapshot produced no image", details: nil))
                return
            }
            let liveView = self.webViews[viewId]
            guard binding.isStillBound(
                liveInstance: liveView,
                liveIdentityId: self.identityIdFor(viewId: viewId),
                liveProvisionalGeneration: self.navigationGenerations[viewId] ?? 0,
                liveCommitGeneration: self.navigationCommitGenerations[viewId] ?? 0,
                liveWindowNumber: liveView?.window?.windowNumber
            ), let webView else {
                result(FlutterError(code: "target_changed", message: "Target changed during capture", details: nil))
                return
            }
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                result(FlutterError(code: "snapshot_failed", message: "PNG encoding failed", details: nil))
                return
            }
            guard !SnapshotPolicy.exceedsPngLimit(png.count) else {
                result(FlutterError(code: "snapshot_too_large", message: "PNG payload exceeds the byte budget", details: nil))
                return
            }
            result([
                "png": FlutterStandardTypedData(bytes: png),
                "width": bitmap.pixelsWide,
                "height": bitmap.pixelsHigh,
                "url": webView.url?.absoluteString as Any,
                "windowId": self.orNull(webView.window?.windowNumber),
            ])
        }
    }

    /// Fixed read-only probe evaluated inside the target page for `sampleMedia`.
    /// Walks `video`/`audio` elements in the main document plus every same-origin
    /// iframe reachable through `contentDocument`; a cross-origin or otherwise
    /// unreachable frame is listed as `reachable: false` — never probed across
    /// the boundary and never mistaken for "no media". `duration` that is NaN
    /// or non-finite (live streams) is reported as `duration: null` with a
    /// `durationKind` marker so JSON output never carries an invalid number.
    /// The caller cannot inject script: this literal is the only thing run.
    /// Budgets: 4 levels deep, 32 frames and 32 media elements per frame cap
    /// the work before the result is built — the walk stops touching nodes
    /// once spent (skipped counts come from collection lengths). URL fields
    /// are length-capped and opaque-scheme URLs stripped in-page, before
    /// serialization; a 200 KB total-byte budget then trims media entries
    /// from the tail. Anything cut is reported via `truncated`/
    /// `skippedFrames`/`depthLimitSkipped`/`mediaSkipped`/`mediaDropped`, so
    /// a truncated walk is never mistaken for "no media".
    /// Nested same-origin iframes are recursed into with hierarchical labels
    /// (`main`, `f0`, `f0.f1`); an unreachable frame at any depth is listed
    /// `reachable:false` and its own subtree is marked unexplored, never
    /// probed across the boundary.
    private static let mediaProbeScript = """
    (function () {
      var MAX_DEPTH = 4, MAX_FRAMES = 32, MAX_MEDIA = 32;
      var MAX_URL = 512, MAX_BYTES = 200000;
      var frames = [];
      var skippedFrames = 0, depthLimitSkipped = 0, mediaSkippedTotal = 0;
      // URL fields are bounded and stripped before they ever reach
      // JSON.stringify — a huge data: payload never allocates into the
      // result or the platform channel.
      function safeUrl(u) {
        if (!u) return null;
        u = String(u);
        if (/^(data|blob|javascript):/i.test(u)) return '<opaque-url>';
        return u.length > MAX_URL ? u.slice(0, MAX_URL) + '\u2026' : u;
      }
      function seekableRanges(m) {
        var ranges = [];
        try {
          var t = m.seekable;
          for (var i = 0; i < t.length && ranges.length < 8; i++) {
            ranges.push([t.start(i), t.end(i)]);
          }
        } catch (e) {}
        return ranges;
      }
      function mediaEntry(m, i) {
        var d = m.duration;
        var kind = 'unknown';
        var duration = null;
        if (typeof d === 'number' && !isNaN(d)) {
          if (isFinite(d)) { kind = 'finite'; duration = d; } else { kind = 'live'; }
        }
        return {
          index: i, tag: String(m.tagName || '').toLowerCase(),
          currentTime: m.currentTime, duration: duration, durationKind: kind,
          paused: m.paused, ended: m.ended, seeking: m.seeking,
          readyState: m.readyState, playbackRate: m.playbackRate,
          seekable: seekableRanges(m),
          error: m.error ? { code: m.error.code } : null
        };
      }
      function collect(doc, label, url, depth) {
        if (frames.length >= MAX_FRAMES) { skippedFrames++; return; }
        var frame = { index: frames.length, label: label, url: safeUrl(url),
                      depth: depth, reachable: true, media: [], mediaSkipped: 0 };
        var els = doc.querySelectorAll('video, audio');
        // Budget-bounded: only the first MAX_MEDIA elements are touched;
        // the skipped count is computed from the collection length.
        var take = Math.min(els.length, MAX_MEDIA);
        for (var i = 0; i < take; i++) frame.media.push(mediaEntry(els[i], i));
        if (els.length > take) {
          frame.mediaSkipped = els.length - take;
          mediaSkippedTotal += frame.mediaSkipped;
        }
        frame.mediaCount = els.length;
        frames.push(frame);
        var iframes = doc.querySelectorAll('iframe');
        if (depth >= MAX_DEPTH) {
          // Subtrees beyond the depth budget are reported as unexplored,
          // not as absent.
          if (iframes.length) { depthLimitSkipped += iframes.length; }
          return;
        }
        for (var k = 0; k < iframes.length; k++) {
          // Stop before touching the remaining iframe elements — the
          // budget is spent, so skipped count comes from list length.
          if (frames.length >= MAX_FRAMES) {
            skippedFrames += iframes.length - k;
            break;
          }
          var el = iframes[k];
          var childLabel = label === 'main' ? 'f' + k : label + '.f' + k;
          try {
            var idoc = el.contentDocument ||
                       (el.contentWindow && el.contentWindow.document);
            if (!idoc) { throw new Error('unavailable'); }
            collect(idoc, childLabel,
                    (idoc.location && idoc.location.href) || el.src || null,
                    depth + 1);
          } catch (e) {
            if (frames.length >= MAX_FRAMES) { skippedFrames++; continue; }
            frames.push({ index: frames.length, label: childLabel,
                          url: safeUrl(el.src), depth: depth + 1,
                          reachable: false, reason: 'unavailable',
                          media: [], mediaCount: 0 });
          }
        }
      }
      collect(document, 'main', location.href, 0);
      var result = {
        frames: frames,
        truncated: skippedFrames > 0 || depthLimitSkipped > 0 ||
                   mediaSkippedTotal > 0,
        skippedFrames: skippedFrames,
        depthLimitSkipped: depthLimitSkipped,
        mediaSkipped: mediaSkippedTotal
      };
      // Total response-byte budget: media entries are dropped from the
      // tail until the serialized result fits; the drop is reported.
      var out = JSON.stringify(result);
      var bytesDropped = 0;
      while (out.length > MAX_BYTES) {
        var dropped = false;
        for (var bi = frames.length - 1; bi >= 0; bi--) {
          var fm = frames[bi].media;
          if (fm && fm.length) { fm.pop(); bytesDropped++; dropped = true;
                                 frames[bi].mediaSkipped++; break; }
        }
        if (!dropped) break;
        out = JSON.stringify(result);
      }
      if (bytesDropped) {
        result.mediaDropped = bytesDropped;
        result.truncated = true;
        out = JSON.stringify(result);
      }
      return out;
    })()
    """

    /// Read-only media-state sample of the page bound to [args]' target.
    ///
    /// Same binding discipline as `takeSnapshot`: (viewId, expectedIdentityId,
    /// live instance, window, provisional + commit generations) is re-verified
    /// when the async evaluation completes, so a navigation or instance swap
    /// mid-eval fails `target_changed` instead of mixing results across
    /// targets. Only the fixed `mediaProbeScript` runs — no caller-supplied
    /// JavaScript. Completes exactly once via the shared completion gate:
    /// the probe result or `media_timeout` after `SnapshotPolicy.deadline`.
    private func sampleMedia(_ args: [String: Any], result: @escaping FlutterResult) {
        guard let viewId = (args["viewId"] as? NSNumber)?.int64Value,
              let expectedIdentityId = args["expectedIdentityId"] as? String else {
            result(FlutterError(code: "invalid_argument", message: "viewId and expectedIdentityId are required", details: nil))
            return
        }
        guard let webView = webViews[viewId],
              identityIdFor(viewId: viewId) == expectedIdentityId else {
            result(FlutterError(code: "target_changed", message: "Target is not bound to a live web view", details: nil))
            return
        }
        guard let initialWindowNumber = webView.window?.windowNumber else {
            result(FlutterError(code: "target_changed", message: "Target view is not in a window", details: nil))
            return
        }
        let binding = SnapshotTargetBinding(
            viewId: viewId,
            identityId: expectedIdentityId,
            instanceId: ObjectIdentifier(webView),
            provisionalGeneration: navigationGenerations[viewId] ?? 0,
            commitGeneration: navigationCommitGenerations[viewId] ?? 0,
            windowNumber: initialWindowNumber,
        )
        let gate = SnapshotCompletionGate()
        DispatchQueue.main.asyncAfter(deadline: .now() + SnapshotPolicy.deadline) {
            if gate.claim() {
                result(FlutterError(
                    code: "media_timeout",
                    message: "Media probe did not complete within \(Int(SnapshotPolicy.deadline)) s",
                    details: nil,
                ))
            }
        }
        webView.evaluateJavaScript(Self.mediaProbeScript) { [weak self, weak webView] value, error in
            // Late callback after the deadline: return before binding checks
            // or any success result.
            guard gate.claim() else { return }
            guard let self else { return }
            if let error {
                result(FlutterError(code: "media_failed", message: error.localizedDescription, details: nil))
                return
            }
            guard let json = value as? String else {
                result(FlutterError(code: "media_failed", message: "Media probe returned no JSON payload", details: nil))
                return
            }
            let liveView = self.webViews[viewId]
            guard binding.isStillBound(
                liveInstance: liveView,
                liveIdentityId: self.identityIdFor(viewId: viewId),
                liveProvisionalGeneration: self.navigationGenerations[viewId] ?? 0,
                liveCommitGeneration: self.navigationCommitGenerations[viewId] ?? 0,
                liveWindowNumber: liveView?.window?.windowNumber
            ), let webView else {
                result(FlutterError(code: "target_changed", message: "Target changed during media probe", details: nil))
                return
            }
            result([
                "json": json,
                "url": webView.url?.absoluteString as Any,
                "windowId": self.orNull(webView.window?.windowNumber),
            ])
        }
    }

    /// Fixed read-only drain for the in-page error buffer (issue #17). Reads
    /// the main document's buffer plus every reachable same-origin iframe's;
    /// unreachable frames are marked `reachable:false`. `installed:false`
    /// distinguishes a view created without the capture flag from a genuine
    /// empty buffer — "no errors recorded" is never conflated with "cannot
    /// observe". The drain is read-only: entries persist for later samples.
    private static let errorsDrainScript = """
    (function () {
      var frames = [];
      function read(doc, label, url) {
        var b = (doc.defaultView || window).__relayErrors || null;
        var f = { index: frames.length, label: label, url: url,
                  reachable: true, installed: !!b, errors: [] };
        if (b) {
          f.bufferId = b.bufferId; f.collectedAt = b.startedAt;
          f.overflow = b.overflow; f.count = b.entries.length;
          f.errors = b.entries.slice();
        }
        frames.push(f);
      }
      read(document, 'main', location.href);
      var iframes = document.querySelectorAll('iframe');
      for (var k = 0; k < iframes.length; k++) {
        var el = iframes[k];
        try {
          var idoc = el.contentDocument ||
                     (el.contentWindow && el.contentWindow.document);
          if (!idoc) { throw new Error('unavailable'); }
          read(idoc, 'iframe' + k,
               (idoc.location && idoc.location.href) || el.src || null);
        } catch (e) {
          frames.push({ index: frames.length, label: 'iframe' + k,
                        url: el.src || null, reachable: false,
                        reason: 'unavailable', installed: false, errors: [] });
        }
      }
      return JSON.stringify({ frames: frames });
    })()
    """

    /// Read-only drain of the page error buffer bound to [args]' target.
    /// Same binding, gate and deadline discipline as `sampleMedia` — drift
    /// mid-eval fails `target_changed`, never mixes buffers across targets.
    private func drainJsErrors(_ args: [String: Any], result: @escaping FlutterResult) {
        guard let viewId = (args["viewId"] as? NSNumber)?.int64Value,
              let expectedIdentityId = args["expectedIdentityId"] as? String else {
            result(FlutterError(code: "invalid_argument", message: "viewId and expectedIdentityId are required", details: nil))
            return
        }
        guard let webView = webViews[viewId],
              identityIdFor(viewId: viewId) == expectedIdentityId else {
            result(FlutterError(code: "target_changed", message: "Target is not bound to a live web view", details: nil))
            return
        }
        guard let initialWindowNumber = webView.window?.windowNumber else {
            result(FlutterError(code: "target_changed", message: "Target view is not in a window", details: nil))
            return
        }
        let binding = SnapshotTargetBinding(
            viewId: viewId,
            identityId: expectedIdentityId,
            instanceId: ObjectIdentifier(webView),
            provisionalGeneration: navigationGenerations[viewId] ?? 0,
            commitGeneration: navigationCommitGenerations[viewId] ?? 0,
            windowNumber: initialWindowNumber,
        )
        let gate = SnapshotCompletionGate()
        DispatchQueue.main.asyncAfter(deadline: .now() + SnapshotPolicy.deadline) {
            if gate.claim() {
                result(FlutterError(
                    code: "errors_timeout",
                    message: "Error drain did not complete within \(Int(SnapshotPolicy.deadline)) s",
                    details: nil,
                ))
            }
        }
        webView.evaluateJavaScript(Self.errorsDrainScript) { [weak self, weak webView] value, error in
            guard gate.claim() else { return }
            guard let self else { return }
            if let error {
                result(FlutterError(code: "errors_failed", message: error.localizedDescription, details: nil))
                return
            }
            guard let json = value as? String else {
                result(FlutterError(code: "errors_failed", message: "Error drain returned no JSON payload", details: nil))
                return
            }
            let liveView = self.webViews[viewId]
            guard binding.isStillBound(
                liveInstance: liveView,
                liveIdentityId: self.identityIdFor(viewId: viewId),
                liveProvisionalGeneration: self.navigationGenerations[viewId] ?? 0,
                liveCommitGeneration: self.navigationCommitGenerations[viewId] ?? 0,
                liveWindowNumber: liveView?.window?.windowNumber
            ), let webView else {
                result(FlutterError(code: "target_changed", message: "Target changed during error drain", details: nil))
                return
            }
            result([
                "json": json,
                "url": webView.url?.absoluteString as Any,
                "windowId": self.orNull(webView.window?.windowNumber),
            ])
        }
    }

    /// Bumps the provisional-navigation generation for [webView]'s view.
    /// Called from didStartProvisionalNavigation so in-flight snapshots see
    /// the target as changed once a page navigation actually begins.
    func bumpNavigationGeneration(for webView: WKWebView) {
        guard let viewId = viewId(of: webView) else { return }
        navigationGenerations[viewId, default: 0] += 1
    }

    /// Bumps the commit-navigation generation for [webView]'s view. Called
    /// from didCommit so a navigation already in flight when a snapshot was
    /// bound is caught the moment it commits — where a provisional-only
    /// generation would have missed it.
    func bumpNavigationCommitGeneration(for webView: WKWebView) {
        guard let viewId = viewId(of: webView) else { return }
        navigationCommitGenerations[viewId, default: 0] += 1
    }

    /// Bridges an optional Int into a message-codec value: NSNull for nil so
    /// the key survives as JSON null instead of a malformed entry.
    private func orNull(_ value: Int?) -> Any {
        guard let value else { return NSNull() }
        return value
    }

    /// Runs a navigation action on the resolved webview. A miss is logged and,
    /// for load-type actions, reported as loadFailed so the Dart spinner can
    /// never be stuck on a dead viewId (stop is intentionally not included —
    /// nothing to unlatch when there is no view).
    private func tryNavigate(
        _ args: [String: Any],
        action: String,
        _ block: (WKWebView) -> Void
    ) -> Bool {
        let viewId = (args["viewId"] as? NSNumber)?.int64Value ?? 0
        let identityId = identityIdFor(viewId: viewId)
        guard let webView = webViews[viewId] else {
            DiagnosticsLog.shared.log("navActionMiss", fields: [
                "action": action,
                "viewId": viewId,
                "identityId": identityId ?? "",
            ])
            if action == "reload", let identityId {
                emit([
                    "event": "loadFailed",
                    "identityId": identityId,
                    "url": "",
                    "error": "no live webview for viewId \(viewId)",
                    "code": "NO_WEBVIEW",
                ])
            }
            return false
        }
        DiagnosticsLog.shared.log("navAction", fields: [
            "action": action,
            "viewId": viewId,
            "identityId": identityId ?? "",
            "url": webView.url?.absoluteString ?? "",
        ])
        if action == "reload" || action == "goBack" || action == "goForward" {
            armLoadWatchdog(viewId: viewId, identityId: identityId ?? "", reason: action)
        }
        block(webView)
        return true
    }

    // MARK: - Platform view lifecycle

    /// Called by the factory when a new PlatformView is created.
    ///
    /// `isolationMode` is the Dart IsolationMode.dbValue; `fingerprint` is the
    /// PanelRuntimeConfig fingerprint. An existing WKWebView is reused only
    /// when BOTH match what the live view was created with — otherwise the
    /// stale view (and its old data store) is torn down and a fresh one is
    /// created, so a mode switch never keeps the wrong store.
    ///
    /// Device-emulation params (`userAgent`, `touchEmulation`,
    /// `viewportWidth/Height`) are already covered by the fingerprint on the
    /// Dart side, so a preset change always reaches this fresh-creation path.
    @discardableResult
    func registerWebView(
        viewId: Int64,
        identityId: String,
        url: String?,
        isolationMode: String,
        fingerprint: String,
        userAgent: String? = nil,
        touchEmulation: Bool = false,
        viewportWidth: Double? = nil,
        viewportHeight: Double? = nil,
        viewportFollowsSurface: Bool = false,
        automationErrorCapture: Bool = false
    ) -> NSView {
        let requestedKind = Self.storeKind(for: isolationMode)
        let reusable = identityStoreKinds[identityId] == requestedKind
            && identityFingerprints[identityId] == fingerprint
        DiagnosticsLog.shared.log("registerWebView", fields: [
            "viewId": viewId,
            "identityId": identityId,
            "storeKind": requestedKind.rawValue,
            "reusable": reusable,
            "hasDetachedWindow": detachedWindows[identityId] != nil,
            "hasExistingMapping": viewIdByIdentity[identityId] != nil,
            "fingerprint": fingerprint,
            "hasUserAgent": userAgent != nil,
            "touchEmulation": touchEmulation,
            "automationErrorCapture": automationErrorCapture,
        ])

        // If a detached window exists for this identity, reattach the existing
        // webView instead of creating a new one (attaching state transition).
        if let existing = detachedWindows[identityId] {
            detachedWindows.removeValue(forKey: identityId)
            // Programmatic close for reattach/teardown: windowWillClose must
            // not run the user-close writeback (it would strip the webView's
            // handlers, drop the view maps, and emit a bogus "closed").
            existing.suppressOnClose = true
            existing.detachWebViewForReattach()
            existing.close()
            let webView = existing.webView
            let previousViewId = viewIdByIdentity[identityId]
            if reusable {
                let container = PlatformViewContainer()
                container.autoresizingMask = [.width, .height]
                webView.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
                container.addSubview(webView)
                webView.autoresizingMask = [.width, .height]
                containers[viewId] = container
                webViews[viewId] = webView
                viewIdByIdentity[identityId] = viewId
                rekeyViewAttachments(from: previousViewId, to: viewId, webView: webView, identityId: identityId)
                emitState(identityId: identityId, state: "embedded")
                return container
            }
            // Mode/config changed while detached: discard the old WebView so
            // it cannot carry its stale store into the rebuilt view.
            teardownWebView(viewId: previousViewId ?? viewId, webView: webView)
        }

        // Focus layout reparents a panel between its main and side slots.
        // Preserve the already-loaded WKWebView rather than creating a second
        // instance and loading its initial URL again.
        if let existingViewId = viewIdByIdentity[identityId],
           let webView = webViews[existingViewId] {
            if !reusable {
                // Stale mapping (e.g. a config-change rebuild where the native
                // close has not been processed yet): tear down the old WebView
                // so it never reappears under the new configuration.
                teardownWebView(viewId: existingViewId, webView: webView)
            } else {
                webView.removeFromSuperview()
                containers.removeValue(forKey: existingViewId)
                webViews.removeValue(forKey: existingViewId)

                let container = PlatformViewContainer()
                container.autoresizingMask = [.width, .height]
                webView.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
                container.addSubview(webView)
                webView.autoresizingMask = [.width, .height]
                containers[viewId] = container
                webViews[viewId] = webView
                viewIdByIdentity[identityId] = viewId
                rekeyViewAttachments(from: existingViewId, to: viewId, webView: webView, identityId: identityId)
                emitState(identityId: identityId, state: "embedded")
                return container
            }
        }

        let config = WKWebViewConfiguration()
        identityStoreKinds[identityId] = requestedKind
        identityFingerprints[identityId] = fingerprint

        if requestedKind == .shared {
            // SharedSession: deliberately NOT isolated. All shared identities
            // share the app's default persistent WKWebsiteDataStore so a login
            // in one is visible in the others (ADR-0002). The store is kept
            // out of `dataStores` so clearIdentityData cannot wipe every
            // shared session's data under a single identity's name.
            config.websiteDataStore = WKWebsiteDataStore.default()
        } else {
            let uuid = identityUuids[identityId] ?? UUID(uuidString: identityId) ?? UUID()
            identityUuids[identityId] = uuid

            if #available(macOS 14.0, *) {
                // Per-identity persistent data store — the core isolation mechanism.
                let store = WKWebsiteDataStore(forIdentifier: uuid)
                config.websiteDataStore = store
                dataStores[identityId] = store
            } else {
                // macOS 13 fallback: non-persistent only (NOT valid for release isolation).
                config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
            }
        }

        // Let pages request a new tab/window. BrowserUIDelegate redirects that
        // navigation into the current managed panel instead of dropping it.
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        // Video controls on macOS use WebKit's native media fullscreen entry
        // point. The injected bridge immediately redirects it to the video
        // element's page-level fullscreen styles instead of keeping the
        // WebView in a system fullscreen window.
        if #available(macOS 12.3, *) {
            config.preferences.isElementFullscreenEnabled = true
        }
        addRouteReporter(to: config, viewId: viewId, identityId: identityId)
        addInAppFullscreenBridge(to: config, viewId: viewId, identityId: identityId)
        addMeasureModeBridge(to: config, viewId: viewId, identityId: identityId)
        if touchEmulation {
            addTouchEmulationScript(to: config)
        }
        if automationErrorCapture {
            addErrorCaptureScript(to: config)
        }
        // Emulated CSS viewport (mobile width-clamp and fixed window-size
        // presets, plus the `custom` seed): remembered for detach so the
        // detached window's content area matches the emulated surface.
        if let viewportWidth, let viewportHeight, viewportWidth > 0, viewportHeight > 0 {
            identityViewports[identityId] = CGSize(width: viewportWidth, height: viewportHeight)
        } else {
            identityViewports.removeValue(forKey: identityId)
        }
        if viewportFollowsSurface {
            identityViewportFollows.insert(identityId)
        } else {
            identityViewportFollows.remove(identityId)
        }
        if #available(macOS 10.13, *) {
            config.suppressesIncrementalRendering = false
        }
        // Keep remote pages from opening privileged content.
        config.preferences.javaEnabled = true
        #if DEBUG
        // Enable right-click -> Inspect Element (Safari Web Inspector) on
        // debug builds only; release builds keep remote pages locked down.
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        let webView = ProfiledWebView(frame: .zero, configuration: config)
        webView.onClaimKeyboardFocus = { [weak self] completion in
            // Dart unfocus must settle before the webview claims first
            // responder: dropping widget focus tears down the text-input
            // plugin, which re-asserts FlutterView and would steal the
            // responder back from a webview that claimed it earlier.
            guard let channel = self?.channel else {
                completion()
                return
            }
            channel.invokeMethod("webviewPointerDown", arguments: nil) { _ in
                completion()
            }
        }
        // Mobile device emulation: override before the initial load so both
        // the HTTP User-Agent header and navigator.userAgent report the
        // preset's UA. nil keeps WKWebView's default desktop UA.
        if let userAgent, !userAgent.isEmpty {
            webView.customUserAgent = userAgent
        }
        webView.autoresizingMask = [.width, .height]
        let navDelegate = NavigationDelegate(plugin: self, identityId: identityId)
        webView.navigationDelegate = navDelegate
        let uiDelegate = BrowserUIDelegate()
        webView.uiDelegate = uiDelegate
        // Retain the delegate via the webView's userData map.
        objc_setAssociatedObject(webView, &NavigationDelegate.associatedKey, navDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(webView, &BrowserUIDelegate.associatedKey, uiDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        if let urlString = url, let url = URL(string: urlString) {
            // Arm the watchdog before the first load: a request issued before
            // the view is attached to a window can wedge without ever reaching
            // didStartProvisionalNavigation.
            armLoadWatchdog(viewId: viewId, identityId: identityId, reason: "initialLoad")
            webView.load(URLRequest(url: url))
        }

        let container = PlatformViewContainer()
        container.autoresizingMask = [.width, .height]
        // Give the webView a non-zero initial frame so WKWebView doesn't
        // render into a zero-size viewport before Flutter lays out the
        // container. PlatformViewContainer.layout() will sync it to the real
        // bounds once Flutter assigns them.
        webView.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        container.addSubview(webView)
        containers[viewId] = container
        webViews[viewId] = webView
        viewIdByIdentity[identityId] = viewId
        observeUrl(of: webView, viewId: viewId, identityId: identityId)
        emitState(identityId: identityId, state: "embedded")
        return container
    }

    /// Move a reused WebView's per-view attachments (URL observer, route
    /// reporter) from the old viewId key to the new one, re-installing the
    /// URL observer when none was recorded.
    private func rekeyViewAttachments(
        from oldViewId: Int64?,
        to viewId: Int64,
        webView: WKWebView,
        identityId: String
    ) {
        guard let oldViewId, oldViewId != viewId else {
            if urlObservers[viewId] == nil {
                observeUrl(of: webView, viewId: viewId, identityId: identityId)
            }
            return
        }
        if let urlObserver = urlObservers.removeValue(forKey: oldViewId) {
            urlObservers[viewId] = urlObserver
        } else {
            observeUrl(of: webView, viewId: viewId, identityId: identityId)
        }
        if let routeHandlerName = routeHandlerNames.removeValue(forKey: oldViewId) {
            routeHandlerNames[viewId] = routeHandlerName
        }
    }

    /// Fully dispose a stale WKWebView and its per-view bookkeeping. Used when
    /// a view is replaced under a different runtime config (isolation-mode or
    /// other fingerprint change) — reuse would carry the old data store over.
    private func teardownWebView(viewId: Int64, webView: WKWebView) {
        DiagnosticsLog.shared.log("teardownWebView", fields: [
            "viewId": viewId,
            "identityId": identityIdFor(viewId: viewId) ?? "",
            "url": webView.url?.absoluteString ?? "",
            "wasLoading": webView.isLoading,
        ])
        disarmLoadWatchdog(viewId: viewId)
        webView.stopLoading()
        urlObservers.removeValue(forKey: viewId)
        removeRouteReporter(for: viewId, webView: webView)
        removeInAppFullscreenBridge(for: viewId, webView: webView)
        removeMeasureModeBridge(for: viewId, webView: webView)
        webView.removeFromSuperview()
        webViews.removeValue(forKey: viewId)
        containers.removeValue(forKey: viewId)
        for (key, vid) in viewIdByIdentity where vid == viewId {
            viewIdByIdentity.removeValue(forKey: key)
        }
    }

    // MARK: - Detach / attach (embedded/detached state machine)

    private func detach(identityId: String, result: @escaping FlutterResult) {
        guard let viewId = viewIdByIdentity[identityId],
              let webView = webViews[viewId] else {
            result(FlutterError(code: "no_webview", message: "identity \(identityId)", details: nil))
            return
        }
        if detachedWindows[identityId] != nil {
            result(["detached": true, "alreadyDetached": true])
            return
        }
        emitState(identityId: identityId, state: "detaching")
        DiagnosticsLog.shared.log("detach", fields: ["identityId": identityId, "viewId": viewId])
        let controller = DetachedWindowController(
            identityId: identityId,
            webView: webView,
            // Mobile presets detach into a phone-sized window so the emulated
            // CSS viewport survives detaching.
            contentSize: identityViewports[identityId],
            onClose: { [weak self] in
                // User closed the detached window — write back `closed` so the
                // Dart state machine does not keep a ghost detached state
                // (rewrite-plan §4.8 / P1 detached lifecycle).
                guard let self = self else { return }
                DiagnosticsLog.shared.log("detachedWindowUserClose", fields: [
                    "identityId": identityId,
                ])
                self.exitInAppFullscreen(identityId: identityId)
                self.detachedWindows.removeValue(forKey: identityId)
                self.viewIdByIdentity.removeValue(forKey: identityId)
                var closedViewId: Int64 = 0
                if let viewId = self.webViews.first(where: { $0.value === webView })?.key {
                    closedViewId = viewId
                    self.teardownWebView(viewId: viewId, webView: webView)
                }
                // Carry the torn-down viewId so Dart can tell this closed event
                // apart from one belonging to a newer re-registered view.
                self.emit([
                    "event": "stateChanged",
                    "identityId": identityId,
                    "state": "closed",
                    "viewId": closedViewId,
                ])
            }
        )
        detachedWindows[identityId] = controller
        controller.show()
        emitState(identityId: identityId, state: "detached")
        result(["detached": true])
    }

    private func attach(identityId: String, result: @escaping FlutterResult) {
        guard let controller = detachedWindows[identityId] else {
            result(FlutterError(code: "not_detached", message: "identity \(identityId)", details: nil))
            return
        }
        emitState(identityId: identityId, state: "attaching")
        DiagnosticsLog.shared.log("attach", fields: ["identityId": identityId])
        detachedWindows.removeValue(forKey: identityId)
        // Programmatic close for reattach: suppress the user-close writeback so
        // the webView keeps its handlers/maps and no bogus "closed" is emitted.
        controller.suppressOnClose = true
        controller.detachWebViewForReattach()
        controller.close()
        let webView = controller.webView
        // The embedded platform view container usually survives detaching; put
        // the WebView back into it directly. If it was disposed meanwhile,
        // registerWebView's reparent path reseats the view when Flutter
        // recreates the platform view.
        if let viewId = viewIdByIdentity[identityId], let container = containers[viewId] {
            webView.frame = CGRect(origin: .zero, size: container.bounds.size)
            webView.autoresizingMask = [.width, .height]
            container.addSubview(webView)
            container.needsLayout = true
        }
        emitState(identityId: identityId, state: "embedded")
        result(["attaching": true, "reattached": true])
    }

    private func close(viewId: Int64, identityId: String, result: @escaping FlutterResult) {
        // Stale-close guard: if the identity has already been re-registered to
        // a different (newer) view, this close was issued against the old one.
        // The addressed view is still torn down, but the identity mapping,
        // detached window and fullscreen state belong to the new view and must
        // not be touched — and no closing/closed state may be emitted for it.
        //
        // A close that omits viewId (Dart had no mapping yet) means "close
        // whatever is current" — resolve it to the mapped view so it cannot
        // bypass the guard and orphan the live view's bookkeeping.
        let mappedViewId = viewIdByIdentity[identityId]
        let effectiveViewId = viewId != 0 ? viewId : (mappedViewId ?? 0)
        let stale = mappedViewId != nil && effectiveViewId != 0 && mappedViewId != effectiveViewId
        DiagnosticsLog.shared.log("close", fields: [
            "identityId": identityId,
            "viewId": viewId,
            "effectiveViewId": effectiveViewId,
            "mappedViewId": mappedViewId ?? -1,
            "stale": stale,
        ])
        if !stale {
            emitState(identityId: identityId, state: "closing")
            exitInAppFullscreen(identityId: identityId)
            if let controller = detachedWindows.removeValue(forKey: identityId) {
                controller.suppressOnClose = true
                controller.close()
            }
        }
        if let webView = webViews[effectiveViewId] {
            // teardownWebView removes identity mappings pointing at this
            // view; in the stale case that is a different viewId, so the new
            // mapping survives untouched.
            teardownWebView(viewId: effectiveViewId, webView: webView)
        } else {
            containers.removeValue(forKey: effectiveViewId)
        }
        if !stale {
            viewIdByIdentity.removeValue(forKey: identityId)
            // Carry the closed viewId so Dart ignores this event when a newer
            // view has already been registered for the identity.
            emit([
                "event": "stateChanged",
                "identityId": identityId,
                "state": "closed",
                "viewId": effectiveViewId,
            ])
        }
        result(nil)
    }

    private func toggleInAppFullscreen(identityId: String, result: @escaping FlutterResult) {
        if fullscreenHosts[identityId] != nil {
            exitInAppFullscreen(identityId: identityId)
            result(false)
            return
        }
        enterInAppFullscreen(identityId: identityId)
        result(fullscreenHosts[identityId] != nil)
    }

    // MARK: - Clear / disk checks

    /// The WKWebsiteDataStore the identity's live (or detached) view is using.
    /// SharedSession views resolve to the shared default store; per-identity
    /// views resolve to their persistent WKWebsiteDataStore(forIdentifier:).
    private func storeFor(identityId: String) -> WKWebsiteDataStore? {
        if let viewId = viewIdByIdentity[identityId], let webView = webViews[viewId] {
            return webView.configuration.websiteDataStore
        }
        if let controller = detachedWindows[identityId] {
            return controller.webView.configuration.websiteDataStore
        }
        return dataStores[identityId]
    }

    private func setCookie(identityId: String, name: String, value: String, domain: String, expiresSeconds: Double? = nil, result: @escaping FlutterResult) {
        guard let store = storeFor(identityId: identityId) else {
            result(FlutterError(code: "no_store", message: "identity \(identityId)", details: nil))
            return
        }
        var props: [HTTPCookiePropertyKey: Any] = [
            .domain: domain,
            .path: "/",
            .name: name,
            .value: value,
        ]
        // Session cookies (no expires) never reach disk — cold-restart tests
        // need a persistent expiry so persistence is distinguishable from a
        // naturally-expired cookie.
        if let expires = expiresSeconds {
            props[.expires] = Date(timeIntervalSince1970: expires)
        }
        let cookie = HTTPCookie(properties: props)
        guard let cookie else {
            result(FlutterError(code: "bad_cookie", message: name, details: nil))
            return
        }
        store.httpCookieStore.setCookie(cookie) { result(true) }
    }

    private func deleteCookie(identityId: String, name: String, domain: String, result: @escaping FlutterResult) {
        guard let store = storeFor(identityId: identityId) else {
            result(FlutterError(code: "no_store", message: "identity \(identityId)", details: nil))
            return
        }
        store.httpCookieStore.getAllCookies { cookies in
            let matching = cookies.filter { $0.name == name && $0.domain == domain }
            let group = DispatchGroup()
            for cookie in matching {
                group.enter()
                store.httpCookieStore.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) { result(matching.count) }
        }
    }

    private func clearIdentityData(identityId: String, result: @escaping FlutterResult) {
        if identityStoreKinds[identityId] == .shared {
            // A sharedSession view has no per-identity store; clearing it would
            // wipe every shared identity's data. Refuse instead of silently
            // doing the wrong thing.
            result(FlutterError(
                code: "shared_store",
                message: "identity \(identityId) uses the shared default store; per-identity clear is not applicable",
                details: nil
            ))
            return
        }
        guard let store = dataStores[identityId] else {
            result(FlutterError(code: "no_store", message: "identity \(identityId)", details: nil))
            return
        }
        DiagnosticsLog.shared.log("clearIdentityData", fields: ["identityId": identityId])
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        // Remove all data from THIS identity's store only.
        store.removeData(ofTypes: allTypes, modifiedSince: Date.distantPast) {
            result(nil)
        }
    }

    private func checkDataStoreExists(identityId: String) -> Bool {
        if identityStoreKinds[identityId] == .shared {
            return dataStorePath(identityId: identityId) != nil
        }
        guard let uuid = identityUuids[identityId] else { return false }
        guard #available(macOS 14.0, *) else { return false }
        // In the sandboxed app, the data stores live under the container's
        // Library/WebKit/WebsiteDataStore/<uuid>/. FileManager.url(for:in:appropriateFor:create:)
        // resolves to the container path under App Sandbox.
        let fm = FileManager.default
        let baseDir: URL
        if let libDir = fm.urls(for: .libraryDirectory, in: .userDomainMask).first {
            baseDir = libDir.appendingPathComponent("WebKit/WebsiteDataStore")
        } else {
            return false
        }
        let uuidString = uuid.uuidString
        // WebKit uses the UUID string as-is (uppercase hex with hyphens).
        let candidates = [
            baseDir.appendingPathComponent(uuidString),
            baseDir.appendingPathComponent(uuidString.uppercased()),
            baseDir.appendingPathComponent(uuidString.lowercased()),
        ]
        return candidates.contains { fm.fileExists(atPath: $0.path) }
    }

    private func dataStorePath(identityId: String) -> String? {
        let fm = FileManager.default
        guard let libDir = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else { return nil }
        if identityStoreKinds[identityId] == .shared {
            // The shared default store persists under the container's
            // Library/WebKit — there is no per-UUID directory for it.
            for candidate in ["WebKit/WebsiteData", "WebKit"] {
                let path = libDir.appendingPathComponent(candidate)
                if fm.fileExists(atPath: path.path) {
                    return path.path
                }
            }
            return nil
        }
        guard let uuid = identityUuids[identityId] else { return nil }
        let baseDir = libDir.appendingPathComponent("WebKit/WebsiteDataStore")
        let uuidString = uuid.uuidString
        for candidate in [uuidString, uuidString.uppercased(), uuidString.lowercased()] {
            let path = baseDir.appendingPathComponent(candidate)
            if fm.fileExists(atPath: path.path) {
                return path.path
            }
        }
        return nil
    }

    private func enterInAppFullscreen(identityId: String) {
        guard fullscreenHosts[identityId] == nil,
              let viewId = viewIdByIdentity[identityId],
              let webView = webViews[viewId],
              let window = webView.window ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow,
              let contentView = window.contentView,
              let originalSuperview = webView.superview else { return }

        let originalFrame = webView.frame
        let placeholder = NSView(frame: originalFrame)
        placeholder.autoresizingMask = webView.autoresizingMask
        originalSuperview.addSubview(placeholder, positioned: .below, relativeTo: webView)
        webView.removeFromSuperview()

        let host = InAppFullscreenHostView(
            frame: contentView.bounds,
            webView: webView,
            placeholder: placeholder,
            originalSuperview: originalSuperview,
            originalFrame: originalFrame,
            onExit: { [weak self] in
                self?.exitInAppFullscreen(identityId: identityId)
            }
        )
        host.autoresizingMask = [.width, .height]
        contentView.addSubview(host, positioned: .above, relativeTo: nil)
        host.frame = contentView.bounds
        host.addSubview(webView, positioned: .below, relativeTo: nil)
        webView.frame = host.bounds
        webView.autoresizingMask = [.width, .height]
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        fullscreenHosts[identityId] = host
        window.makeFirstResponder(host)
        emit(["event": "fullscreenChanged", "identityId": identityId, "isFullscreen": true])
    }

    private func exitInAppFullscreen(identityId: String) {
        guard let host = fullscreenHosts.removeValue(forKey: identityId) else { return }
        let webView = host.webView
        webView.removeFromSuperview()
        host.removeFromSuperview()
        host.placeholder.removeFromSuperview()
        host.originalSuperview?.addSubview(webView)
        webView.frame = host.originalFrame
        webView.autoresizingMask = [.width, .height]
        host.originalSuperview?.needsLayout = true
        host.originalSuperview?.layoutSubtreeIfNeeded()
        emit(["event": "fullscreenChanged", "identityId": identityId, "isFullscreen": false])
    }
}

/// WKWebView with mouse side-button (X1/X2) history navigation.
///
/// Why this exists: pointer events landing on web content are delivered to
/// AppKit and never enter Flutter's framework hit-testing, so the Dart-side
/// Listener in the workspace cannot see side buttons pressed over a page.
/// Raw WKWebView ignores buttonNumber 3/4, so Safari-style back/forward is
/// added here explicitly.
///
/// The press lands on WebKit's private content subview; AppKit forwards the
/// unhandled `otherMouseDown` up the responder chain to this subclass. Only
/// buttons 3 (back) and 4 (forward) are consumed — everything else (notably
/// middle-click, button 2) falls through to super unchanged. The subclass
/// travels with the WKWebView, so embedded, detached-window, and in-app
/// fullscreen states are all covered. History flags refresh on the Dart side
/// via the existing didFinish/url-observer events.
///
/// Note: PDF/plugin content renders in dedicated system subviews that may
/// consume side-button events themselves; over those areas back/forward is
/// then a silent no-op.
final class ProfiledWebView: WKWebView {
    /// Set at creation (registerWebView). Invoked on a click while a foreign
    /// responder owns the keyboard; must call its completion once the
    /// Dart-side widget focus has been dropped so this view can safely claim
    /// first responder afterwards.
    var onClaimKeyboardFocus: (((@escaping () -> Void) -> Void))?

    override var acceptsFirstResponder: Bool { true }

    /// Whether the window's first responder is inside this webview — or is
    /// the in-app fullscreen chrome hosting it (that host owns the responder
    /// while this view's page is fullscreened).
    private var ownsKeyboardFocus: Bool {
        guard let window = window ?? superview?.window,
              let responder = window.firstResponder as? NSView else {
            return false
        }
        if responder === self || responder.isDescendant(of: self) {
            return true
        }
        if let host = responder as? InAppFullscreenHostView, host.webView === self {
            return true
        }
        return false
    }

    /// macOS dispatches Cmd+key equivalents to the window's first responder —
    /// but clicking a platform view does not always move first responder off
    /// Flutter's hidden text-input plugin (a Dart TextField holds it), so
    /// Cmd+C/V/X/A would dispatch to the plugin instead of the page (same
    /// embedder quirk as flutter_inappwebview #2380). On each click: ask Dart
    /// to drop widget focus FIRST — its text-input teardown re-asserts
    /// FlutterView as first responder and would steal the responder back from
    /// a webview that claimed it earlier — then claim first responder and let
    /// the click proceed.
    private func prepareKeyboardFocus(then proceed: @escaping () -> Void) {
        if ownsKeyboardFocus {
            proceed()
            return
        }
        guard let window = window ?? superview?.window else {
            proceed()
            return
        }
        guard let claim = onClaimKeyboardFocus else {
            window.makeFirstResponder(self)
            proceed()
            return
        }
        claim { [weak self] in
            guard let self else {
                proceed()
                return
            }
            (self.window ?? self.superview?.window)?.makeFirstResponder(self)
            proceed()
        }
    }

    override func mouseDown(with event: NSEvent) {
        prepareKeyboardFocus { [weak self] in self?.handleMouseDown(event) }
    }

    override func rightMouseDown(with event: NSEvent) {
        prepareKeyboardFocus { [weak self] in self?.handleRightMouseDown(event) }
    }

    override func otherMouseDown(with event: NSEvent) {
        prepareKeyboardFocus { [weak self] in self?.handleOtherMouseDown(event) }
    }

    // `super` cannot be referenced inside an escaping closure, so the
    // post-claim dispatch lives in plain methods.
    private func handleMouseDown(_ event: NSEvent) {
        super.mouseDown(with: event)
    }

    private func handleRightMouseDown(_ event: NSEvent) {
        super.rightMouseDown(with: event)
    }

    private func handleOtherMouseDown(_ event: NSEvent) {
        switch event.buttonNumber {
        case 3:
            if canGoBack { goBack() }
        case 4:
            if canGoForward { goForward() }
        default:
            super.otherMouseDown(with: event)
        }
    }

    /// Browser-style key equivalents for the focused page. Views are offered
    /// key equivalents before the main menu, and every panel's webview is
    /// asked — so only consume keys when this view owns the keyboard focus.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, ownsKeyboardFocus else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == [.command, .shift],
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let shift = flags.contains(.shift)
        switch key {
        case "c": return dispatchEditingAction("copy:")
        case "x": return dispatchEditingAction("cut:")
        case "v": return dispatchEditingAction("paste:")
        case "a": return dispatchEditingAction("selectAll:")
        case "z": return dispatchEditingAction(shift ? "redo:" : "undo:")
        case "r":
            if shift { reloadFromOrigin() } else { reload() }
            return true
        case "[" where !shift:
            if canGoBack { goBack() }
            return true
        case "]" where !shift:
            if canGoForward { goForward() }
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    /// Dispatches a standard editing action (copy:/paste:/…) to the responder
    /// chain starting at the first responder — the page's content view.
    private func dispatchEditingAction(_ selectorName: String) -> Bool {
        // In in-app fullscreen the chrome view owns the responder; hand it to
        // the webview first so the command reaches WebKit's content view.
        if let host = (window ?? superview?.window)?.firstResponder
            as? InAppFullscreenHostView,
           host.webView === self {
            (window ?? superview?.window)?.makeFirstResponder(self)
        }
        return NSApp.sendAction(NSSelectorFromString(selectorName), to: nil, from: self)
    }
}

/// Container NSView returned to Flutter. Holding the WKWebView inside a
/// container lets us move the WebView into a detached window and back without
/// destroying the Flutter platform view.
final class PlatformViewContainer: NSView {
    override var isFlipped: Bool { true }

    /// Explicitly sync the WKWebView frame whenever the container is laid out
    /// by Flutter. Relying solely on autoresizingMask fails when the container
    /// starts at .zero and is resized by Flutter's asynchronous layout pass —
    /// the WKWebView's internal scrollview keeps the old (zero) viewport and
    /// the page content appears offset/blank until a manual resize triggers a
    /// relayout.
    override func layout() {
        super.layout()
        for subview in subviews {
            subview.frame = bounds
        }
    }
}

/// Keeps a WebView inside the application's content view while the page is in
/// the app-managed fullscreen state. WebKit's native fullscreen window is not
/// used because it escapes the Relay Desk window and changes macOS window UI.
final class InAppFullscreenHostView: NSView {
    let webView: WKWebView
    let placeholder: NSView
    weak var originalSuperview: NSView?
    let originalFrame: CGRect
    private let onExit: () -> Void

    init(
        frame: CGRect,
        webView: WKWebView,
        placeholder: NSView,
        originalSuperview: NSView,
        originalFrame: CGRect,
        onExit: @escaping () -> Void
    ) {
        self.webView = webView
        self.placeholder = placeholder
        self.originalSuperview = originalSuperview
        self.originalFrame = originalFrame
        self.onExit = onExit
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        canDrawSubviewsIntoLayer = true
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
        let closeButton = NSButton(title: "Exit Full Screen", target: self, action: #selector(exitFullscreen))
        closeButton.bezelStyle = .texturedRounded
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || event.keyCode == 117 {
            onExit()
        } else {
            super.keyDown(with: event)
        }
    }

    @objc private func exitFullscreen() {
        onExit()
    }
}

final class NavigationDelegate: NSObject, WKNavigationDelegate {
    static var associatedKey: UInt8 = 0
    private weak var plugin: ProfiledWebViewPlugin?
    private let identityId: String

    init(plugin: ProfiledWebViewPlugin, identityId: String) {
        self.plugin = plugin
        self.identityId = identityId
    }

    private func logFields(
        _ webView: WKWebView,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var fields: [String: Any] = [
            "identityId": identityId,
            "viewId": plugin?.viewId(of: webView) ?? -1,
            "url": webView.url?.absoluteString ?? "",
        ]
        for (k, v) in extra { fields[k] = v }
        return fields
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let viewId = plugin?.viewId(of: webView) {
            plugin?.disarmLoadWatchdog(viewId: viewId)
        }
        DiagnosticsLog.shared.log(
            "nav.didFinish",
            fields: logFields(webView, extra: [
                "canGoBack": webView.canGoBack,
                "canGoForward": webView.canGoForward,
            ])
        )
        plugin?.emit([
            "event": "loadComplete",
            "identityId": identityId,
            "url": webView.url?.absoluteString ?? "",
            "canGoBack": webView.canGoBack,
            "canGoForward": webView.canGoForward,
        ])
        // A full navigation reset the page context (and with it our overlay
        // DOM). If measure mode is still armed for this view, reinstall it.
        if let viewId = plugin?.viewId(of: webView) {
            plugin?.rearmMeasureMode(viewId: viewId, webView: webView)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if let viewId = plugin?.viewId(of: webView) {
            plugin?.disarmLoadWatchdog(viewId: viewId)
        }
        let nsError = error as NSError
        DiagnosticsLog.shared.log(
            "nav.didFail",
            fields: logFields(webView, extra: [
                "domain": nsError.domain, "code": nsError.code,
                "error": error.localizedDescription,
            ])
        )
        plugin?.emit([
            "event": "loadFailed",
            "identityId": identityId,
            "url": webView.url?.absoluteString ?? "",
            "error": error.localizedDescription,
            "code": "\(nsError.domain):\(nsError.code)",
        ])
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // Re-arm here (not only at the loadUrl call site) so link clicks and
        // JS-initiated navigations are also covered.
        if let viewId = plugin?.viewId(of: webView) {
            plugin?.armLoadWatchdog(viewId: viewId, identityId: identityId, reason: "didStart")
            plugin?.bumpNavigationGeneration(for: webView)
        }
        DiagnosticsLog.shared.log("nav.didStart", fields: logFields(webView))
        plugin?.emit([
            "event": "loadStarted",
            "identityId": identityId,
            "url": webView.url?.absoluteString ?? "",
        ])
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        plugin?.bumpNavigationCommitGeneration(for: webView)
        DiagnosticsLog.shared.log("nav.didCommit", fields: logFields(webView))
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        DiagnosticsLog.shared.log("nav.serverRedirect", fields: logFields(webView))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if let viewId = plugin?.viewId(of: webView) {
            plugin?.disarmLoadWatchdog(viewId: viewId)
        }
        let nsError = error as NSError
        DiagnosticsLog.shared.log(
            "nav.didFailProvisional",
            fields: logFields(webView, extra: [
                "domain": nsError.domain, "code": nsError.code,
                "error": error.localizedDescription,
            ])
        )
        plugin?.emit([
            "event": "loadFailed",
            "identityId": identityId,
            "url": webView.url?.absoluteString ?? "",
            "error": error.localizedDescription,
            "code": "\(nsError.domain):\(nsError.code)",
        ])
    }

    /// WebContent process crash/kill: WKWebView calls this INSTEAD of a nav
    /// failure — without it a dead process leaves the UI spinner up forever.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if let viewId = plugin?.viewId(of: webView) {
            plugin?.disarmLoadWatchdog(viewId: viewId)
        }
        DiagnosticsLog.shared.log(
            "nav.webContentProcessTerminated",
            fields: logFields(webView)
        )
        plugin?.emit([
            "event": "loadFailed",
            "identityId": identityId,
            "url": webView.url?.absoluteString ?? "",
            "error": "web content process terminated",
            "code": "WEBCONTENT_TERMINATED",
        ])
    }
}

/// Routes target="_blank" and window.open() requests back through the
/// existing, Flutter-managed WKWebView. Without this UI delegate WebKit drops
/// those navigations because no new native window is created for them.
final class BrowserUIDelegate: NSObject, WKUIDelegate {
    static var associatedKey: UInt8 = 0

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        webView.load(navigationAction.request)
        return nil
    }
}

/// Hosts a detached WKWebView in a separate child window. When the user
/// closes the window, `onClose` fires so Dart can update the state machine
/// (no ghost detached state).
final class DetachedWindowController: NSWindow, NSWindowDelegate {
    let identityId: String
    let webView: WKWebView
    private let onClose: () -> Void
    /// Set for programmatic closes (reattach, teardown, identity close) where
    /// the user-close state writeback must not run.
    var suppressOnClose = false

    init(
        identityId: String,
        webView: WKWebView,
        contentSize: CGSize? = nil,
        onClose: @escaping () -> Void
    ) {
        self.identityId = identityId
        self.webView = webView
        self.onClose = onClose
        let size = contentSize ?? CGSize(width: 900, height: 640)
        let frame = CGRect(x: 120, y: 120, width: size.width, height: size.height)
        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.title = "Relay Desk — \(identityId.prefix(8))"
        self.isReleasedWhenClosed = false
        self.delegate = self
        webView.frame = self.contentView!.bounds
        webView.autoresizingMask = [.width, .height]
        self.contentView?.addSubview(webView)
    }

    func show() {
        NSApplication.shared.mainWindow?.addChildWindow(self, ordered: .above)
    }

    /// Pull the webView out before closing so registerWebView can reclaim it.
    func detachWebViewForReattach() {
        webView.removeFromSuperview()
    }

    func windowWillClose(_ notification: Notification) {
        if suppressOnClose { return }
        onClose()
    }
}

final class ProfiledWebViewFactory: NSObject, FlutterPlatformViewFactory {
    private let plugin: ProfiledWebViewPlugin

    init(plugin: ProfiledWebViewPlugin) {
        self.plugin = plugin
    }

    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        let dict = args as? [String: Any] ?? [:]
        let identityId: String
        if let id = dict["identityId"] as? String {
            identityId = id
        } else {
            // creationParams failing to decode would silently bind the view to
            // a random store; log it loudly instead of failing silently.
            NSLog("ProfiledWebView: missing identityId in creationParams; using random UUID (check createArgsCodec)")
            identityId = UUID().uuidString
        }
        let url = dict["url"] as? String
        // Missing isolationMode/fingerprint must degrade to the isolated
        // store and never reuse an existing view — fail toward isolation.
        let isolationMode = dict["isolationMode"] as? String ?? "nativeProfile"
        let fingerprint = dict["fingerprint"] as? String ?? ""
        // Device emulation: absent params degrade to the desktop surface
        // (default UA, no touch overrides, default detached window size).
        let userAgent = dict["userAgent"] as? String
        let touchEmulation = dict["touchEmulation"] as? Bool ?? false
        let viewportWidth = (dict["viewportWidth"] as? NSNumber)?.doubleValue
        let viewportHeight = (dict["viewportHeight"] as? NSNumber)?.doubleValue
        let viewportFollowsSurface = dict["viewportFollowsSurface"] as? Bool ?? false
        // Installs the bounded in-page error buffer (issue #17); absent/false
        // leaves the page JS environment untouched, as in non-automation
        // builds.
        let automationErrorCapture = dict["automationErrorCapture"] as? Bool ?? false
        return plugin.registerWebView(
            viewId: viewId,
            identityId: identityId,
            url: url,
            isolationMode: isolationMode,
            fingerprint: fingerprint,
            userAgent: userAgent,
            touchEmulation: touchEmulation,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            viewportFollowsSurface: viewportFollowsSurface,
            automationErrorCapture: automationErrorCapture
        )
    }

    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

/// Appends timestamped diagnostics lines to
/// `~/Library/Containers/<bundle>/Data/Library/Logs/RelayDesk/webview.log`
/// (falls back to the temp dir outside the sandbox). Covers WebView lifecycle,
/// navigation callbacks, watchdog fires and Dart-side breadcrumbs — the data
/// needed to explain "load hangs forever, stop does nothing, restart fixes
/// it" reports without attaching a debugger.
///
/// Lines are JSON objects so `jq`/`rg` can filter them; every line is also
/// mirrored to NSLog for `log stream`/Console.app. The file is truncated-rotated
/// at ~1 MB to `webview.log.old` so a noisy page can never grow it unboundedly.
final class DiagnosticsLog {
    static let shared = DiagnosticsLog()

    /// Absolute path of the active log file (nil if the file could not be
    /// opened — logs still go to NSLog in that case).
    private(set) var path: String?

    private let queue = DispatchQueue(label: "relaydesk.diagnostics-log")
    private var handle: FileHandle?
    private var fileURL: URL?
    private let maxBytes: UInt64 = 1_024 * 1_024

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .libraryDirectory, in: .userDomainMask).first
        let dir = base?
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("RelayDesk", isDirectory: true)
            ?? fm.temporaryDirectory.appendingPathComponent("RelayDesk", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("webview.log")
            if !fm.fileExists(atPath: file.path) {
                fm.createFile(atPath: file.path, contents: nil)
            }
            let h = try FileHandle(forWritingTo: file)
            h.seekToEndOfFile()
            fileURL = file
            handle = h
            path = file.path
            log("logOpened", fields: ["path": file.path])
        } catch {
            NSLog("RelayDesk DiagnosticsLog: cannot open log file: \(error)")
        }
    }

    /// Append one event line. Thread-safe; failures are swallowed (logging must
    /// never break the app it is diagnosing).
    func log(_ event: String, fields: [String: Any] = [:]) {
        queue.async {
            var entry: [String: Any] = [
                "ts": Self.timestamp(),
                "event": event,
            ]
            for (k, v) in fields { entry[k] = v }
            guard JSONSerialization.isValidJSONObject(entry),
                  let data = try? JSONSerialization.data(withJSONObject: entry),
                  let line = String(data: data, encoding: .utf8)
            else { return }
            NSLog("RelayDesk %@", line)
            self.rotateIfNeeded()
            if let lineData = (line + "\n").data(using: .utf8) {
                self.handle?.write(lineData)
            }
        }
    }

    private func rotateIfNeeded() {
        guard let h = handle, let file = fileURL else { return }
        guard (try? h.offset()) ?? 0 > maxBytes else { return }
        h.closeFile()
        let old = file.deletingLastPathComponent()
            .appendingPathComponent("webview.log.old")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: file, to: old)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        handle = try? FileHandle(forWritingTo: file)
        handle?.seekToEndOfFile()
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return f.string(from: Date())
    }
}
