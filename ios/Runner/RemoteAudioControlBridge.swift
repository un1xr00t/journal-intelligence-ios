import Flutter
import MediaPlayer
import UIKit

final class RemoteAudioControlBridge: NSObject, FlutterStreamHandler {
  static let shared = RemoteAudioControlBridge()

  private var eventSink: FlutterEventSink?
  private var handlersConfigured = false

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "updateNowPlaying":
      updateNowPlaying(call.arguments)
      result(nil)
    case "clearNowPlaying":
      clearNowPlaying()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    configureRemoteCommandsIfNeeded()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func configureRemoteCommandsIfNeeded() {
    guard !handlersConfigured else { return }
    handlersConfigured = true

    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.isEnabled = true
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.skipBackwardCommand.isEnabled = true
    commandCenter.skipForwardCommand.isEnabled = true
    commandCenter.skipBackwardCommand.preferredIntervals = [15]
    commandCenter.skipForwardCommand.preferredIntervals = [15]
    commandCenter.previousTrackCommand.isEnabled = false
    commandCenter.nextTrackCommand.isEnabled = false

    commandCenter.playCommand.addTarget { [weak self] _ in
      self?.emit(action: "play")
      return .success
    }
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      self?.emit(action: "pause")
      return .success
    }
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.emit(action: "togglePlayPause")
      return .success
    }
    commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
      self?.emit(action: "skipBackward")
      return .success
    }
    commandCenter.skipForwardCommand.addTarget { [weak self] _ in
      self?.emit(action: "skipForward")
      return .success
    }
  }

  private func updateNowPlaying(_ rawArguments: Any?) {
    configureRemoteCommandsIfNeeded()
    UIApplication.shared.beginReceivingRemoteControlEvents()

    guard let arguments = rawArguments as? [String: Any] else { return }
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    info[MPMediaItemPropertyTitle] =
      (arguments["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? "Journal Intelligence"
    if let subtitle = (arguments["subtitle"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines), !subtitle.isEmpty {
      info[MPMediaItemPropertyArtist] = subtitle
    }
    if let duration = arguments["duration"] as? Double, duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    if let elapsed = arguments["elapsed"] as? Double, elapsed >= 0 {
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
    }
    let isPlaying = arguments["isPlaying"] as? Bool ?? false
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func clearNowPlaying() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    UIApplication.shared.endReceivingRemoteControlEvents()
  }

  private func emit(action: String) {
    guard let eventSink else { return }
    DispatchQueue.main.async {
      eventSink(["action": action])
    }
  }
}
