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
