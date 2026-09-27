import Foundation

/// 条目时间的本地化展示
enum TimeFormatting {
    /// 与界面语言一致的 Locale：语言取应用实际使用的本地化（避免英文界面里出现中文日期），
    /// 地区与 12 / 24 小时制等偏好沿用系统设置
    static let locale: Locale = {
        let current = Locale.autoupdatingCurrent
        guard let localization = Bundle.main.preferredLocalizations.first else { return current }
        var components = Locale.Components(locale: current)
        var language = Locale.Language.Components(identifier: localization)
        language.region = language.region ?? current.region
        components.languageComponents = language
        components.hourCycle = current.hourCycle
        return Locale(components: components)
    }()

    /// 按模板生成符合当地习惯的格式（中文：HH:mm、M月d日、yyyy/M/d、yyyy年M月d日 HH:mm）
    private static func formatter(template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private static let timeFormatter = formatter(template: "jmm")
    private static let dayFormatter = formatter(template: "MMMd")
    private static let yearFormatter = formatter(template: "yMd")
    private static let absoluteFormatter = formatter(template: "yMMMdjmm")

    /// 刚刚 / N 分钟前 / 今天 HH:mm / 昨天 HH:mm / M月d日 / yyyy/M/d
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        let calendar = Calendar.current
        if seconds < 60 {
            return String(localized: "Just now", comment: "Relative time of an item copied less than a minute ago")
        }
        if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return String(localized: "\(minutes) min ago", comment: "Relative time of an item, in minutes")
        }
        let time = timeFormatter.string(from: date)
        if calendar.isDateInToday(date) { return time }
        if calendar.isDateInYesterday(date) {
            return String(
                localized: "Yesterday \(time)",
                comment: "Time of an item copied yesterday, e.g. “Yesterday 23:11”"
            )
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) { return dayFormatter.string(from: date) }
        return yearFormatter.string(from: date)
    }

    static func absolute(_ date: Date) -> String {
        absoluteFormatter.string(from: date)
    }
}
