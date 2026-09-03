import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerTrashChannel(flutterViewController)

    super.awakeFromNib()
  }

  /// `joycai/trash` — moves a path to the user's Trash through FileManager,
  /// which is the only route the sandbox allows. See `TrashService` on the
  /// Dart side for the other platforms.
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
        do {
          try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
          result(nil)
        } catch {
          result(FlutterError(code: "trash_failed", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
