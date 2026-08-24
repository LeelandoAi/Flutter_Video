import Cocoa
import FlutterMacOS

public class LeeVideoPlugin: NSObject, FlutterPlugin {
  private let registrar: FlutterPluginRegistrar
  private let channel: FlutterMethodChannel
  private var transitionObservers: [NSObjectProtocol] = []
  private var stateObservers: [NSObjectProtocol] = []
  private var pendingResult: FlutterResult?
  private var transitionTimeout: DispatchWorkItem?

  private var window: NSWindow? {
    registrar.view?.window
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "lee_video/fullscreen",
      binaryMessenger: registrar.messenger)
    let instance = LeeVideoPlugin(registrar: registrar, channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.observeFullscreenState()
  }

  init(registrar: FlutterPluginRegistrar, channel: FlutterMethodChannel) {
    self.registrar = registrar
    self.channel = channel
    super.init()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let window else {
      result(FlutterError(
        code: "window_unavailable",
        message: "The Flutter host window is not available.",
        details: nil))
      return
    }

    switch call.method {
    case "enter":
      setFullscreen(true, window: window, result: result)
    case "exit":
      setFullscreen(false, window: window, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func observeFullscreenState() {
    let center = NotificationCenter.default
    stateObservers = [
      center.addObserver(
        forName: NSWindow.didEnterFullScreenNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        self?.notifyIfHostWindow(notification, fullscreen: true)
      },
      center.addObserver(
        forName: NSWindow.didExitFullScreenNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        self?.notifyIfHostWindow(notification, fullscreen: false)
      },
    ]
  }

  private func notifyIfHostWindow(_ notification: Notification, fullscreen: Bool) {
    guard let window, notification.object as? NSWindow === window else {
      return
    }
    channel.invokeMethod(
      "fullscreenChanged",
      arguments: ["fullscreen": fullscreen])
  }

  private func setFullscreen(
    _ fullscreen: Bool,
    window: NSWindow,
    result: @escaping FlutterResult
  ) {
    if window.styleMask.contains(.fullScreen) == fullscreen {
      result(nil)
      return
    }
    guard pendingResult == nil else {
      result(FlutterError(
        code: "fullscreen_transition_in_progress",
        message: "A fullscreen transition is already in progress.",
        details: nil))
      return
    }

    pendingResult = result
    let center = NotificationCenter.default
    let completedNotification = fullscreen
      ? NSWindow.didEnterFullScreenNotification
      : NSWindow.didExitFullScreenNotification
    transitionObservers = [
      center.addObserver(
        forName: completedNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        self?.finishTransition()
      },
    ]

    let timeout = DispatchWorkItem { [weak self] in
      self?.finishTransition(error: FlutterError(
        code: "fullscreen_transition_timeout",
        message: "The macOS fullscreen transition did not finish in time.",
        details: nil))
    }
    transitionTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
    window.toggleFullScreen(nil)
  }

  private func finishTransition(error: FlutterError? = nil) {
    let center = NotificationCenter.default
    transitionObservers.forEach { center.removeObserver($0) }
    transitionObservers.removeAll()
    transitionTimeout?.cancel()
    transitionTimeout = nil
    let result = pendingResult
    pendingResult = nil
    result?(error)
  }

  deinit {
    let center = NotificationCenter.default
    transitionObservers.forEach { center.removeObserver($0) }
    stateObservers.forEach { center.removeObserver($0) }
    transitionTimeout?.cancel()
  }
}
