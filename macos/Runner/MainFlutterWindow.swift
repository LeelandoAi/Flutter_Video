import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var fullscreenObservers: [NSObjectProtocol] = []
  private var fullscreenStateObservers: [NSObjectProtocol] = []
  private var pendingFullscreenResult: FlutterResult?
  private var fullscreenTransitionTimeout: DispatchWorkItem?
  private var fullscreenChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let fullscreenChannel = FlutterMethodChannel(
      name: "flutter_video/fullscreen",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    self.fullscreenChannel = fullscreenChannel
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
        window.setFullscreen(true, result: result)
      case "exit":
        window.setFullscreen(false, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let center = NotificationCenter.default
    fullscreenStateObservers = [
      center.addObserver(
        forName: NSWindow.didEnterFullScreenNotification,
        object: self,
        queue: .main
      ) { [weak self] _ in
        self?.notifyFullscreenChanged(true)
      },
      center.addObserver(
        forName: NSWindow.didExitFullScreenNotification,
        object: self,
        queue: .main
      ) { [weak self] _ in
        self?.notifyFullscreenChanged(false)
      },
    ]

    super.awakeFromNib()
  }

  private func setFullscreen(_ fullscreen: Bool, result: @escaping FlutterResult) {
    if styleMask.contains(.fullScreen) == fullscreen {
      result(nil)
      return
    }
    guard pendingFullscreenResult == nil else {
      result(FlutterError(
        code: "fullscreen_transition_in_progress",
        message: "A fullscreen transition is already in progress.",
        details: nil))
      return
    }

    pendingFullscreenResult = result
    let center = NotificationCenter.default
    let completedNotification = fullscreen
      ? NSWindow.didEnterFullScreenNotification
      : NSWindow.didExitFullScreenNotification
    fullscreenObservers = [
      center.addObserver(
        forName: completedNotification,
        object: self,
        queue: .main
      ) { [weak self] _ in
        self?.finishFullscreenTransition()
      },
    ]
    let timeout = DispatchWorkItem { [weak self] in
      self?.finishFullscreenTransition(error: FlutterError(
        code: "fullscreen_transition_timeout",
        message: "The macOS fullscreen transition did not finish in time.",
        details: nil))
    }
    fullscreenTransitionTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
    toggleFullScreen(nil)
  }

  private func finishFullscreenTransition(error: FlutterError? = nil) {
    let center = NotificationCenter.default
    fullscreenObservers.forEach { center.removeObserver($0) }
    fullscreenObservers.removeAll()
    fullscreenTransitionTimeout?.cancel()
    fullscreenTransitionTimeout = nil
    let result = pendingFullscreenResult
    pendingFullscreenResult = nil
    result?(error)
  }

  private func notifyFullscreenChanged(_ fullscreen: Bool) {
    fullscreenChannel?.invokeMethod(
      "fullscreenChanged",
      arguments: ["fullscreen": fullscreen])
  }

  deinit {
    let center = NotificationCenter.default
    fullscreenObservers.forEach { center.removeObserver($0) }
    fullscreenStateObservers.forEach { center.removeObserver($0) }
    fullscreenTransitionTimeout?.cancel()
  }
}
