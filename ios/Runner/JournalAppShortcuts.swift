import AppIntents
import Flutter
import Foundation
import Security

private let journalBaseURLString = "https://journal.williamthomas.name"

@available(iOS 16.0, *)
struct JournalAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    return [
      AppShortcut(
        intent: LogJournalEntryIntent(),
        phrases: [
          "Save a journal entry in \(.applicationName)",
          "Add to my journal in \(.applicationName)",
          "Capture a personal note in \(.applicationName)",
        ],
        shortTitle: "Log Journal Entry",
        systemImageName: "book.closed"
      ),
      AppShortcut(
        intent: LogCareNoteIntent(),
        phrases: [
          "Log a support note in \(.applicationName)",
          "Save a Wyatt support note in \(.applicationName)",
          "Capture a caregiving note in \(.applicationName)",
        ],
        shortTitle: "Log Support Note",
        systemImageName: "waveform.and.mic"
      ),
    ]
  }
}

@available(iOS 16.0, *)
struct LogJournalEntryIntent: AppIntent {
  static var title: LocalizedStringResource = "Log Journal Entry"
  static var description = IntentDescription(
    "Capture a spoken journal entry and save it directly to your Journal Intelligence timeline."
  )
  static var openAppWhenRun: Bool = false

  @Parameter(
    title: "Journal entry",
    requestValueDialog: IntentDialog("What do you want to add to your journal?")
  )
  var text: String

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return .result(
        dialog: IntentDialog("Tell me what happened and I’ll save it to your journal.")
      )
    }

    let outcome = await SiriShortcutAPIClient().executeJournalEntry(note: trimmed)
    switch outcome {
    case .saved:
      return .result(dialog: IntentDialog("Saved to your journal."))
    case .needsForeground(.authRequired, let route):
      LaunchRouteStreamHandler.shared.prepareForegroundLaunch(route: route)
      if #available(iOS 16.4, *) {
        try await requestToContinueInForeground(
          IntentDialog("Open Journal Intelligence so I can refresh your secure session before saving this journal entry.")
        )
      }
      return .result(
        dialog: IntentDialog(
          "Open Journal Intelligence so I can refresh your secure session before saving this journal entry."
        )
      )
    case .needsForeground(_, let route):
      LaunchRouteStreamHandler.shared.prepareForegroundLaunch(route: route)
      if #available(iOS 16.4, *) {
        try await requestToContinueInForeground(
          IntentDialog("Open Journal Intelligence so you can review and finish saving this journal entry.")
        )
      }
      return .result(
        dialog: IntentDialog(
          "Open Journal Intelligence so you can review and finish saving this journal entry."
        )
      )
    }
  }
}

@available(iOS 16.0, *)
extension LogJournalEntryIntent: ForegroundContinuableIntent {}

@available(iOS 16.0, *)
struct LogCareNoteIntent: AppIntent {
  static var title: LocalizedStringResource = "Log Support Note"
  static var description = IntentDescription(
    "Capture a spoken caregiving or support note and save it to Journal Intelligence, including Proof Vault when routing is obvious."
  )
  static var openAppWhenRun: Bool = false

