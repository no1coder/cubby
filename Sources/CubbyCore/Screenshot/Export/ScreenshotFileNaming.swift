import Foundation

/// 截图文件名：`Cubby 2026-09-27 01.23.45.png`；固定 24 小时制、公历、ASCII 数字，不随地区变化
public enum ScreenshotFileNaming {
    /// 文件名前缀（品牌名，不本地化）
    public static let prefix = "Cubby"
    /// 文件扩展名
    public static let pathExtension = "png"
    /// 数字后缀的上限；超过后改用 UUID，保证有限步结束
    private static let maxNumberedSuffix = 9_999

    /// "Cubby 2026-09-27 01.23.45.png"
    public static func fileName(date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let value = { (component: Calendar.Component) in calendar.component(component, from: date) }
        let stamp = String(
            format: "%04d-%02d-%02d %02d.%02d.%02d",
            locale: Locale(identifier: "en_US_POSIX"),
            value(.year),
            value(.month),
            value(.day),
            value(.hour),
            value(.minute),
            value(.second)
        )
        return "\(prefix) \(stamp).\(pathExtension)"
    }

    /// 目录中不冲突的 URL：存在则追加 " 2"、" 3"…（exists 注入便于测试）
    public static func uniqueURL(in directory: URL, fileName: String, exists: (URL) -> Bool) -> URL {
        let candidate = directory.appendingPathComponent(fileName)
        guard exists(candidate) else { return candidate }

        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        let named = { (suffix: String) -> URL in
            let name = ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
            return directory.appendingPathComponent(name)
        }
        for number in 2...maxNumberedSuffix {
            let url = named(String(number))
            if !exists(url) { return url }
        }
        return named(UUID().uuidString)
    }
}
