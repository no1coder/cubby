import Foundation

/// 历史数据无法按任何已知格式读取的原因
public enum HistoryMigrationError: Error, Equatable, Sendable {
    /// 不是合法的历史 JSON：无法解析、结构不符或版本号非法
    case malformed
    /// 由更新版本的 Cubby 写入，版本号高于当前支持的版本
    case unsupportedVersion(found: Int)
}

/// 历史文件的格式版本识别与逐级迁移（纯函数，不接触文件系统）。
///
/// 版本记录：
/// - v0：v0.1 写入的 `{"items":[...]}`，没有 `schemaVersion` 字段
/// - v1：顶层增加 `schemaVersion`，items 结构与 v0 相同
///
/// 新增 v2 时只需在 `steps` 末尾追加一个 v1 → v2 的转换，`currentVersion` 随之递增；
/// 新字段一律使用 Optional + `decodeIfPresent`，能不迁移就不迁移。
public enum HistoryMigrator {
    /// 一次读取的结果
    public struct Outcome: Equatable, Sendable {
        public let history: ClipHistory
        /// 原始数据的格式版本
        public let sourceVersion: Int

        public init(history: ClipHistory, sourceVersion: Int = HistoryMigrator.currentVersion) {
            self.history = history
            self.sourceVersion = sourceVersion
        }

        /// 是否从旧版本迁移而来：为 true 时应以当前版本重新保存
        public var didMigrate: Bool {
            sourceVersion < HistoryMigrator.currentVersion
        }
    }

    /// 单步迁移：输入版本 N 的顶层 JSON 对象，返回版本 N+1 的对象（版本号由迁移链统一写入）
    typealias Step = @Sendable (_ object: [String: Any]) throws -> [String: Any]

    /// steps[n] 负责 v(n) → v(n+1)，数组长度即当前版本号
    static let steps: [Step] = [
        // v0 → v1：items 结构不变，仅新增顶层 schemaVersion
        { $0 }
    ]

    /// 当前写入的格式版本
    public static var currentVersion: Int {
        steps.count
    }

    /// 识别版本并逐级迁移到当前版本
    public static func migrate(_ data: Data) throws(HistoryMigrationError) -> Outcome {
        try migrate(data, steps: steps)
    }

    /// 按当前版本整块编码（始终带 schemaVersion）。保存走下面的流式版本，二者输出逐字节相同
    public static func encode(_ history: ClipHistory) throws -> Data {
        try makeEncoder().encode(CurrentFile(history: history))
    }

    /// 流式编码时每攒够这么多字节交给 sink 一次：减少写入的系统调用，又不为整份历史分配连续缓冲
    public static let streamingChunkSize = 256 * 1024

    /// 按当前版本流式编码：逐条编码条目，按块交给 sink，输出与 encode(_:) 逐字节相同。
    /// 整块编码会为 26MB 级的历史一次性分配同等大小的缓冲，释放后仍滞留在进程 footprint 中；
    /// 流式编码的峰值只有一个块加上最大的单个条目。
    public static func encode(
        _ history: ClipHistory,
        chunkSize: Int = streamingChunkSize,
        into sink: (Data) throws -> Void
    ) throws {
        let encoder = makeEncoder()
        var chunk = Data(streamingHeader.utf8)
        for (index, item) in history.items.enumerated() {
            if index > 0 { chunk.append(UInt8(ascii: ",")) }
            // 及时释放单条编码产生的临时对象，避免在一次保存内累积
            try autoreleasepool { chunk.append(try encoder.encode(item)) }
            if chunk.count >= chunkSize {
                try sink(chunk)
                chunk.removeAll(keepingCapacity: true)
            }
        }
        chunk.append(contentsOf: streamingFooter.utf8)
        try sink(chunk)
    }