  @Parameter(
    title: "What happened",
    requestValueDialog: IntentDialog("What do you want to log?")
  )
  var text: String

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return .result(dialog: IntentDialog("Tell me what happened and I’ll log it."))
    }

    let outcome = await SiriShortcutAPIClient().executeSupportNote(note: trimmed)
    switch outcome {
    case .saved:
      return .result(
        dialog: IntentDialog("Saved to your timeline and Proof Vault.")
      )
    case .needsForeground(.authRequired, let route):
      LaunchRouteStreamHandler.shared.prepareForegroundLaunch(route: route)
      if #available(iOS 16.4, *) {
        try await requestToContinueInForeground(
          IntentDialog("Open Journal Intelligence so I can refresh your secure session before saving this note.")
        )
      }
      return .result(
        dialog: IntentDialog(
          "Open Journal Intelligence so I can refresh your secure session before saving this note."
        )
      )
    case .needsForeground(.missingFolder, let route):
      LaunchRouteStreamHandler.shared.prepareForegroundLaunch(route: route)
      if #available(iOS 16.4, *) {
        try await requestToContinueInForeground(
          IntentDialog("Open Journal Intelligence so you can confirm the Proof Vault folder for this note.")
        )
      }
      return .result(
        dialog: IntentDialog(
          "Open Journal Intelligence so you can confirm the Proof Vault folder for this note."
        )
      )
    case .needsForeground(.saveFailed, let route):
      LaunchRouteStreamHandler.shared.prepareForegroundLaunch(route: route)
      if #available(iOS 16.4, *) {
        try await requestToContinueInForeground(
          IntentDialog("Open Journal Intelligence so you can finish saving this note.")
        )
      }
      return .result(
        dialog: IntentDialog("Open Journal Intelligence so you can finish saving this note.")
      )
    case .needsForeground(.ambiguousRouting, let route):
      LaunchRouteStreamHandler.shared.prepareForegroundLaunch(route: route)
      if #available(iOS 16.4, *) {
        try await requestToContinueInForeground(
          IntentDialog("Open Journal Intelligence so you can review where this note belongs.")
        )
      }
      return .result(
        dialog: IntentDialog(
          "Open Journal Intelligence so you can review where this note belongs."
        )
      )
    }
  }
}

@available(iOS 16.0, *)
extension LogCareNoteIntent: ForegroundContinuableIntent {}

final class NativeRefreshSessionStore {
  static let shared = NativeRefreshSessionStore()

  private enum Constants {
    static let service = "name.williamthomas.journalIntelligence.nativeSession"
    static let account = "refresh_token_cookie"
    static let refreshCookieName = "refresh_token"
  }

  private struct StoredSession: Codable {
    let cookieValue: String
    let expiresAt: Date?
    let updatedAt: Date
  }

  struct RefreshCookieSession {
    let cookieValue: String
    let expiresAt: Date?

    var cookieHeader: String {
      "\(Constants.refreshCookieName)=\(cookieValue)"
    }
  }

  private init() {}

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "syncFromSetCookieHeaders":
      guard let arguments = call.arguments as? [String: Any],
            let headers = arguments["headers"] as? [String] else {
        result(
          FlutterError(
            code: "invalid_native_session_args",
            message: "Missing Set-Cookie headers.",
            details: nil
          )
        )
        return
      }

