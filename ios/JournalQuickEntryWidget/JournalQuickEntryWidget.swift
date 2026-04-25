import SwiftUI
import WidgetKit

private enum JournalWidgetColors {
    static let bgBase = Color(red: 7 / 255, green: 7 / 255, blue: 15 / 255)
    static let bgCard = Color(red: 16 / 255, green: 16 / 255, blue: 30 / 255)
    static let accent = Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255)
    static let accent2 = Color(red: 139 / 255, green: 92 / 255, blue: 246 / 255)
    static let textPrimary = Color(red: 232 / 255, green: 232 / 255, blue: 240 / 255)
    static let textSecondary = Color(red: 152 / 255, green: 152 / 255, blue: 176 / 255)
}

private struct QuickEntry: TimelineEntry {
    let date: Date
}

private struct QuickEntryProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickEntry {
        QuickEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickEntry) -> Void) {
        completion(QuickEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickEntry>) -> Void) {
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date()
        completion(Timeline(entries: [QuickEntry(date: Date())], policy: .after(nextRefresh)))
    }
}

private struct JournalQuickEntryWidgetView: View {
    let entry: QuickEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            mediumWidget
                .widgetBackground()
        default:
            smallWidget
                .widgetBackground()
                .widgetURL(URL(string: "journalintelligence:///write"))
        }
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(JournalWidgetColors.textPrimary)
                .frame(width: 42, height: 42)
                .background(
                    LinearGradient(
                        colors: [JournalWidgetColors.accent, JournalWidgetColors.accent2],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())

            Spacer(minLength: 4)

            Text("Quick Entry")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(JournalWidgetColors.textPrimary)

            Text("Open Write")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(JournalWidgetColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumWidget: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(JournalWidgetColors.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(JournalWidgetColors.accent)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Journal Intelligence")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(JournalWidgetColors.textPrimary)
                    Text("Capture the thought before it disappears.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(JournalWidgetColors.textSecondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                shortcut("Write", systemImage: "square.and.pencil", path: "/write", prominent: true)
                shortcut("Today", systemImage: "sparkles", path: "/today")
                shortcut("Sage", systemImage: "brain.head.profile", path: "/sage")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func shortcut(
        _ label: String,
        systemImage: String,
        path: String,
        prominent: Bool = false
    ) -> some View {
        Link(destination: URL(string: "journalintelligence://\(path)")!) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(JournalWidgetColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(prominent ? JournalWidgetColors.accent : JournalWidgetColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private extension View {
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) {
                JournalWidgetColors.bgBase
            }
        } else {
            padding()
                .background(JournalWidgetColors.bgBase)
        }
    }
}

struct JournalQuickEntryWidget: Widget {
    let kind = "JournalQuickEntryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickEntryProvider()) { entry in
            JournalQuickEntryWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Entry")
        .description("Open Journal Intelligence straight to writing.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct JournalQuickEntryWidgetBundle: WidgetBundle {
    var body: some Widget {
        JournalQuickEntryWidget()
    }
}
