import Foundation

/// 晾衣绳设置的取值规则（docs/UI-UPGRADE-PLAN.md 第 5 节）
public extension AppSettings {
    /// 「指针停在顶边多久后滑下」的默认值（秒）
    nonisolated static let defaultClotheslineDwell: TimeInterval = 0.5

    /// 设置里可选的停留时长（秒），从短到长
    nonisolated static let clotheslineDwellChoices: [TimeInterval] = [0.3, 0.5, 0.8, 1.2]

    /// 接受的停留时长范围（秒）：太短会在指针掠过顶边时误触发，太长就感觉不到；范围外回到默认值
    nonisolated static let clotheslineDwellRange: ClosedRange<TimeInterval> = 0.1...3.0

    /// 读取存储的停留时长：不是数字（含字符串、布尔值）、缺失或超出范围时回到默认值
    internal nonisolated static func storedClotheslineDwell(_ stored: Any?) -> TimeInterval {
        // 布尔值在 UserDefaults 里也是 NSNumber，单独排除
        guard let number = stored as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return defaultClotheslineDwell
        }
        let value = number.doubleValue
        return clotheslineDwellRange.contains(value) ? value : defaultClotheslineDwell
    }
}
