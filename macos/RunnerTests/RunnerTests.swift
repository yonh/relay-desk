import Cocoa
import FlutterMacOS
import WebKit
import XCTest

@testable import relay_desk

/// Native-level regression tests for the Shared Session isolation fix
/// (.scratch/shared-session/issues/01 + 02).
///
/// These exercise the real `registerWebView` creation path — the same entry
/// the AppKitView factory calls — and assert which WKWebsiteDataStore each
/// identity's WKWebView ends up with:
///
///   - sharedSession views share `WKWebsiteDataStore.default()` (persistent,
///     NOT isolated — per ADR-0002 and the identity contract);
///   - nativeProfile views get distinct persistent
///     `WKWebsiteDataStore(forIdentifier:)` per identity UUID;
///   - changing isolationMode (fingerprint change) must NOT reuse the old
///     WebView/store;
///   - a stale async `close` must not clobber the re-registered view.
// @MainActor: WKWebView/WKWebsiteDataStore/WKHTTPCookieStore access off the
// main thread trips libMainThreadChecker (SIGABRT) under hosted tests.
@MainActor
final class RunnerTests: XCTestCase {
    private var plugin: ProfiledWebViewPlugin!

    override func setUp() {
        super.setUp()
        plugin = ProfiledWebViewPlugin()
    }

    private func store(ofViewId viewId: Int64) -> WKWebsiteDataStore {
        guard let webView = plugin.webViews[viewId] else {
            XCTFail("no webView for viewId \(viewId)")
            return WKWebsiteDataStore.nonPersistent()
        }
        return webView.configuration.websiteDataStore
    }

    private func call(_ method: String, _ args: [String: Any]) {
        plugin.handle(FlutterMethodCall(methodName: method, arguments: args)) { _ in }
    }

    // MARK: Ticket 01 — Shared Session shares the default persistent store

    func testSharedSessionViewsShareTheDefaultStore() {
        let a = UUID().uuidString
        let b = UUID().uuidString
        plugin.registerWebView(viewId: 1, identityId: a, url: nil, isolationMode: "sharedSession", fingerprint: "fa")
        plugin.registerWebView(viewId: 2, identityId: b, url: nil, isolationMode: "sharedSession", fingerprint: "fb")

        XCTAssertTrue(store(ofViewId: 1) === WKWebsiteDataStore.default())
        XCTAssertTrue(store(ofViewId: 2) === WKWebsiteDataStore.default())
        XCTAssertTrue(WKWebsiteDataStore.default().isPersistent)
        XCTAssertEqual(plugin.identityStoreKinds[a], .shared)
        XCTAssertEqual(plugin.identityStoreKinds[b], .shared)
        // Shared identities must NOT get per-identity stores.
        XCTAssertNil(plugin.dataStores[a])
        XCTAssertNil(plugin.dataStores[b])
    }

