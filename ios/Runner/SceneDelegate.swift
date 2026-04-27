import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private let speechRecognitionService = SpeechRecognitionService()
  private let launchRouteStreamHandler = LaunchRouteStreamHandler()
  private var voiceChannelsConfigured = false
  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private let methodChannelName = "journal_intelligence/voice_entry"
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

    self.methodChannel = methodChannel
    self.eventChannel = eventChannel
    self.launchRouteEventChannel = launchRouteEventChannel
    voiceChannelsConfigured = true
  }

  private func handleURLContexts(_ contexts: Set<UIOpenURLContext>) {
    for context in contexts {
      launchRouteStreamHandler.emit(url: context.url)
    }
  }
}
