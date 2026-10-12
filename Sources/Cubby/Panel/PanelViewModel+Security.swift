import AppKit
import CubbyCore

/// 卡片上的地址守护标记（PanelSecurity 设计稿）
enum CardSecurityMarker: Equatable {
    /// 识别出的敏感值；isGuarded 为当前守护的那一条（「守护中」，其余为「已核验」）
    case sensitive(SensitiveValue, isGuarded: Bool)
    /// 被替换进来的条目：红色记录，不能粘贴或复制，不参与 ⌘1–⌘9
    case tampered

    var isTampered: Bool { self == .tampered }
}

/// 敏感值识别的缓存（按条目 ID + 内容指纹）：卡片在每次列表重算时都会求值，识别只做一次；守护的类型变了整体清空
@MainActor
final class SensitiveValueCache {
    private var kinds: Set<SensitiveKind> = []
    private var values: [UUID: (hash: String, value: SensitiveValue?)] = [:]

    func value(for item: ClipItem, kinds: Set<SensitiveKind>) -> SensitiveValue? {
        guard case .text(let text) = item.payload, item.kind != .link, item.kind != .color else { return nil }
        if kinds != self.kinds {
            values.removeAll()
            self.kinds = kinds
        }
        if let cached = values[item.id], cached.hash == item.contentHash { return cached.value }
        let value = SensitiveTextClassifier.classify(text, kinds: kinds)
        values[item.id] = (item.contentHash, value)
        return value
    }

    /// 只保留仍在历史里的条目（删除、清空后丢掉识别结果）；守护关闭时整体清空
    func prune(keeping itemIDs: Set<UUID>?) {
        guard let itemIDs else {
            values.removeAll()
            return
        }
        values = values.filter { itemIDs.contains($0.key) }
    }
}

// 面板里的地址守护（docs/UI-UPGRADE-PLAN.md §6.3，按用户决定：被替换进来的条目完全禁止粘贴与复制，没有确认浮层）
extension PanelViewModel {
    static let quickPasteCount = 9

    /// 被替换进来、还没被认领的条目
    var blockedItemIDs: Set<UUID> {
        security?.blockedItemIDs ?? []
    }

    func isBlocked(_ item: ClipItem) -> Bool {
        blockedItemIDs.contains(item.id)
    }

    /// 被替换进来的条目：提示音 + 底栏说明，返回 true 表示已拦下
    func rejectIfBlocked(_ itemID: UUID) -> Bool {
        guard blockedItemIDs.contains(itemID) else { return false }
        NSSound.beep()
        showToast(.info(SecurityCopy.blocked, symbolName: "exclamationmark.shield.fill"))
        return true
    }

    /// ⌘1–⌘9 的编号：跳过被替换进来的条目（id → 从 0 开始的序号）
    func quickPasteIndices(_ items: [ClipItem]) -> [UUID: Int] {
        let blocked = blockedItemIDs
        var result: [UUID: Int] = [:]
        for item in items where !blocked.contains(item.id) {
            guard result.count < Self.quickPasteCount else { break }
            result[item.id] = result.count
        }
        return result
    }

    /// ⌘N 对应的条目（与卡片上的键帽一致）
    func quickPasteItem(at index: Int) -> ClipItem? {
        let blocked = blockedItemIDs
        let candidates = items.lazy.filter { !blocked.contains($0.id) }
        return candidates.dropFirst(index).first
    }

    /// 卡片上的标记；守护关闭时只保留被替换的红色记录
    func securityMarker(for item: ClipItem) -> CardSecurityMarker? {
        guard let security else { return nil }
        if security.blockedItemIDs.contains(item.id) { return .tampered }
        guard security.isEnabled,
            let value = sensitiveValues.value(for: item, kinds: settings.guardedKinds)
        else { return nil }
        return .sensitive(value, isGuarded: security.guardedValue?.isSame(as: value) == true)
    }

    /// 红色记录上的「详情」：重新打开警示卡（原值已不在内存里时打开设置 › 剪贴板安全）
    func showTamperDetails(_ item: ClipItem) {
        onShowTamperDetails?(item.id)
    }
}
