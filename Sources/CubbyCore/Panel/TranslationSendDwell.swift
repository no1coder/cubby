import Foundation

/// 发往云端引擎前的停留（docs/CLIP-TRANSLATION-DESIGN.md A3、A4）：翻译卡跟随选中项、列表中按住 ⌥ 预览都要
/// 在一条上停留满 `cloud` 才发送，快速翻过或 ⌥ 只是组合键的一部分（⌥↑、⌥↓、⌥ 点按）时不会发出去。
/// 本机引擎与缓存命中不联网，不停留
public enum TranslationSendDwell {
    /// 云端引擎发送前的总停留
    public static let cloud: Duration = .milliseconds(600)

    /// 还要再等多久才发送；elapsed 为已经停留的时间（按住 ⌥ 的 300 ms 计入）
    public static func remaining(
        sendsTextOffDevice: Bool, isCached: Bool, elapsed: Duration, total: Duration = cloud
    ) -> Duration {
        guard sendsTextOffDevice, !isCached else { return .zero }
        return max(total - elapsed, .zero)
    }
}
