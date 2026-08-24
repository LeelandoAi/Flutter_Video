import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let fullscreenChannel = FlutterMethodChannel(
      name: "flutter_video/fullscreen",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    fullscreenChannel.setMethodCallHandler { [weak self] call, result in
      guard let window = self else {
        result(FlutterError(
          code: "window_unavailable",
          message: "Main window is not available.",
          details: nil))
        return
      }
      switch call.method {
      case "enter":
        if !window.styleMask.contains(.fullScreen) {
          window.toggleFullScreen(nil)
        }
        result(nil)
      case "exit":
        if window.styleMask.contains(.fullScreen) {
          window.toggleFullScreen(nil)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
