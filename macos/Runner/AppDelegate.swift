import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var iconChannel: FlutterMethodChannel?
  private var selectedIcon = "B2"
  private var dockMenuTitle = "Switch Icon"
  private var restoreTitle = "Restore B2 default"
  private var errorTitle = "Could not update the icon. Please try again."
  private var iconChoices: [(id: String, title: String, image: NSImage)] = []
  private var changingIcon = false

  func configureIconChannel(_ channel: FlutterMethodChannel) {
    iconChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      guard let arguments = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_icon", message: "Missing icon arguments", details: nil))
        return
      }
      switch call.method {
      case "setIcon":
        guard let id = arguments["id"] as? String,
          ["A1", "A2", "B1", "B2", "C1", "C3"].contains(id),
          let png = arguments["png"] as? FlutterStandardTypedData,
          let image = NSImage(data: png.data)
        else {
          result(FlutterError(code: "invalid_icon", message: "Invalid PNG icon", details: nil))
          return
        }
        NSApplication.shared.applicationIconImage = image
        self.selectedIcon = id
        result(nil)
      case "configureDockMenu":
        guard let title = arguments["title"] as? String,
          let choices = arguments["choices"] as? [[String: Any]] else {
          result(FlutterError(code: "invalid_menu", message: "Invalid Dock menu", details: nil))
          return
        }
        self.dockMenuTitle = title
        self.restoreTitle = arguments["restoreTitle"] as? String ?? self.restoreTitle
        self.errorTitle = arguments["errorTitle"] as? String ?? self.errorTitle
        self.iconChoices = choices.compactMap { choice in
          guard let id = choice["id"] as? String,
            let title = choice["title"] as? String,
            let png = choice["png"] as? FlutterStandardTypedData,
            let image = NSImage(data: png.data) else { return nil }
          image.size = NSSize(width: 24, height: 24)
          return (id: id, title: title, image: image)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    guard !iconChoices.isEmpty else { return nil }
    let menu = NSMenu()
    let parent = NSMenuItem(title: dockMenuTitle, action: nil, keyEquivalent: "")
    let choices = NSMenu(title: dockMenuTitle)
    choices.autoenablesItems = false
    for choice in iconChoices {
      let item = NSMenuItem(title: choice.title, action: #selector(selectDockIcon(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = choice.id
      item.image = choice.image
      item.state = choice.id == selectedIcon ? .on : .off
      item.isEnabled = !changingIcon
      choices.addItem(item)
    }
    choices.addItem(.separator())
    let restore = NSMenuItem(title: restoreTitle, action: #selector(selectDockIcon(_:)), keyEquivalent: "")
    restore.target = self
    restore.representedObject = "B2"
    restore.isEnabled = !changingIcon && selectedIcon != "B2"
    choices.addItem(restore)
    parent.submenu = choices
    menu.addItem(parent)
    return menu
  }

  @objc private func selectDockIcon(_ sender: NSMenuItem) {
    guard !changingIcon, let id = sender.representedObject as? String,
      let channel = iconChannel else { return }
    changingIcon = true
    channel.invokeMethod("selectIcon", arguments: ["id": id]) { [weak self] response in
      guard let self = self else { return }
      self.changingIcon = false
      if (response as? Bool) != true {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = self.errorTitle
        alert.runModal()
      }
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