    /// 以指定迁移链识别并迁移，目标版本为 steps.count（测试可注入模拟的多步链）
    static func migrate(_ data: Data, steps: [Step]) throws(HistoryMigrationError) -> Outcome {
        let target = steps.count
        let envelope = try decode(Envelope.self, from: data, targetVersion: target)
        if let history = envelope.current {
            return Outcome(history: history, sourceVersion: envelope.version)
        }
        guard envelope.version < target else {
            throw .unsupportedVersion(found: envelope.version)
        }
        let upgraded = try upgrade(data, from: envelope.version, through: steps)
        // 迁移链的产物必须能被当前版本的解码逻辑读取
        let history = try decode(CurrentItems.self, from: upgraded, targetVersion: target).history
        return Outcome(history: history, sourceVersion: envelope.version)
    }

    // MARK: - 内部实现

    /// 通过 userInfo 把目标版本传给 Envelope，使其只在版本相符时解码条目
    private static let targetVersionKey: CodingUserInfoKey = {
        guard let key = CodingUserInfoKey(rawValue: "io.github.no1coder.Cubby.targetSchemaVersion") else {
            preconditionFailure("Invalid CodingUserInfoKey")
        }
        return key
    }()

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        targetVersion: Int
    ) throws(HistoryMigrationError) -> T {
        let decoder = JSONDecoder()
        decoder.userInfo = [targetVersionKey: targetVersion]
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw .malformed
        }
    }

    /// 旧版本：转为通用 JSON 对象，依次执行 steps[version...]，每步之后写入新的版本号
    private static func upgrade(
        _ data: Data,
        from version: Int,
        through steps: [Step]
    ) throws(HistoryMigrationError) -> Data {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HistoryMigrationError.malformed
            }
            let migrated = try steps[version...].enumerated().reduce(object) { partial, step in
                let stamp = [FileKeys.schemaVersion.rawValue: version + step.offset + 1]
                return try step.element(partial).merging(stamp) { _, new in new }
            }
            // 步骤可能放入无法序列化的值，提前校验以免 JSONSerialization 触发 Objective-C 异常
            guard JSONSerialization.isValidJSONObject(migrated) else {
                throw HistoryMigrationError.malformed
            }
            return try JSONSerialization.data(withJSONObject: migrated)
        } catch {
            throw .malformed
        }
    }

    private enum FileKeys: String, CodingKey {
        case schemaVersion
        case items
    }

    /// 整块与流式编码共用的编码器。按键名排序：JSONEncoder 默认的键序取决于字典的随机种子，
    /// 同一份历史每次保存的字节都可能不同；排序后输出确定，流式输出才能与整块编码逐字节对照（实测无额外耗时）
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// 流式编码的外层结构，与 CurrentFile 按排序键编码的结果一致：{"items":[…],"schemaVersion":N}
    private static var streamingHeader: String {
        "{\"\(FileKeys.items.rawValue)\":["
    }

    private static var streamingFooter: String {
        "],\"\(FileKeys.schemaVersion.rawValue)\":\(currentVersion)}"
    }

    /// 文件外层：先读版本号，仅在等于目标版本时才解码条目（更高版本的条目结构可能无法解码）
    private struct Envelope: Decodable {
        let version: Int
        let current: ClipHistory?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: FileKeys.self)
            // 缺失（或为 null）视为 v0
            let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
            guard version >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .schemaVersion, in: container, debugDescription: "Schema version must not be negative"
                )
            }
            let target = decoder.userInfo[HistoryMigrator.targetVersionKey] as? Int ?? HistoryMigrator.currentVersion
            self.version = version
            self.current = version == target ? try CurrentItems(from: decoder).history : nil
        }
    }

    /// 当前版本的条目结构（解码）
    private struct CurrentItems: Decodable {
        let history: ClipHistory

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: FileKeys.self)
            history = ClipHistory(items: try container.decode([ClipItem].self, forKey: .items))
        }
    }

    /// 当前版本的文件结构（编码），与解码共用同一组键名
    private struct CurrentFile: Encodable {
        let history: ClipHistory

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: FileKeys.self)
            try container.encode(HistoryMigrator.currentVersion, forKey: .schemaVersion)
            try container.encode(history.items, forKey: .items)
        }
    }
}
