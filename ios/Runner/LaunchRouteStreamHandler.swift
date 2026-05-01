import Flutter
import Foundation

final class LaunchRouteStreamHandler: NSObject, FlutterStreamHandler {
  static let shared = LaunchRouteStreamHandler()

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
    emit(route: url.absoluteString)
  }

  func emit(route: String) {
    let trimmedRoute = route.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedRoute.isEmpty else {
      return
    }

    if let eventSink {
      eventSink(trimmedRoute)
    } else {
      pendingRoutes.append(trimmedRoute)
    }
  }

  func takePendingRoute() -> String? {
    guard let route = pendingRoutes.last else {
      return nil
    }
    pendingRoutes.removeAll()
    return route
  }

  private func flushPendingRoutes() {
    guard let eventSink else { return }
    pendingRoutes.forEach { eventSink($0) }
    pendingRoutes.removeAll()
  }
}
