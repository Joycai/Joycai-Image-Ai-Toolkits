import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var nativeMenus: NativeMenus?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    DirectoryAccess.shared.register(flutterViewController)
    CredentialProtection.register(flutterViewController)
    registerTrashChannel(flutterViewController)
    registerDockBadgeChannel(flutterViewController)
    nativeMenus = NativeMenus(controller: flutterViewController, window: self)

    super.awakeFromNib()
  }

  /// AppKit supplies the standard system badge appearance on the app icon.
  private func registerDockBadgeChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "joycai/dock_badge", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "setCount" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let count = call.arguments as? Int, count >= 0 else {
        result(FlutterError(code: "bad_args", message: "nonnegative count required", details: nil))
        return
      }
      NSApplication.shared.dockTile.badgeLabel = count > 0 ? String(count) : nil
      result(nil)
    }
  }

  /// `joycai/trash` — recycles through the workspace, using Finder's trash
  /// behavior instead of FileManager's direct volume trash lookup.
  private func registerTrashChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "joycai/trash", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isSupported":
        result(true)
      case "trash":
        guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String
        else {
          result(FlutterError(code: "bad_args", message: "path missing", details: nil))
          return
        }
        // Start on an active dispatch queue so the completion returns on that
        // same queue, as required by NSWorkspace and Flutter's platform channel.
        DispatchQueue.main.async {
          NSWorkspace.shared.recycle([URL(fileURLWithPath: path)]) { _, error in
            if let error = error {
              result(FlutterError(
                code: "trash_failed", message: error.localizedDescription, details: nil))
            } else {
              result(nil)
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// Preserve the XIB's responder-chain editing, Services and window commands.
/// Only application navigation is dispatched into Flutter.
private class NativeMenus: NSObject, NSMenuItemValidation, NSMenuDelegate {
  private let channel: FlutterMethodChannel
  private var commands: [String: NSMenuItem] = [:]
  private var enabledCommands: Set<String> = []
  private var undoItems: [String: NSMenuItem] = [:]
  private var undoState: [String: Bool] = [:]
  private weak var window: NSWindow?

  init(controller: FlutterViewController, window: NSWindow) {
    self.window = window
    channel = FlutterMethodChannel(
      name: "joycai/native_menu", binaryMessenger: controller.engine.binaryMessenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "update":
        guard let args = call.arguments as? [String: Any],
          let labels = args["labels"] as? [String: String],
          let entries = args["commands"] as? [[String: Any]],
          let menu = NSApp.mainMenu
        else {
          result(FlutterError(code: "bad_args", message: "Menu payload missing", details: nil))
          return
        }
        self.update(menu: menu, labels: labels, entries: entries)
        result(nil)
      case "disable":
        self.enabledCommands.removeAll()
        for item in self.commands.values { item.isEnabled = false }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func update(menu: NSMenu, labels: [String: String], entries: [[String: Any]]) {
    var indexed: [String: NSMenuItem] = [:]
    func visit(_ menu: NSMenu) {
      for item in menu.items {
        if let id = item.identifier?.rawValue {
          indexed[id] = item
          if let label = labels[id] {
            item.title = label
            item.submenu?.title = label
          }
        }
        if let submenu = item.submenu { visit(submenu) }
      }
    }
    visit(menu)
    // Flutter's UndoHistory owns the text history, but its system UndoManager
    // integration is iOS-only. Query the focused client when Edit opens.
    if !(menu is NativeApplicationMenu) {
      let root = NativeApplicationMenu(title: menu.title)
      for item in menu.items {
        menu.removeItem(item)
        root.addItem(item)
      }
      root.onUndo = { [weak self] direction in
        self?.channel.invokeMethod("command", arguments: direction)
      }
      root.canHandleUndo = { [weak self] in
        guard let window = self?.window else { return false }
        return NSApp.keyWindow === window
      }
      NSApp.mainMenu = root
    }
    indexed["5QF-Oa-p0T"]?.submenu?.delegate = self
    for (id, direction) in [("dRJ-4n-Yzg", "undo"), ("6dh-zS-Vam", "redo")] {
      if let item = indexed[id] {
        item.target = self
        item.action = #selector(invokeUndo(_:))
        item.representedObject = direction
        undoItems[direction] = item
      }
    }
    enabledCommands.removeAll()
    var destinationIndex = 0
    for entry in entries {
      guard let id = entry["id"] as? String, let label = entry["label"] as? String,
        let key = entry["key"] as? String else { continue }
      let item: NSMenuItem
      if let existing = commands[id] {
        item = existing
      } else if id == "openSettings", let settings = indexed["BOF-NM-1cW"] {
        item = settings
      } else {
        item = NSMenuItem(title: label, action: #selector(invoke(_:)), keyEquivalent: key)
        if id.hasPrefix("destination:"), let view = indexed["H8h-7b-M4v"]?.submenu {
          view.insertItem(item, at: destinationIndex)
        } else if id == "showShortcutPanel", let help = indexed["EPT-qC-fAb"]?.submenu {
          help.addItem(item)
        } else { continue }
      }
      if id.hasPrefix("destination:") { destinationIndex += 1 }
      item.title = label
      item.action = #selector(invoke(_:))
      item.target = self
      item.representedObject = id
      item.keyEquivalent = key
      var modifiers: NSEvent.ModifierFlags = []
      if entry["command"] as? Bool == true { modifiers.insert(.command) }
      if entry["shift"] as? Bool == true { modifiers.insert(.shift) }
      if entry["option"] as? Bool == true { modifiers.insert(.option) }
      item.keyEquivalentModifierMask = modifiers
      if entry["enabled"] as? Bool == true { enabledCommands.insert(id) }
      item.isEnabled = enabledCommands.contains(id)
      commands[id] = item
    }
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    guard let window = window, NSApp.keyWindow === window else { return false }
    guard let id = menuItem.representedObject as? String else { return false }
    if id == "undo" || id == "redo" { return undoState[id] ?? false }
    return enabledCommands.contains(id)
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    channel.invokeMethod("undoState", arguments: nil) { [weak self] response in
      guard let self = self, let state = response as? [String: Bool] else { return }
      self.undoState = state
      for (id, item) in self.undoItems { item.isEnabled = state[id] ?? false }
    }
  }

  @objc private func invokeUndo(_ sender: NSMenuItem) {
    guard validateMenuItem(sender), let direction = sender.representedObject as? String else { return }
    channel.invokeMethod("command", arguments: direction)
  }

  @objc private func invoke(_ sender: NSMenuItem) {
    guard validateMenuItem(sender), let id = sender.representedObject as? String else { return }
    channel.invokeMethod("command", arguments: id)
  }
}

private class NativeApplicationMenu: NSMenu {
  var onUndo: ((String) -> Void)?
  var canHandleUndo: (() -> Bool)?

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
    if canHandleUndo?() == true, event.charactersIgnoringModifiers?.lowercased() == "z",
      modifiers == [.command] || modifiers == [.command, .shift] {
      // History can change since Edit was last opened. Dispatch to the current
      // Flutter client; it safely ignores undo/redo when its stack is empty.
      onUndo?(modifiers.contains(.shift) ? "redo" : "undo")
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}
