import Foundation
import AppIntents

@available(iOS 16.0, *)
struct JournalAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: LogCareNoteIntent(),
      phrases: [
        "Log a care note in \(.applicationName)",
        "Capture a support note in \(.applicationName)",
        "Record what happened in \(.applicationName)",
      ],
      shortTitle: "Log Care Note",
      systemImageName: "waveform.and.mic"
    )
  }
}

@available(iOS 16.0, *)
struct LogCareNoteIntent: AppIntent {
  static var title: LocalizedStringResource = "Log Care Note"
  static var description = IntentDescription(
    "Capture a spoken caregiving note and send it into Journal Intelligence for timeline and Proof Vault routing."
  )
  static var openAppWhenRun: Bool = true

  @Parameter(
    title: "What happened",
    requestValueDialog: IntentDialog("What do you want to log?")
  )
  var text: String
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return .result(dialog: IntentDialog("Tell me what happened and I’ll route it into your journal."))
    }

    LaunchRouteStreamHandler.shared.emit(route: Self.buildRoute(for: trimmed))
    return .result(
      dialog: IntentDialog("Opening Journal Intelligence to classify and save your note.")
    )
  }

  private static func buildRoute(for text: String) -> String {
    var components = URLComponents()
    components.scheme = "journalintelligence"
    components.host = "siri-capture"
    components.queryItems = [
      URLQueryItem(name: "prefill", value: text),
      URLQueryItem(name: "source", value: "siri_shortcut"),
      URLQueryItem(name: "auto_save", value: "1"),
    ]
    return components.url?.absoluteString ?? "journalintelligence://siri-capture"
  }
}
