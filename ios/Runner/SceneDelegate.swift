import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private static let launchRouteActivityType =
    "name.williamthomas.journalIntelligence.route"
  private static let launchRouteUserInfoKey = "route"
  private let speechRecognitionService = SpeechRecognitionService()
  private let launchRouteStreamHandler = LaunchRouteStreamHandler.shared
  private let notificationBridge = NotificationBridge.shared
  private var voiceChannelsConfigured = false
  private var methodChannel: FlutterMethodChannel?
  private var notificationMethodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private let methodChannelName = "journal_intelligence/voice_entry"
  private let notificationMethodChannelName = "journal_intelligence/notifications"
  private let eventChannelName = "journal_intelligence/voice_entry/events"
  private var launchRouteEventChannel: FlutterEventChannel?
  private let launchRouteEventChannelName =
    "journal_intelligence/launch_route/events"

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    configureVoiceChannelsIfNeeded()
    handleURLContexts(connectionOptions.urlContexts)
    handleUserActivities(connectionOptions.userActivities)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    configureVoiceChannelsIfNeeded()
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    super.scene(scene, openURLContexts: URLContexts)
    handleURLContexts(URLContexts)
  }

  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    super.scene(scene, continue: userActivity)
    handleUserActivity(userActivity)
  }

  private func configureVoiceChannelsIfNeeded() {
    guard !voiceChannelsConfigured,
          let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    let launchRouteEventChannel = FlutterEventChannel(
      name: launchRouteEventChannelName,
      binaryMessenger: controller.binaryMessenger
    )

    eventChannel.setStreamHandler(speechRecognitionService)
    launchRouteEventChannel.setStreamHandler(launchRouteStreamHandler)
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "voice_unavailable",
            message: "Voice capture is unavailable right now.",
            details: nil
          )
        )
        return
      }

      switch call.method {
      case "start":
        self.speechRecognitionService.start(result: result)
      case "stop":
        self.speechRecognitionService.stop()
        result(nil)
      case "cancel":
        self.speechRecognitionService.cancel()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let notificationMethodChannel = FlutterMethodChannel(
      name: notificationMethodChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    notificationMethodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "notifications_unavailable",
            message: "Notifications are unavailable right now.",
            details: nil
          )
        )
        return
      }

      self.notificationBridge.handle(call, result: result)
    }

    self.methodChannel = methodChannel
    self.notificationMethodChannel = notificationMethodChannel
    self.eventChannel = eventChannel
    self.launchRouteEventChannel = launchRouteEventChannel
    voiceChannelsConfigured = true
  }

  private func handleURLContexts(_ contexts: Set<UIOpenURLContext>) {
    for context in contexts {
      launchRouteStreamHandler.emit(url: context.url)
    }
  }

  private func handleUserActivities(_ userActivities: Set<NSUserActivity>) {
    for userActivity in userActivities {
      handleUserActivity(userActivity)
    }
  }

  private func handleUserActivity(_ userActivity: NSUserActivity) {
    guard userActivity.activityType == Self.launchRouteActivityType,
          let route = userActivity.userInfo?[Self.launchRouteUserInfoKey] as? String else {
      return
    }

    launchRouteStreamHandler.emit(route: route)
  }
}
