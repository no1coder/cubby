import SwiftUI
import CubbyCore

/// 安全记录表（时间 · 事件 · 当时的前台应用，新的在前，最多 20 行）：放在定高列表框里，长记录不会把整页撑得很长
struct SecurityLogTable: View {
    let entries: [SecurityLogEntry]

    private static let maxRows = 20
    private static let maxListHeight: CGFloat = 150
    private static let rowHeight: CGFloat = 27
    private static let timeWidth: CGFloat = 96
    private static let appWidth: CGFloat = 96

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if entries.isEmpty {
            Text("No events yet", comment: "Settings › Security: empty security log")
                .font(.system(size: FontSize.footnote))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 40)
        } else {
            VStack(spacing: 0) {
                row(
                    time: Self.timeHeader, event: Self.eventHeader, app: Self.appHeader,
                    eventColor: .secondary, isHeader: true)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries.prefix(Self.maxRows)) { entry in
                            row(
                                time: Self.time(entry.date), event: Self.event(entry), app: entry.appName ?? "–",
                                eventColor: entry.event == .tampered ? SecurityPalette.redText(colorScheme) : .primary,
                                isHeader: false)
                        }
                    }
                }
                .frame(height: min(CGFloat(min(entries.count, Self.maxRows)) * Self.rowHeight, Self.maxListHeight))
            }
        }
    }

    private func row(time: String, event: String, app: String, eventColor: Color, isHeader: Bool) -> some View {
        HStack(spacing: 10) {
            Text(time)
                .foregroundStyle(.secondary)
                .frame(width: Self.timeWidth, alignment: .leading)
            Text(event)
                .foregroundStyle(eventColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(app)
                .foregroundStyle(.secondary)
                .frame(width: Self.appWidth, alignment: .leading)
        }
        .font(.system(size: FontSize.footnote))
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.vertical, isHeader ? 4 : 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 文案

    private static var timeHeader: String {
        String(localized: "Time", comment: "Settings › Security log column")
    }

    private static var eventHeader: String {
        String(localized: "Event", comment: "Settings › Security log column")
    }

    private static var appHeader: String {
        String(localized: "App in Front", comment: "Settings › Security log column: the frontmost app at the time")
    }

    /// 「地址被替换 · 0x7a3F…92E1」
    static func event(_ entry: SecurityLogEntry) -> String {
        let summary = entry.summary
        return switch entry.event {
        case .tampered:
            String(localized: "Address replaced · \(summary)", comment: "Security log event. %@ = abbreviated value")
        case .restored:
            String(
                localized: "Restored what you copied · \(summary)",
                comment: "Security log event. %@ = abbreviated value")
        case .dismissed:
            String(localized: "Changed by you · \(summary)", comment: "Security log event. %@ = abbreviated value")
        case .pasteVerified:
            String(localized: "Paste matched · \(summary)", comment: "Security log event. %@ = abbreviated value")
        }
    }

    /// 今天 16:52 / 昨天 21:07 / 10月3日 16:52
    static func time(_ date: Date, now: Date = Date()) -> String {
        let time = timeFormatter.string(from: date)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return String(
                localized: "Today \(time)", comment: "Security log time of an event today, e.g. “Today 16:52”")
        }
        if calendar.isDateInYesterday(date) {
            return String(
                localized: "Yesterday \(time)",
                comment: "Time of an item copied yesterday, e.g. “Yesterday 23:11”"
            )
        }
        return dateFormatter.string(from: date)
    }

    private static let timeFormatter = formatter("jmm")
    private static let dateFormatter = formatter("MMMdjmm")

    private static func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = TimeFormatting.locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
