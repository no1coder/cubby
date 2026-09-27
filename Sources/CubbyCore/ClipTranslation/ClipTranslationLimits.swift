import Foundation

/// 译文缓存的上限（docs/CLIP-TRANSLATION-DESIGN.md §2.3，纯逻辑，由 ClipHistory.settingTranslation 执行）。
/// 「字符」一律按 UTF-16 码元计（与 NSString.length 一致）：历史里的长文本也能快速求长度
public struct ClipTranslationLimits: Equatable, Sendable {
    /// 每种语言保存的译文上限：超出只显示、不缓存
    public let maxStoredLength: Int
    /// 每条最多缓存的语言数：超出淘汰最早的
    public let maxLanguagesPerItem: Int
    /// 全部译文的总量上限：超出按 createdAt 淘汰最早的译文（不动条目）；历史文件每次整体重写，控制写放大
    public let maxTotalLength: Int

    public static let standard = ClipTranslationLimits(
        maxStoredLength: 30_000, maxLanguagesPerItem: 3, maxTotalLength: 1_000_000)

    public init(maxStoredLength: Int, maxLanguagesPerItem: Int, maxTotalLength: Int) {
        self.maxStoredLength = maxStoredLength
        self.maxLanguagesPerItem = max(maxLanguagesPerItem, 1)
        self.maxTotalLength = maxTotalLength
    }

    /// 能否缓存到该条目上：只接受文本与图片条目（文本不带译后图片，图片必须带），目标语言非空且未超单语言上限
    public func accepts(_ translation: ClipTranslation, for item: ClipItem) -> Bool {
        guard !translation.target.isEmpty, translation.length <= maxStoredLength else { return false }
        switch item.kind {
        case .text: return translation.imageName == nil
        case .image: return translation.imageName != nil
        case .link, .file, .color: return false
        }
    }

    /// 放入条目已有的译文：同一目标语言原位覆盖，新语言追加在后；超过每条语言数时按 createdAt 淘汰最早的（不淘汰新放入的）
    func inserting(_ translation: ClipTranslation, into existing: ClipTranslations?) -> ClipTranslations {
        let entries = existing?.entries ?? []
        let position = entries.firstIndex { $0.target == translation.target } ?? entries.endIndex
        let merged =
            entries[..<position].filter { $0.target != translation.target } + [translation]
            + entries[position...].filter { $0.target != translation.target }
        let overflow = merged.count - maxLanguagesPerItem
        guard overflow > 0 else { return ClipTranslations(merged) }
        let evicted = Set(
            merged.indices.filter { merged[$0].target != translation.target }
                .sorted { merged[$0].createdAt < merged[$1].createdAt }
                .prefix(overflow))
        return ClipTranslations(merged.indices.filter { !evicted.contains($0) }.map { merged[$0] })
    }

    /// 全部条目的译文总量不超过 maxTotalLength：按 createdAt 淘汰最早的译文，不动条目，也不淘汰 kept 指定的那一条
    func enforcingTotalLength(_ items: [ClipItem], keeping kept: (id: UUID, target: String)) -> [ClipItem] {
        // UTF-8 字节数是 UTF-16 码元数的上界，且对原生字符串是 O(1)：绝大多数情况无需逐段求长度
        guard items.reduce(0, { $0 + $1.translationUTF8Length }) > maxTotalLength else { return items }
        let located = items.flatMap { item in
            (item.translations?.entries ?? []).map { (id: item.id, entry: $0, length: $0.length) }
        }
        let excess = located.reduce(0) { $0 + $1.length } - maxTotalLength
        guard excess > 0 else { return items }
        let oldestFirst =
            located
            .filter { !($0.id == kept.id && $0.entry.target == kept.target) }
            .sorted { $0.entry.createdAt < $1.entry.createdAt }
        let count = oldestFirst.reduce(into: (freed: 0, count: 0)) { state, candidate in
            guard state.freed < excess else { return }
            state = (state.freed + candidate.length, state.count + 1)
        }.count
        let evicted = Dictionary(grouping: oldestFirst.prefix(count), by: \.id).mapValues { $0.map(\.entry) }
        return items.map { item in
            guard let gone = evicted[item.id], let entries = item.translations?.entries else { return item }
            let remaining = entries.filter { !gone.contains($0) }
            return item.withTranslations(remaining.isEmpty ? nil : ClipTranslations(remaining))
        }
    }
}

// MARK: - 译文的派生值

public extension ClipTranslation {
    /// 计入上限的字符数（UTF-16 码元）：各段之和，未翻译的段不计
    var length: Int {
        segments.reduce(0) { $0 + ($1?.utf16.count ?? 0) }
    }

    /// 纯文本（搜索、卡片上的译文首行）：已翻译的段按换行拼接，行内标记（粗体、链接、代码）去掉只留文字
    var plainText: String {
        let texts = segments.compactMap { $0 }
        let plain = usesInlineMarkup == true ? texts.map(ClipInlineMarkup.plainText) : texts
        return plain.joined(separator: "\n")
    }

    /// 替换译后图片的 blob 名，其余字段不变
    func withImageName(_ name: String?) -> ClipTranslation {
        ClipTranslation(
            target: target, source: source, engineName: engineName, isOnDevice: isOnDevice, createdAt: createdAt,
            segmentation: segmentation, segments: segments, usesInlineMarkup: usesInlineMarkup, imageName: name)
    }

    /// UTF-8 字节数（O(1)），UTF-16 码元数的上界
    internal var utf8Length: Int {
        segments.reduce(0) { $0 + ($1?.utf8.count ?? 0) }
    }
}

extension ClipItem {
    fileprivate var translationUTF8Length: Int {
        translations?.entries.reduce(0) { $0 + $1.utf8Length } ?? 0
    }
}