      do {
        try syncFromSetCookieHeaders(headers)
        result(nil)
      } catch {
        result(
          FlutterError(
            code: "native_session_sync_failed",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    case "clear":
      do {
        try clear()
        result(nil)
      } catch {
        result(
          FlutterError(
            code: "native_session_clear_failed",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func loadSession() -> RefreshCookieSession? {
    guard let data = try? readData(),
          let stored = try? JSONDecoder().decode(StoredSession.self, from: data) else {
      return nil
    }
    if let expiresAt = stored.expiresAt, expiresAt <= Date() {
      try? clear()
      return nil
    }
    return RefreshCookieSession(cookieValue: stored.cookieValue, expiresAt: stored.expiresAt)
  }

  func syncFromSetCookieHeaders(_ headers: [String]) throws {
    guard let cookie = parseRefreshCookie(from: headers) else {
      return
    }
    try save(cookieValue: cookie.value, expiresAt: cookie.expiresDate)
  }

  func clear() throws {
    let status = SecItemDelete(keychainQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw NativeSessionStoreError.keychainFailure(status)
    }
  }

  private func save(cookieValue: String, expiresAt: Date?) throws {
    let payload = StoredSession(
      cookieValue: cookieValue,
      expiresAt: expiresAt,
      updatedAt: Date()
    )
    let data = try JSONEncoder().encode(payload)

    var attributes = keychainQuery
    attributes[kSecValueData as String] = data

    let status = SecItemAdd(attributes as CFDictionary, nil)
    if status == errSecSuccess {
      return
    }
    guard status == errSecDuplicateItem else {
      throw NativeSessionStoreError.keychainFailure(status)
    }

    let updateStatus = SecItemUpdate(
      keychainQuery as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    guard updateStatus == errSecSuccess else {
      throw NativeSessionStoreError.keychainFailure(updateStatus)
    }
  }

  private func readData() throws -> Data? {
    var query = keychainQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      return item as? Data
    case errSecItemNotFound:
      return nil
    default:
      throw NativeSessionStoreError.keychainFailure(status)
    }
  }

  private var keychainQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Constants.service,
      kSecAttrAccount as String: Constants.account,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
  }

  private func parseRefreshCookie(from headers: [String]) -> HTTPCookie? {
    guard let baseURL = URL(string: journalBaseURLString) else {
      return nil
    }

    for header in headers {
      let cookies = HTTPCookie.cookies(
        withResponseHeaderFields: ["Set-Cookie": header],
        for: baseURL
      )
      if let refreshCookie = cookies.first(where: { $0.name == Constants.refreshCookieName }) {
        return refreshCookie
      }
    }

    return nil
  }

  func syncFromHTTPHeaderFields(_ headers: [AnyHashable: Any]) throws {
    guard let baseURL = URL(string: journalBaseURLString) else {
      return
    }
    let responseHeaders = headers.reduce(into: [String: String]()) { partialResult, item in
      partialResult[String(describing: item.key)] = String(describing: item.value)
    }
    let cookies = HTTPCookie.cookies(withResponseHeaderFields: responseHeaders, for: baseURL)
    guard let refreshCookie = cookies.first(where: { $0.name == Constants.refreshCookieName }) else {
      return
    }
    try save(cookieValue: refreshCookie.value, expiresAt: refreshCookie.expiresDate)
  }
}

private enum NativeSessionStoreError: LocalizedError {
  case keychainFailure(OSStatus)

  var errorDescription: String? {
    switch self {
    case .keychainFailure(let status):
      return "Keychain operation failed with status \(status)."
    }
  }
}

@available(iOS 16.0, *)
private final class SiriShortcutAPIClient {
  private let session = URLSession.shared
  private let sessionStore = NativeRefreshSessionStore.shared

  func execute(note: String) async -> SiriShortcutExecutionOutcome {
    return await executeSupportNote(note: note)
  }

  func executeSupportNote(note: String) async -> SiriShortcutExecutionOutcome {
    let classification = SiriShortcutClassifier.classify(note: note)
    guard classification.shouldAutoSave, let preferredFolder = classification.folderName else {
      return .needsForeground(
        .ambiguousRouting,
        route: SiriShortcutRouteBuilder.reviewRoute(
          note: classification.normalizedText,
          reason: .ambiguousRouting,
          preferredFolderName: classification.folderName,
          journalOnly: false
        )
      )
    }

    guard let refreshSession = sessionStore.loadSession() else {
      return .needsForeground(
        .authRequired,
        route: SiriShortcutRouteBuilder.reviewRoute(
          note: classification.normalizedText,
          reason: .authRequired,
          preferredFolderName: preferredFolder,
          journalOnly: false
        )
      )
    }

    do {
      let accessToken = try await refreshAccessToken(using: refreshSession)
      let folders = try await fetchFolders(accessToken: accessToken)
      guard let folder = folders.first(where: {
        SiriShortcutClassifier.normalizeLabel($0.name) ==
          SiriShortcutClassifier.normalizeLabel(preferredFolder)
      }) else {
        return .needsForeground(
          .missingFolder,
          route: SiriShortcutRouteBuilder.reviewRoute(
            note: classification.normalizedText,
            reason: .missingFolder,
            preferredFolderName: preferredFolder,
            journalOnly: false
          )
        )
      }

      var createdEntryId: Int?
      do {
        createdEntryId = try await createTimelineEntry(
          text: classification.normalizedText,
          accessToken: accessToken
        )
        _ = try await createVaultItem(
          folderId: folder.id,
          classification: classification,
          accessToken: accessToken
        )
        return .saved
      } catch {
        if let createdEntryId {
          try? await deleteTimelineEntry(entryId: createdEntryId, accessToken: accessToken)
        }
        return .needsForeground(
          .saveFailed,
          route: SiriShortcutRouteBuilder.reviewRoute(
            note: classification.normalizedText,
            reason: .saveFailed,
            preferredFolderName: preferredFolder,
            journalOnly: false
          )
        )
      }
    } catch ShortcutAPIError.authExpired {
      try? sessionStore.clear()
      return .needsForeground(
        .authRequired,
        route: SiriShortcutRouteBuilder.reviewRoute(
          note: classification.normalizedText,
          reason: .authRequired,
          preferredFolderName: preferredFolder,
          journalOnly: false
        )
      )
    } catch {
      return .needsForeground(
        .saveFailed,
        route: SiriShortcutRouteBuilder.reviewRoute(
          note: classification.normalizedText,
          reason: .saveFailed,
          preferredFolderName: preferredFolder,
          journalOnly: false
        )
      )
    }
  }

  func executeJournalEntry(note: String) async -> SiriShortcutExecutionOutcome {
    let normalizedText = note
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

    guard !normalizedText.isEmpty else {
      return .needsForeground(
        .saveFailed,
        route: SiriShortcutRouteBuilder.reviewRoute(
          note: note,
          reason: .saveFailed,
          preferredFolderName: nil,
          journalOnly: true
        )
      )
    }

    guard let refreshSession = sessionStore.loadSession() else {
      return .needsForeground(
        .authRequired,
        route: SiriShortcutRouteBuilder.reviewRoute(
          note: normalizedText,
          reason: .authRequired,
          preferredFolderName: nil,
          journalOnly: true
        )
      )
    }

    do {
      let accessToken = try await refreshAccessToken(using: refreshSession)
      _ = try await createTimelineEntry(
        text: normalizedText,
        accessToken: accessToken
      )
      return .saved
    } catch ShortcutAPIError.authExpired {
      try? sessionStore.clear()
      return .needsForeground(
        .authRequired,
        route: SiriShortcutRouteBuilder.reviewRoute(
          note: normalizedText,
          reason: .authRequired,
          preferredFolderName: nil,
          journalOnly: true
        )
      )
    } catch {
      return .needsForeground(
        .saveFailed,
        route: SiriShortcutRouteBuilder.reviewRoute(
          note: normalizedText,
          reason: .saveFailed,
          preferredFolderName: nil,
          journalOnly: true
        )
      )
    }
  }

  private func refreshAccessToken(
    using refreshSession: NativeRefreshSessionStore.RefreshCookieSession
  ) async throws -> String {
    var request = URLRequest(url: try url(path: "/auth/refresh"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(refreshSession.cookieHeader, forHTTPHeaderField: "Cookie")

    let (data, response) = try await session.data(for: request)
    let httpResponse = try validate(response: response, data: data)
    try syncUpdatedRefreshCookie(from: httpResponse)

    let payload = try decodeJSONDictionary(from: data)
    guard let accessToken = payload["access_token"] as? String, !accessToken.isEmpty else {
      throw ShortcutAPIError.invalidResponse
    }
    return accessToken
  }

  private func fetchFolders(accessToken: String) async throws -> [ShortcutVaultFolder] {
    var request = URLRequest(url: try url(path: "/api/vault/folders"))
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await session.data(for: request)
    _ = try validate(response: response, data: data)
    let decoded = try JSONSerialization.jsonObject(with: data)
    guard let rawFolders = decoded as? [[String: Any]] else {
      throw ShortcutAPIError.invalidResponse
    }
    return rawFolders.compactMap { folder in
      guard let idValue = folder["id"],
            let name = folder["name"] as? String,
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
      }
      return ShortcutVaultFolder(id: String(describing: idValue), name: name)
    }
  }

  private func createTimelineEntry(text: String, accessToken: String) async throws -> Int? {
    let body = [
      "text": text,
      "entry_date": Self.entryDateFormatter.string(from: Date()),
    ]
    let payload = try await sendJSONRequest(
      method: "POST",
      path: "/api/journal/write",
      accessToken: accessToken,
      body: body
    )
    return (payload["entry_id"] as? NSNumber)?.intValue
  }

  private func deleteTimelineEntry(entryId: Int, accessToken: String) async throws {
    _ = try await sendJSONRequest(
      method: "DELETE",
      path: "/api/entries/\(entryId)",
      accessToken: accessToken,
      body: nil
    )
  }

  private func createVaultItem(
    folderId: String,
    classification: SiriShortcutClassification,
    accessToken: String
  ) async throws -> String? {
    let body = [
      "title": classification.title,
      "notes": classification.notes,
      "item_date": Self.entryDateFormatter.string(from: Date()),
    ]
    let payload = try await sendJSONRequest(
      method: "POST",
      path: "/api/vault/folders/\(folderId)/items",
      accessToken: accessToken,
      body: body
    )
    if let id = payload["id"] {
      return String(describing: id)
    }
    return nil
  }

  private func sendJSONRequest(
    method: String,
    path: String,
    accessToken: String,
    body: [String: Any]?
  ) async throws -> [String: Any] {
    var request = URLRequest(url: try url(path: path))
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    if let body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }

    let (data, response) = try await session.data(for: request)
    _ = try validate(response: response, data: data)
    if data.isEmpty {
      return [:]
    }
    return try decodeJSONDictionary(from: data)
  }

  private func url(path: String) throws -> URL {
    guard let url = URL(string: journalBaseURLString + path) else {
      throw ShortcutAPIError.invalidRequest
    }
    return url
  }

  private func validate(response: URLResponse, data: Data) throws -> HTTPURLResponse {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ShortcutAPIError.invalidResponse
    }
    switch httpResponse.statusCode {
    case 200 ... 299:
      return httpResponse
    case 401, 403:
      throw ShortcutAPIError.authExpired
    default:
      throw ShortcutAPIError.httpFailure(statusCode: httpResponse.statusCode, body: data)
    }
  }

  private func decodeJSONDictionary(from data: Data) throws -> [String: Any] {
    let json = try JSONSerialization.jsonObject(with: data)
    guard let dictionary = json as? [String: Any] else {
      throw ShortcutAPIError.invalidResponse
    }
    return dictionary
  }

  private func syncUpdatedRefreshCookie(from response: HTTPURLResponse) throws {
    try sessionStore.syncFromHTTPHeaderFields(response.allHeaderFields)
  }

  private static let entryDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()
}

private enum ShortcutAPIError: Error {
  case invalidRequest
  case invalidResponse
  case authExpired
  case httpFailure(statusCode: Int, body: Data)
}

private struct ShortcutVaultFolder {
  let id: String
  let name: String
}

@available(iOS 16.0, *)
private enum SiriShortcutExecutionOutcome {
  case saved
  case needsForeground(SiriShortcutReviewReason, route: String)
}

private enum SiriShortcutReviewReason: String {
  case authRequired = "auth_required"
  case ambiguousRouting = "ambiguous_routing"
  case missingFolder = "missing_folder"
  case saveFailed = "save_failed"
}

private struct SiriShortcutRouteBuilder {
  static func reviewRoute(
    note: String,
    reason: SiriShortcutReviewReason,
    preferredFolderName: String?,
    journalOnly: Bool
  ) -> String {
    var components = URLComponents()
    components.scheme = "journalintelligence"
    components.host = "siri-capture"
    components.queryItems = [
      URLQueryItem(name: "prefill", value: note),
      URLQueryItem(name: "source", value: "siri_shortcut"),
      URLQueryItem(name: "review_reason", value: reason.rawValue),
      URLQueryItem(name: "journal_only", value: journalOnly ? "1" : "0"),
    ]
    if let preferredFolderName,
       !preferredFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      components.queryItems?.append(
        URLQueryItem(name: "preferred_folder", value: preferredFolderName)
      )
    }
    return components.url?.absoluteString ?? "journalintelligence://siri-capture"
  }
}

private struct SiriShortcutClassification {
  let normalizedText: String
  let title: String
  let notes: String
  let folderName: String?
  let confidence: Double
  let reason: String

  var shouldAutoSave: Bool {
    guard let folderName else { return false }
    return !folderName.isEmpty && confidence >= 0.92
  }
}

private enum SiriShortcutClassifier {
  static func classify(note: String) -> SiriShortcutClassification {
    let normalizedText = note
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    let lower = normalizedText.lowercased()

    let hasPurchaseSignal = contains(
      lower,
      pattern: #"\\b(bought|buy|paid|purchase|purchased|spent|store|target|walmart|groceries)\\b"#
    )
    let hasSupplySignal = contains(
      lower,
      pattern: #"\\b(pull[- ]?ups|diaper|diapers|wipes|formula|clothes|shoes|supplies)\\b"#
    )
    let hasActivitySignal = contains(
      lower,
      pattern: #"\\b(walk|playground|park|zoo|outing|soccer|baseball|practice|activity|activities|museum)\\b"#
    )
    let hasMedicalSignal = contains(
      lower,
      pattern: #"\\b(doctor|pediatrician|appointment|medication|medicine|therapy|hospital|urgent care|sick|health)\\b"#
    )
    let hasSchoolSignal = contains(
      lower,
      pattern: #"\\b(school|daycare|teacher|homework|conference|pickup|dropoff|class)\\b"#
    )
    let hasCommunicationSignal = contains(
      lower,
      pattern: #"\\b(call|called|text|texted|email|emailed|talked|conversation|messaged|coordinated)\\b"#
    )
    let hasDailyCareSignal = contains(
      lower,
      pattern: #"\\b(bath|bedtime|nap|meal|breakfast|lunch|dinner|fed|feeding|snack|diaper change)\\b"#
    )

    var candidates: [(folder: String, confidence: Double, reason: String)] = []
    if hasPurchaseSignal || hasSupplySignal {
      let confidence = hasPurchaseSignal && hasSupplySignal ? 0.99 : 0.95
      candidates.append((
        folder: "Financial Support",
        confidence: confidence,
        reason: "Strong purchase or supplies signal."
      ))
    }
    if hasActivitySignal {
      candidates.append((
        folder: "Activities",
        confidence: contains(lower, pattern: #"\\b(walk|playground|park)\\b"#) ? 0.97 : 0.93,
        reason: "Clear outing or activity signal."
      ))
    }
    if hasMedicalSignal {
      candidates.append((
        folder: "Medical & Health",
        confidence: 0.95,
        reason: "Clear medical or health signal."
      ))
    }
    if hasSchoolSignal {
      candidates.append((
        folder: "School & Education",
        confidence: 0.94,
        reason: "Clear school or education signal."
      ))
    }
    if hasCommunicationSignal {
      candidates.append((
        folder: "Communications",
        confidence: 0.92,
        reason: "Clear communication or coordination signal."
      ))
    }
    if hasDailyCareSignal {
      candidates.append((
        folder: "Daily Care",
        confidence: 0.94,
        reason: "Clear day-to-day caregiving signal."
      ))
    }

    let title = deriveTitle(from: normalizedText)
    let notes = "Captured from Siri: \(normalizedText)"

    guard !candidates.isEmpty else {
      return SiriShortcutClassification(
        normalizedText: normalizedText,
        title: title,
        notes: notes,
        folderName: nil,
        confidence: 0.58,
        reason: "Routing is not obvious enough for background save."
      )
    }

    let sorted = candidates.sorted { lhs, rhs in
      if lhs.confidence == rhs.confidence {
        return lhs.folder < rhs.folder
      }
      return lhs.confidence > rhs.confidence
    }
    let top = sorted[0]
    let second = sorted.dropFirst().first
    let confidencePenalty = {
      guard let second else { return 0.0 }
      return (top.confidence - second.confidence) < 0.05 ? 0.12 : 0.0
    }()

    return SiriShortcutClassification(
      normalizedText: normalizedText,
      title: title,
      notes: notes,
      folderName: top.folder,
      confidence: max(0.0, top.confidence - confidencePenalty),
      reason: confidencePenalty > 0
        ? "Multiple routing signals were detected, so review is safer."
        : top.reason
    )
  }

  static func normalizeLabel(_ value: String) -> String {
    value
      .lowercased()
      .replacingOccurrences(of: "&", with: "and")
      .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func contains(_ value: String, pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
  }

  private static func deriveTitle(from text: String) -> String {
    guard !text.isEmpty else { return "Captured care note" }
    if text.count <= 64 {
      return text
    }
    let truncated = text.prefix(61).trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(truncated)..."
  }
}
