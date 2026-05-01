import Flutter
import Foundation

final class LaunchRouteStreamHandler: NSObject, FlutterStreamHandler {
  static let shared = LaunchRouteStreamHandler()
  private static let pendingRouteDefaultsKey =
    "journal_intelligence.native_pending_launch_route"

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
    emit(route: route, persistForLaunch: false)
  }

  func prepareForegroundLaunch(route: String) {
    emit(route: route, persistForLaunch: true)
  }

  private func emit(route: String, persistForLaunch: Bool) {
    let trimmedRoute = route.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedRoute.isEmpty else {
      return
    }

    if persistForLaunch {
      UserDefaults.standard.set(trimmedRoute, forKey: Self.pendingRouteDefaultsKey)
    }

    if let eventSink {
      eventSink(trimmedRoute)
    } else {
      pendingRoutes.append(trimmedRoute)
    }
  }

  func takePendingRoute() -> String? {
    if let route = pendingRoutes.last {
      pendingRoutes.removeAll()
      UserDefaults.standard.removeObject(forKey: Self.pendingRouteDefaultsKey)
      return route
    }

    guard let route = UserDefaults.standard.string(forKey: Self.pendingRouteDefaultsKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !route.isEmpty else {
      return nil
    }
    UserDefaults.standard.removeObject(forKey: Self.pendingRouteDefaultsKey)
    return route
  }

  private func flushPendingRoutes() {
    guard let eventSink else { return }
    pendingRoutes.forEach { eventSink($0) }
    pendingRoutes.removeAll()
  }
}
