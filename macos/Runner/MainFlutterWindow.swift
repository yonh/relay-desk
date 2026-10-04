import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private static let windowWidthDefaultsKey = "relayDesk.window.width"
  private static let windowHeightDefaultsKey = "relayDesk.window.height"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    restoreWindowSize()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidResize(_:)),
      name: NSWindow.didResizeNotification,
      object: self
    )

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Thin native adapter (ADR-0002): per-identity WKWebsiteDataStore(forIdentifier:)
    ProfiledWebViewPlugin.register(with: flutterViewController.registrar(forPlugin: "ProfiledWebView"))

    super.awakeFromNib()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func windowDidResize(_ notification: Notification) {
    let windowSize = frame.size
    UserDefaults.standard.set(windowSize.width, forKey: Self.windowWidthDefaultsKey)
    UserDefaults.standard.set(windowSize.height, forKey: Self.windowHeightDefaultsKey)
  }

  private func restoreWindowSize() {
    let defaults = UserDefaults.standard
    guard
      defaults.object(forKey: Self.windowWidthDefaultsKey) != nil,
      defaults.object(forKey: Self.windowHeightDefaultsKey) != nil
    else {
      return
    }

    let savedSize = NSSize(
      width: defaults.double(forKey: Self.windowWidthDefaultsKey),
      height: defaults.double(forKey: Self.windowHeightDefaultsKey)
    )
    guard savedSize.width.isFinite, savedSize.height.isFinite, savedSize.width > 0, savedSize.height > 0 else {
      return
    }

    var restoredSize = NSSize(
      width: max(savedSize.width, minSize.width),
      height: max(savedSize.height, minSize.height)
    )
    if let visibleSize = screen?.visibleFrame.size ?? NSScreen.main?.visibleFrame.size {
      restoredSize.width = min(restoredSize.width, visibleSize.width)
      restoredSize.height = min(restoredSize.height, visibleSize.height)
    }

    setFrame(NSRect(origin: frame.origin, size: restoredSize), display: false)
  }
}
