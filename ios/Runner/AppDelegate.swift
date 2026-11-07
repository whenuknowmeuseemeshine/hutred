import Flutter
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var widgetChannel: FlutterMethodChannel?
  private var widgetReady = false
  private var pendingCommands: [String] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Кнопки виджета (iOS 17+) присылают команды сюда.
    NotificationCenter.default.addObserver(
      forName: .hutredWidgetCommand, object: nil, queue: .main
    ) { [weak self] note in
      guard let self = self, let cmd = note.object as? String else { return }
      self.pendingCommands.append(cmd)
      self.flushWidgetCommands()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HutredWidget") else { return }
    let channel = FlutterMethodChannel(name: "hutred/widget", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "dir":
        guard let url = HutredGroup.folder else {
          result(nil)
          return
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        result(url.path)
      case "refresh":
        WidgetCenter.shared.reloadAllTimelines()
        result(nil)
      case "ready":
        self?.widgetReady = true
        self?.flushWidgetCommands()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    widgetChannel = channel
  }

  private func flushWidgetCommands() {
    guard widgetReady, let channel = widgetChannel else { return }
    for cmd in pendingCommands {
      channel.invokeMethod("command", arguments: cmd)
    }
    pendingCommands.removeAll()
  }
}
