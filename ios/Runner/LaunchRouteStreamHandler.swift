import Flutter
import Foundation

final class LaunchRouteStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var pendingRoutes: [String] = []

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    flushPendingRoutes()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func emit(url: URL) {
    let route = url.absoluteString
    guard !route.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    if let eventSink {
      eventSink(route)
    } else {
      pendingRoutes.append(route)
    }
  }

  private func flushPendingRoutes() {
    guard let eventSink else { return }
    pendingRoutes.forEach { eventSink($0) }
    pendingRoutes.removeAll()
  }
}