    func testNativeProfileViewsGetDistinctPersistentStores() {
        let a = UUID().uuidString
        let b = UUID().uuidString
        plugin.registerWebView(viewId: 1, identityId: a, url: nil, isolationMode: "nativeProfile", fingerprint: "fa")
        plugin.registerWebView(viewId: 2, identityId: b, url: nil, isolationMode: "nativeProfile", fingerprint: "fb")

        let storeA = store(ofViewId: 1)
        let storeB = store(ofViewId: 2)
        XCTAssertFalse(storeA === storeB)
        XCTAssertFalse(storeA === WKWebsiteDataStore.default())
        XCTAssertTrue(storeA.isPersistent && storeB.isPersistent)
        if #available(macOS 14.0, *) {
            XCTAssertEqual(storeA.identifier, UUID(uuidString: a))
            XCTAssertEqual(storeB.identifier, UUID(uuidString: b))
        }
        XCTAssertEqual(plugin.identityStoreKinds[a], .perIdentity)
        XCTAssertNotNil(plugin.dataStores[a])
        XCTAssertNotNil(plugin.dataStores[b])
    }

    func testMissingIsolationModeFallsBackToPerIdentityStore() {
        // Factory-level behaviour: no isolationMode must NOT silently share.
        let id = UUID().uuidString
        plugin.registerWebView(viewId: 1, identityId: id, url: nil, isolationMode: "nativeProfile", fingerprint: "f")
        XCTAssertEqual(ProfiledWebViewPlugin.storeKind(for: nil), .perIdentity)
        XCTAssertEqual(ProfiledWebViewPlugin.storeKind(for: "bogus"), .perIdentity)
        XCTAssertEqual(ProfiledWebViewPlugin.storeKind(for: "sharedSession"), .shared)
    }

    // MARK: Ticket 02 — mode switch / reuse / stale close

    func testReparentReusesWebViewWhenFingerprintMatches() {
        let id = UUID().uuidString
        plugin.registerWebView(viewId: 1, identityId: id, url: nil, isolationMode: "nativeProfile", fingerprint: "f1")
        let original = plugin.webViews[1]

        // Same fingerprint → Focus reparent reuses the live view.
        plugin.registerWebView(viewId: 2, identityId: id, url: nil, isolationMode: "nativeProfile", fingerprint: "f1")
        XCTAssertTrue(plugin.webViews[2] === original)
        XCTAssertNil(plugin.webViews[1])
        XCTAssertEqual(plugin.viewIdByIdentity[id], 2)
    }

    func testModeSwitchDoesNotReuseOldStore() {
        let id = UUID().uuidString
        plugin.registerWebView(viewId: 1, identityId: id, url: nil, isolationMode: "sharedSession", fingerprint: "f1")
        let sharedView = plugin.webViews[1]
        XCTAssertTrue(store(ofViewId: 1) === WKWebsiteDataStore.default())

        // Switch to nativeProfile: new fingerprint must NOT reuse the old
        // shared-store view.
        plugin.registerWebView(viewId: 2, identityId: id, url: nil, isolationMode: "nativeProfile", fingerprint: "f2")
        XCTAssertFalse(plugin.webViews[2] === sharedView!)
        XCTAssertFalse(store(ofViewId: 2) === WKWebsiteDataStore.default())
        XCTAssertEqual(plugin.identityStoreKinds[id], .perIdentity)
        if #available(macOS 14.0, *) {
            XCTAssertEqual(store(ofViewId: 2).identifier, UUID(uuidString: id))
        }
    }

    func testSwitchingBackRestoresTheSamePerIdentityStore() {
        let id = UUID().uuidString
        plugin.registerWebView(viewId: 1, identityId: id, url: nil, isolationMode: "nativeProfile", fingerprint: "f1")
        let original = store(ofViewId: 1)

        plugin.registerWebView(viewId: 2, identityId: id, url: nil, isolationMode: "sharedSession", fingerprint: "f2")
        XCTAssertTrue(store(ofViewId: 2) === WKWebsiteDataStore.default())

        plugin.registerWebView(viewId: 3, identityId: id, url: nil, isolationMode: "nativeProfile", fingerprint: "f1")
        let restored = store(ofViewId: 3)
        XCTAssertFalse(restored === WKWebsiteDataStore.default())
        if #available(macOS 14.0, *) {
            // Same identity UUID → same persistent on-disk store (old data
            // readable again; the switch must not migrate or merge data).
            XCTAssertEqual(restored.identifier, original.identifier)
        }
    }

    func testStaleCloseDoesNotDropTheReRegisteredView() {
        let id = UUID().uuidString
        plugin.registerWebView(viewId: 1, identityId: id, url: nil, isolationMode: "nativeProfile", fingerprint: "f1")
        // Re-register under a new viewId (config-change rebuild path).
        plugin.registerWebView(viewId: 2, identityId: id, url: nil, isolationMode: "nativeProfile", fingerprint: "f1")
        let liveView = plugin.webViews[2]

        // A delayed close for the OLD viewId arrives after re-registration.
        // It must not drop the new mapping or the new view.
        call("close", ["viewId": 1, "identityId": id])
        XCTAssertEqual(plugin.viewIdByIdentity[id], 2)
        XCTAssertTrue(plugin.webViews[2] === liveView)
        XCTAssertTrue(plugin.webViews[2]!.superview === plugin.containers[2])
    }

    func testIdentityScopedCloseResolvesToCurrentView() {
        let id = UUID().uuidString
        plugin.registerWebView(viewId: 5, identityId: id, url: nil, isolationMode: "nativeProfile", fingerprint: "f1")

        // A close that carries no viewId (Dart had no mapping yet — e.g. the
        // close raced in between native register and Dart registerView) must
        // tear down the CURRENT view and its mapping, not bypass the guard
        // and orphan a live WebView.
        call("close", ["identityId": id])
        XCTAssertNil(plugin.viewIdByIdentity[id])
        XCTAssertNil(plugin.webViews[5])
        XCTAssertNil(plugin.containers[5])
    }

    func testDetachAttachPreservesSharedStore() {
        let id = UUID().uuidString
        plugin.registerWebView(viewId: 1, identityId: id, url: nil, isolationMode: "sharedSession", fingerprint: "f1")
        let original = plugin.webViews[1]!
        let container = plugin.containers[1]!

        call("detach", ["identityId": id])
        XCTAssertNotNil(plugin.detachedWindows[id])

        call("attach", ["identityId": id])
        XCTAssertNil(plugin.detachedWindows[id])
        // Same WebView instance reseated into the still-alive container,
        // still on the shared store.
        XCTAssertTrue(plugin.webViews[1] === original)
        XCTAssertTrue(original.superview === container)
        XCTAssertTrue(original.configuration.websiteDataStore === WKWebsiteDataStore.default())
        XCTAssertEqual(plugin.viewIdByIdentity[id], 1)
    }

    // MARK: Store-level cookie sharing across views

    func testSharedSessionCookieVisibleFromAnotherSharedIdentity() async throws {
        let a = UUID().uuidString
        let b = UUID().uuidString
        let iso = UUID().uuidString
        plugin.registerWebView(viewId: 1, identityId: a, url: nil, isolationMode: "sharedSession", fingerprint: "fa")
        plugin.registerWebView(viewId: 2, identityId: b, url: nil, isolationMode: "sharedSession", fingerprint: "fb")
        plugin.registerWebView(viewId: 3, identityId: iso, url: nil, isolationMode: "nativeProfile", fingerprint: "fi")

        let domain = "127.0.0.1"
        let cookieName = "rd_shared_\(UUID().uuidString.prefix(8))"
        guard
            let cookie = HTTPCookie(properties: [
                .domain: domain,
                .path: "/",
                .name: cookieName,
                .value: "v1",
            ])
        else {
            XCTFail("could not build HTTPCookie for domain \(domain)")
            return
        }

        // Write into A's store, read from B's store — they are the same
        // shared default store. The cookie store write→read propagation is
        // async (a separate daemon backs WKHTTPCookieStore), so poll briefly
        // rather than asserting on a single read.
        let storeA = store(ofViewId: 1)
        try await storeA.httpCookieStore.setCookie(cookie)
        let bSeesIt = await pollCookies(store: store(ofViewId: 2), name: cookieName)
        XCTAssertTrue(bSeesIt, "shared session B must see the cookie written via shared identity A")

        // The isolated identity must never see it (poll it too — absence on
        // the first read could just be propagation lag).
        let isoSeesIt = await pollCookies(store: store(ofViewId: 3), name: cookieName)
        XCTAssertFalse(isoSeesIt, "isolated identity must not see the shared cookie")

        await delete(cookie: cookie, from: WKWebsiteDataStore.default())
    }

    /// Polls the cookie store up to ~2s for a cookie by name.
    private func pollCookies(store: WKWebsiteDataStore, name: String) async -> Bool {
        for _ in 0..<20 {
            let cookies = await allCookies(of: store)
            if cookies.contains(where: { $0.name == name }) { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    private func allCookies(of store: WKWebsiteDataStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
    }

    private func delete(cookie: HTTPCookie, from store: WKWebsiteDataStore) async {
        await withCheckedContinuation { continuation in
            store.httpCookieStore.delete(cookie) { continuation.resume() }
        }
    }

    // MARK: Device emulation (UA / touch surface / detached viewport)

    func testUserAgentParamAppliesCustomUserAgent() {
        let id = UUID().uuidString
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Test"
        plugin.registerWebView(
            viewId: 1, identityId: id, url: nil,
            isolationMode: "nativeProfile", fingerprint: "f",
            userAgent: ua
        )
        XCTAssertEqual(plugin.webViews[1]?.customUserAgent, ua)
    }

    func testAbsentUserAgentKeepsTheDefaultUA() {
        let id = UUID().uuidString
        plugin.registerWebView(
            viewId: 1, identityId: id, url: nil,
            isolationMode: "nativeProfile", fingerprint: "f"
        )
        // Desktop surface: no override applied. WKWebView reports its
        // built-in UA via customUserAgent (non-nil), so assert it carries no
        // mobile markers rather than asserting nil.
        XCTAssertFalse(
            plugin.webViews[1]?.customUserAgent?.contains("iPhone") ?? false
        )
        XCTAssertFalse(
            plugin.webViews[1]?.customUserAgent?.contains("Android") ?? false
        )
    }

    func testTouchEmulationAddsDocumentStartUserScript() {
        let id = UUID().uuidString
        plugin.registerWebView(
            viewId: 1, identityId: id, url: nil,
            isolationMode: "nativeProfile", fingerprint: "f",
            touchEmulation: true
        )
        let scripts = plugin.webViews[1]!.configuration.userContentController.userScripts
        XCTAssertTrue(
            scripts.contains { $0.source.contains("maxTouchPoints") },
            "touchEmulation must inject the maxTouchPoints override script"
        )
    }

    func testTouchEmulationOffAddsNoOverrideScript() {
        let id = UUID().uuidString
        plugin.registerWebView(
            viewId: 1, identityId: id, url: nil,
            isolationMode: "nativeProfile", fingerprint: "f",
            touchEmulation: false
        )
        let scripts = plugin.webViews[1]!.configuration.userContentController.userScripts
        XCTAssertFalse(
            scripts.contains { $0.source.contains("maxTouchPoints") },
            "desktop preset must not inject the touch override script"
        )
    }

    func testViewportSizeRecordedForDetachAndClearedForDesktop() {
        let id = UUID().uuidString
        plugin.registerWebView(
            viewId: 1, identityId: id, url: nil,
            isolationMode: "nativeProfile", fingerprint: "f1",
            viewportWidth: 393, viewportHeight: 852
        )
        XCTAssertEqual(plugin.identityViewports[id], CGSize(width: 393, height: 852))

        // Rebuild under a desktop preset (fingerprint change): the recorded
        // viewport must not leak into the new detached-window sizing.
        plugin.registerWebView(
            viewId: 2, identityId: id, url: nil,
            isolationMode: "nativeProfile", fingerprint: "f2"
        )
        XCTAssertNil(plugin.identityViewports[id])
    }
}
