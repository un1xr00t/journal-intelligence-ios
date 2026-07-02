import Flutter
import CoreLocation
import MapKit
import UserNotifications
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NotificationBridge.shared.configure()
    if #available(iOS 16.0, *) {
      JournalAppShortcuts.updateAppShortcutParameters()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    LaunchRouteStreamHandler.shared.emit(url: url)
    return super.application(app, open: url, options: options)
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if userActivity.activityType == "name.williamthomas.journalIntelligence.route",
       let route = userActivity.userInfo?["route"] as? String {
      LaunchRouteStreamHandler.shared.emit(route: route)
    }
    return super.application(
      application,
      continue: userActivity,
      restorationHandler: restorationHandler
    )
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

final class NotificationBridge: NSObject, CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
  static let shared = NotificationBridge()
  private static let locationJournalCategoryId = "location_journal"
  private static let openSageActionId = "open_sage"

  private let center = UNUserNotificationCenter.current()
  private let locationManager = CLLocationManager()
  private let geocoder = CLGeocoder()
  private var pendingLocationPermissionResult: FlutterResult?
  private var pendingCurrentLocationResult: FlutterResult?
  private var shouldRequestLocationAfterAuthorization = false

  private override init() {
    super.init()
    locationManager.delegate = self
  }

  func configure() {
    center.delegate = self
    let openSageAction = UNNotificationAction(
      identifier: Self.openSageActionId,
      title: "Ask Sage",
      options: [.foreground]
    )
    let locationCategory = UNNotificationCategory(
      identifier: Self.locationJournalCategoryId,
      actions: [openSageAction],
      intentIdentifiers: [],
      options: [.customDismissAction]
    )
    center.setNotificationCategories([locationCategory])
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getStatus":
      getStatus(result: result)
    case "requestNotificationPermission":
      requestNotificationPermission(result: result)
    case "requestLocationPermission":
      requestLocationPermission(result: result)
    case "getCurrentLocation":
      getCurrentLocation(result: result)
    case "resolveAddress":
      resolveAddress(call.arguments, result: result)
    case "scheduleCalendarNotification":
      scheduleCalendarNotification(call.arguments, result: result)
    case "showImmediateNotification":
      showImmediateNotification(call.arguments, result: result)
    case "scheduleLocationNotification":
      scheduleLocationNotification(call.arguments, result: result)
    case "getDeliveredLocationEvents":
      getDeliveredLocationEvents(result: result)
    case "cancelNotifications":
      cancelNotifications(call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func getStatus(result: @escaping FlutterResult) {
    center.getNotificationSettings { [weak self] settings in
      guard let self else { return }
      DispatchQueue.main.async {
        result([
          "notificationStatus": self.notificationStatusString(settings.authorizationStatus),
          "notificationsAuthorized": self.notificationsAuthorized(
            for: settings.authorizationStatus),
          "locationStatus": self.locationStatusString(self.currentLocationAuthorizationStatus),
        ])
      }
    }
  }

  private func requestNotificationPermission(result: @escaping FlutterResult) {
    center.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] _, error in
      guard let self else { return }
      if let error {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "notification_permission_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
        return
      }

      self.getStatus(result: result)
    }
  }

  private func requestLocationPermission(result: @escaping FlutterResult) {
    let status = currentLocationAuthorizationStatus
    if status == .authorizedAlways || status == .authorizedWhenInUse {
      getStatus(result: result)
      return
    }
    if status == .denied || status == .restricted {
      getStatus(result: result)
      return
    }

    pendingLocationPermissionResult = result
    locationManager.requestWhenInUseAuthorization()
  }

  private func getCurrentLocation(result: @escaping FlutterResult) {
    let status = currentLocationAuthorizationStatus
    switch status {
    case .authorizedAlways, .authorizedWhenInUse:
      pendingCurrentLocationResult = result
      locationManager.requestLocation()
    case .notDetermined:
      pendingCurrentLocationResult = result
      shouldRequestLocationAfterAuthorization = true
      locationManager.requestWhenInUseAuthorization()
    case .denied, .restricted:
      result(
        FlutterError(
          code: "location_permission_denied",
          message: "Location access is required to save this place.",
          details: nil
        )
      )
    @unknown default:
      result(
        FlutterError(
          code: "location_unavailable",
          message: "Location access is unavailable right now.",
          details: nil
        )
      )
    }
  }

  private func resolveAddress(_ rawArguments: Any?, result: @escaping FlutterResult) {
    guard let arguments = rawArguments as? [String: Any],
          let address = arguments["address"] as? String else {
      result(
        FlutterError(
          code: "invalid_resolve_address",
          message: "Missing address for geocoding.",
          details: nil
        )
      )
      return
    }

    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      result(
        FlutterError(
          code: "invalid_resolve_address",
          message: "Address cannot be empty.",
          details: nil
        )
      )
      return
    }

    geocoder.geocodeAddressString(trimmed) { placemarks, error in
      DispatchQueue.main.async {
        if let error {
          result(
            FlutterError(
              code: "resolve_address_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
          return
        }

        guard let placemark = placemarks?.first,
              let location = placemark.location else {
          result(
            FlutterError(
              code: "resolve_address_not_found",
              message: "Could not find that address.",
              details: nil
            )
          )
          return
        }

        var payload: [String: Any] = [
          "latitude": location.coordinate.latitude,
          "longitude": location.coordinate.longitude,
        ]
        if let addressLabel = self.addressLabel(from: placemark), !addressLabel.isEmpty {
          payload["addressLabel"] = addressLabel
        }
        result(payload)
      }
    }
  }

  private func scheduleCalendarNotification(_ rawArguments: Any?, result: @escaping FlutterResult) {
    guard let arguments = rawArguments as? [String: Any],
          let id = arguments["id"] as? String,
          let title = arguments["title"] as? String,
          let body = arguments["body"] as? String,
          let hour = arguments["hour"] as? Int,
          let minute = arguments["minute"] as? Int else {
      result(
        FlutterError(
          code: "invalid_calendar_notification",
          message: "Missing calendar notification arguments.",
          details: nil
        )
      )
      return
    }

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    if let route = arguments["route"] as? String, !route.isEmpty {
      content.userInfo["route"] = route
    }
    if let routeSage = arguments["routeSage"] as? String, !routeSage.isEmpty {
      content.userInfo["route_sage"] = routeSage
    }
    if let categoryId = arguments["categoryId"] as? String, !categoryId.isEmpty {
      content.categoryIdentifier = categoryId
    }

    var components = DateComponents()
    components.hour = hour
    components.minute = minute
    if let day = arguments["day"] as? Int {
      components.day = day
    }
    if let month = arguments["month"] as? Int {
      components.month = month
    }
    if let year = arguments["year"] as? Int {
      components.year = year
    }
    if let weekday = arguments["weekday"] as? Int {
      components.weekday = weekday
    }

    let repeats = arguments["repeats"] as? Bool ?? true
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

    center.add(request) { error in
      DispatchQueue.main.async {
        if let error {
          result(
            FlutterError(
              code: "schedule_calendar_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        } else {
          result(nil)
        }
      }
    }
  }

  private func showImmediateNotification(_ rawArguments: Any?, result: @escaping FlutterResult) {
    guard let arguments = rawArguments as? [String: Any],
          let id = arguments["id"] as? String,
          let title = arguments["title"] as? String,
          let body = arguments["body"] as? String else {
      result(
        FlutterError(
          code: "invalid_immediate_notification",
          message: "Missing immediate notification arguments.",
          details: nil
        )
      )
      return
    }

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    if let route = arguments["route"] as? String, !route.isEmpty {
      content.userInfo["route"] = route
    }
    if let routeSage = arguments["routeSage"] as? String, !routeSage.isEmpty {
      content.userInfo["route_sage"] = routeSage
    }
    if let categoryId = arguments["categoryId"] as? String, !categoryId.isEmpty {
      content.categoryIdentifier = categoryId
    }

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

    center.add(request) { error in
      DispatchQueue.main.async {
        if let error {
          result(
            FlutterError(
              code: "show_immediate_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        } else {
          result(nil)
        }
      }
    }
  }

  private func scheduleLocationNotification(_ rawArguments: Any?, result: @escaping FlutterResult) {
    guard let arguments = rawArguments as? [String: Any],
          let id = arguments["id"] as? String,
          let title = arguments["title"] as? String,
          let body = arguments["body"] as? String,
          let latitude = arguments["latitude"] as? Double,
          let longitude = arguments["longitude"] as? Double,
          let radius = arguments["radius"] as? Double else {
      result(
        FlutterError(
          code: "invalid_location_notification",
          message: "Missing location notification arguments.",
          details: nil
        )
      )
      return
    }

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    if let eventKind = arguments["eventKind"] as? String, !eventKind.isEmpty {
      content.userInfo["event_kind"] = eventKind
    }
    if let placeId = arguments["placeId"] as? String, !placeId.isEmpty {
      content.userInfo["place_id"] = placeId
    }
    if let placeName = arguments["placeName"] as? String, !placeName.isEmpty {
      content.userInfo["place_name"] = placeName
    }
    if let placeKind = arguments["placeKind"] as? String, !placeKind.isEmpty {
      content.userInfo["place_kind"] = placeKind
    }
    if let transition = arguments["transition"] as? String, !transition.isEmpty {
      content.userInfo["transition"] = transition
    }
    if let route = arguments["route"] as? String, !route.isEmpty {
      content.userInfo["route"] = route
    }
    if let routeSage = arguments["routeSage"] as? String, !routeSage.isEmpty {
      content.userInfo["route_sage"] = routeSage
    }
    if let categoryId = arguments["categoryId"] as? String, !categoryId.isEmpty {
      content.categoryIdentifier = categoryId
    }

    let centerCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    let region = CLCircularRegion(
      center: centerCoordinate,
      radius: max(100.0, min(radius, 1000.0)),
      identifier: id
    )
    region.notifyOnEntry = arguments["notifyOnEntry"] as? Bool ?? true
    region.notifyOnExit = arguments["notifyOnExit"] as? Bool ?? false

    let repeats = arguments["repeats"] as? Bool ?? true
    let trigger = UNLocationNotificationTrigger(region: region, repeats: repeats)
    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

    center.add(request) { error in
      DispatchQueue.main.async {
        if let error {
          result(
            FlutterError(
              code: "schedule_location_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        } else {
          result(nil)
        }
      }
    }
  }

  private func getDeliveredLocationEvents(result: @escaping FlutterResult) {
    center.getDeliveredNotifications { notifications in
      let events: [[String: Any]] = notifications.compactMap { notification in
        let userInfo = notification.request.content.userInfo
        guard let eventKind = userInfo["event_kind"] as? String,
              eventKind == "location_nudge",
              let placeId = userInfo["place_id"] as? String,
              let placeKind = userInfo["place_kind"] as? String,
              let transition = userInfo["transition"] as? String else {
          return nil
        }

        return [
          "identifier": notification.request.identifier,
          "deliveredAt": notification.date.iso8601String,
          "placeId": placeId,
          "placeName": (userInfo["place_name"] as? String) ?? "Saved Place",
          "placeKind": placeKind,
          "transition": transition,
        ]
      }

      DispatchQueue.main.async {
        result(events)
      }
    }
  }

  private func cancelNotifications(_ rawArguments: Any?, result: @escaping FlutterResult) {
    guard let arguments = rawArguments as? [String: Any],
          let ids = arguments["ids"] as? [String] else {
      result(
        FlutterError(
          code: "invalid_cancel_arguments",
          message: "Missing notification identifiers.",
          details: nil
        )
      )
      return
    }

    center.removePendingNotificationRequests(withIdentifiers: ids)
    center.removeDeliveredNotifications(withIdentifiers: ids)
    result(nil)
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    handleAuthorizationUpdate()
  }

  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    handleAuthorizationUpdate()
  }

  private func handleAuthorizationUpdate() {
    let status = currentLocationAuthorizationStatus

    if let pendingLocationPermissionResult, status != .notDetermined {
      self.pendingLocationPermissionResult = nil
      getStatus(result: pendingLocationPermissionResult)
    }

    guard shouldRequestLocationAfterAuthorization, status != .notDetermined else {
      return
    }

    shouldRequestLocationAfterAuthorization = false

    if status == .authorizedAlways || status == .authorizedWhenInUse {
      locationManager.requestLocation()
      return
    }

    if let pendingCurrentLocationResult {
      self.pendingCurrentLocationResult = nil
      pendingCurrentLocationResult(
        FlutterError(
          code: "location_permission_denied",
          message: "Location access is required to save this place.",
          details: nil
        )
      )
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last, let pendingCurrentLocationResult else {
      return
    }

    self.pendingCurrentLocationResult = nil
    geocoder.reverseGeocodeLocation(location) { placemarks, _ in
      self.resolveCurrentPlaceDetails(
        for: location,
        placemark: placemarks?.first,
        completion: pendingCurrentLocationResult
      )
    }
  }

  private func resolveCurrentPlaceDetails(
    for location: CLLocation,
    placemark: CLPlacemark?,
    completion: @escaping FlutterResult
  ) {
    let request = MKLocalSearch.Request()
    request.resultTypes = .pointOfInterest
    request.region = MKCoordinateRegion(
      center: location.coordinate,
      latitudinalMeters: 250,
      longitudinalMeters: 250
    )

    MKLocalSearch(request: request).start { response, _ in
      let pointOfInterestName = response?.mapItems
        .sorted(by: { lhs, rhs in
          let leftDistance = lhs.placemark.location?.distance(from: location) ?? .greatestFiniteMagnitude
          let rightDistance = rhs.placemark.location?.distance(from: location) ?? .greatestFiniteMagnitude
          return leftDistance < rightDistance
        })
        .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty })

      let areaOfInterest = placemark?.areasOfInterest?
        .compactMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty })

      let locality = placemark?.locality?.trimmingCharacters(in: .whitespacesAndNewlines)
      let subLocality = placemark?.subLocality?.trimmingCharacters(in: .whitespacesAndNewlines)
      let addressLabel = self.addressLabel(from: placemark)
      let fallbackName = self.fallbackPlaceName(
        addressLabel: addressLabel,
        subLocality: subLocality,
        locality: locality
      )

      let resolvedName = [pointOfInterestName, areaOfInterest, fallbackName]
        .compactMap { $0 }
        .first(where: { !$0.isEmpty }) ?? "Current Spot"

      var payload: [String: Any] = [
        "latitude": location.coordinate.latitude,
        "longitude": location.coordinate.longitude,
        "accuracy": location.horizontalAccuracy,
        "placeName": resolvedName,
      ]
      if let addressLabel, !addressLabel.isEmpty {
        payload["addressLabel"] = addressLabel
      }
      if let pointOfInterestName, !pointOfInterestName.isEmpty {
        payload["resolvedBy"] = "poi"
      } else if let areaOfInterest, !areaOfInterest.isEmpty {
        payload["resolvedBy"] = "area_of_interest"
      } else {
        payload["resolvedBy"] = "reverse_geocode"
      }
      completion(payload)
    }
  }

  private func addressLabel(from placemark: CLPlacemark?) -> String? {
    guard let placemark else { return nil }

    let streetParts = [
      placemark.subThoroughfare,
      placemark.thoroughfare,
    ]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let cityStateParts = [
      placemark.locality,
      placemark.administrativeArea,
    ]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    let pieces = [
      streetParts.joined(separator: " "),
      cityStateParts.joined(separator: ", "),
    ]
      .filter { !$0.isEmpty }
    let joined = pieces.joined(separator: " • ")
    return joined.isEmpty ? nil : joined
  }

  private func fallbackPlaceName(
    addressLabel: String?,
    subLocality: String?,
    locality: String?
  ) -> String? {
    if let subLocality, !subLocality.isEmpty {
      return subLocality
    }
    if let locality, !locality.isEmpty {
      return locality
    }
    return addressLabel
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    guard let pendingCurrentLocationResult else {
      return
    }

    self.pendingCurrentLocationResult = nil
    pendingCurrentLocationResult(
      FlutterError(
        code: "current_location_failed",
        message: error.localizedDescription,
        details: nil
      )
    )
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    let routeKey = response.actionIdentifier == Self.openSageActionId
      ? "route_sage"
      : "route"
    let fallbackRouteKey = routeKey == "route_sage" ? "route" : "route_sage"
    if let route = userInfo[routeKey] as? String
      ?? userInfo[fallbackRouteKey] as? String {
      LaunchRouteStreamHandler.shared.emit(route: route)
    }
    completionHandler()
  }

  private var currentLocationAuthorizationStatus: CLAuthorizationStatus {
    if #available(iOS 14.0, *) {
      return locationManager.authorizationStatus
    }
    return CLLocationManager.authorizationStatus()
  }

  private func notificationsAuthorized(for status: UNAuthorizationStatus) -> Bool {
    switch status {
    case .authorized, .provisional, .ephemeral:
      return true
    default:
      return false
    }
  }

  private func notificationStatusString(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined:
      return "notDetermined"
    case .denied:
      return "denied"
    case .authorized:
      return "authorized"
    case .provisional:
      return "provisional"
    case .ephemeral:
      return "ephemeral"
    @unknown default:
      return "unknown"
    }
  }

  private func locationStatusString(_ status: CLAuthorizationStatus) -> String {
    switch status {
    case .notDetermined:
      return "notDetermined"
    case .restricted:
      return "restricted"
    case .denied:
      return "denied"
    case .authorizedAlways:
      return "authorizedAlways"
    case .authorizedWhenInUse:
      return "authorizedWhenInUse"
    @unknown default:
      return "unknown"
    }
  }
}

private extension Date {
  var iso8601String: String {
    ISO8601DateFormatter().string(from: self)
  }
}
