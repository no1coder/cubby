import Foundation

/// 安全记录（设置 › 剪贴板安全）：本机保存，只存缩写的值
public struct SecurityLogEntry: Codable, Equatable, Identifiable, Sendable {
    public enum Event: String, Codable, Sendable {
        /// 检测到被替换（待处理）
        case tampered
        /// 被替换后用户点了「恢复我复制的地址」
        case restored
        /// 被替换后用户点了「是我自己换的」
        case dismissed
        /// 从 Cubby 粘贴敏感值后核对一致
        case pasteVerified
    }

    public let id: UUID
    public let date: Date
    public let event: Event
    public let kind: SensitiveKind
    /// 缩写后的值（AddressComparison.abbreviated）
    public let summary: String
    /// 当时的前台应用名称
    public let appName: String?
    /// 被替换进来的历史条目（tampered；入历史后补上）
    public let tamperedItemID: UUID?
    /// 这条记录针对的 tampered 记录（restored / dismissed）：「是我自己换的」早于入历史时，
    /// 关联条目时据此一并补上 tamperedItemID。旧版本写入的记录没有该字段，按 nil 解码
    public let relatedEntryID: UUID?

    public init(
        id: UUID = UUID(), date: Date, event: Event, kind: SensitiveKind, summary: String, appName: String?,
        tamperedItemID: UUID? = nil, relatedEntryID: UUID? = nil
    ) {
        self.id = id
        self.date = date
        self.event = event
        self.kind = kind
        self.summary = summary
        self.appName = appName
        self.tamperedItemID = tamperedItemID
        self.relatedEntryID = relatedEntryID
    }
}

extension SecurityLogEntry {
    /// 同一条记录（id 不变）关联到历史条目
    fileprivate func linked(toItem itemID: UUID) -> SecurityLogEntry {
        SecurityLogEntry(
            id: id, date: date, event: event, kind: kind, summary: summary, appName: appName, tamperedItemID: itemID,
            relatedEntryID: relatedEntryID)
    }
}

/// 安全记录列表（不可变，新的在前）：保留 90 天、最多 500 条
public struct SecurityLog: Codable, Equatable, Sendable {
    public static let retention: TimeInterval = 90 * 24 * 3600
    public static let capacity = 500

    public let entries: [SecurityLogEntry]

    public init(entries: [SecurityLogEntry] = []) {
        self.entries = entries
    }

    /// 加一条（新的在前），并按保留期与容量裁剪。仍在禁止中的条目对应的 tampered 记录不裁剪：
    /// 否则 500 条核对记录或 90 天之后，被替换进来的条目会悄悄变回可以粘贴
    public func appending(_ entry: SecurityLogEntry, now: Date) -> SecurityLog {
        let all = [entry] + entries
        let blocked = Self.blockedItems(in: all)
        let isProtected = { (entry: SecurityLogEntry) in
            entry.event == .tampered && entry.tamperedItemID.map(blocked.contains) == true
        }
        let cutoff = now.addingTimeInterval(-Self.retention)
        var kept = all.filter { isProtected($0) || $0.date >= cutoff }
        // 超出容量时从最旧的开始丢，受保护的跳过
        var excess = kept.count - Self.capacity
        if excess > 0 {
            kept = kept.reversed().filter { entry in
                guard excess > 0, !isProtected(entry) else { return true }
                excess -= 1
                return false
            }
            .reversed()
        }
        return SecurityLog(entries: kept)
    }

    /// 把某条 tampered 记录关联到入历史后的条目；已经针对它的 dismissed / restored 记录一并补上条目 ID
    public func linking(entryID: UUID, toItem itemID: UUID) -> SecurityLog {
        SecurityLog(
            entries: entries.map { $0.id == entryID || $0.relatedEntryID == entryID ? $0.linked(toItem: itemID) : $0 })
    }

    /// 被替换进来的历史条目（面板里显示为红色记录，禁止粘贴与复制）。
    /// 用户点了「是我自己换的」（dismissed 记录带同一个条目 ID）后解除；「恢复」后仍然禁止
    public var tamperedItemIDs: Set<UUID> {
        Self.blockedItems(in: entries)
    }

    private static func blockedItems(in entries: [SecurityLogEntry]) -> Set<UUID> {
        let itemIDs = { (event: SecurityLogEntry.Event) in
            Set(entries.lazy.filter { $0.event == event }.compactMap(\.tamperedItemID))
        }
        return itemIDs(.tampered).subtracting(itemIDs(.dismissed))
    }

    /// 近 days 天的统计（设置页顶部）
    public func summary(days: Int = 30, now: Date) -> Summary {
        let cutoff = now.addingTimeInterval(-TimeInterval(days) * Self.secondsPerDay)
        let recent = entries.filter { $0.date >= cutoff }
        return Summary(
            tampered: recent.count { $0.event == .tampered },
            verifiedPastes: recent.count { $0.event == .pasteVerified })
    }

    private static let secondsPerDay: TimeInterval = 24 * 3600

    public struct Summary: Equatable, Sendable {
        public let tampered: Int
        public let verifiedPastes: Int

        public init(tampered: Int, verifiedPastes: Int) {
            self.tampered = tampered
            self.verifiedPastes = verifiedPastes
        }
    }
}
