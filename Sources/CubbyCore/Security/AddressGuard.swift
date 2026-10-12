import Foundation

/// 地址守护的状态机（docs/UI-UPGRADE-PLAN.md §6.2）：纯值类型，App 层喂事件、按结果更新界面。
/// 记住最近一次用户复制的敏感值；剪贴板在时间窗内变成另一个同类型的值、前台应用没变、
/// 且（有输入监控时）期间没有按过 ⌘C / ⌘X，就判定为被替换
public struct AddressGuard: Equatable, Sendable {
    public static let defaultWindow: TimeInterval = 10
    /// 没有输入监控时的时间窗：看不到 ⌘C / ⌘X，用户在同一个应用里连续复制两个地址很常见，窗口放宽会误报
    /// （而误报会让第二个合法的值被完全禁止），所以只看极短时间内的替换
    public static let windowWithoutKeystrokes: TimeInterval = 1.5

    /// 用户复制的敏感值与当时的环境
    public struct Copy: Equatable, Sendable {
        public let value: SensitiveValue
        public let date: Date
        /// 复制时的前台应用（bundle ID）
        public let frontmostBundleID: String?
        public let source: SourceApp?
        /// 复制时剪贴板上的原文（含首尾空白、银行卡号的分隔符）：「恢复」原样写回；不知道时为 nil
        public let text: String?

        public init(
            value: SensitiveValue, date: Date, frontmostBundleID: String?, source: SourceApp?, text: String? = nil
        ) {
            self.value = value
            self.date = date
            self.frontmostBundleID = frontmostBundleID
            self.source = source
            self.text = text
        }

        /// 「恢复」要写回的文本：原文，不知道时用规范化后的值
        public var restorableText: String {
            text ?? value.value
        }
    }

    /// 判定为被替换
    public struct Tamper: Equatable, Sendable {
        public let original: Copy
        public let replacement: SensitiveValue
        public let date: Date
        public let frontmostBundleID: String?
        /// 有输入监控、确认期间没有按过 ⌘C / ⌘X
        public let checkedKeystrokes: Bool
        /// 替换进来的原文（「是我自己换的」之后作为守护对象的原文）
        public let replacementText: String?

        public init(
            original: Copy, replacement: SensitiveValue, date: Date, frontmostBundleID: String?,
            checkedKeystrokes: Bool, replacementText: String? = nil
        ) {
            self.original = original
            self.replacement = replacement
            self.date = date
            self.frontmostBundleID = frontmostBundleID
            self.checkedKeystrokes = checkedKeystrokes
            self.replacementText = replacementText
        }

        /// 从复制到被替换经过的秒数
        public var elapsed: TimeInterval {
            date.timeIntervalSince(original.date)
        }
    }

    public struct Configuration: Equatable, Sendable {
        public var kinds: Set<SensitiveKind>
        public var window: TimeInterval
        /// 有输入监控权限（能看到 ⌘C / ⌘X）
        public var monitorsKeystrokes: Bool

        public init(
            kinds: Set<SensitiveKind> = Set(SensitiveKind.allCases), window: TimeInterval = AddressGuard.defaultWindow,
            monitorsKeystrokes: Bool = false
        ) {
            self.kinds = kinds
            self.window = window
            self.monitorsKeystrokes = monitorsKeystrokes
        }

        /// App 使用的配置：有输入监控时 10 秒，没有时 1.5 秒（windowWithoutKeystrokes）
        public static func recommended(kinds: Set<SensitiveKind>, monitorsKeystrokes: Bool) -> Configuration {
            Configuration(
                kinds: kinds,
                window: monitorsKeystrokes ? AddressGuard.defaultWindow : AddressGuard.windowWithoutKeystrokes,
                monitorsKeystrokes: monitorsKeystrokes)
        }
    }

    public enum Event: Equatable, Sendable {
        /// 剪贴板变了（不是 Cubby 自己写的）：text 为纯文本内容，没有文本时为 nil
        case pasteboardChanged(text: String?, date: Date, frontmostBundleID: String?, source: SourceApp?)
        /// Cubby 自己写入剪贴板（从面板粘贴 / 复制、警示卡「恢复」）：写入的是敏感值时成为新的守护对象
        case cubbyWrote(text: String, date: Date, frontmostBundleID: String?)
        /// 输入监控看到 ⌘C 或 ⌘X
        case copyKeystroke(date: Date)
        /// 警示卡「是我自己换的」：把替换后的值当作用户复制的
        case acceptedReplacement(Tamper)
    }

    public enum Outcome: Equatable, Sendable {
        case none
        /// 开始守护一个新复制的敏感值
        case guarding(Copy)
        case tampered(Tamper)
    }

    public private(set) var configuration: Configuration
    /// 当前守护的值（最近一次用户复制的敏感值）
    public private(set) var guarded: Copy?
    /// 守护开始后最近一次 ⌘C / ⌘X
    public private(set) var lastCopyKeystroke: Date?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func configured(_ configuration: Configuration) -> AddressGuard {
        var copy = self
        copy.configuration = configuration
        return copy
    }

    /// 处理一个事件，返回新状态与结果
    public func handling(_ event: Event) -> (AddressGuard, Outcome) {
        switch event {
        case .pasteboardChanged(let text, let date, let frontmostBundleID, let source):
            let value = text.flatMap { SensitiveTextClassifier.classify($0, kinds: configuration.kinds) }
            return pasteboardChanged(
                to: value, text: text, date: date, frontmostBundleID: frontmostBundleID, source: source)
        case .cubbyWrote(let text, let date, let frontmostBundleID):
            guard let value = SensitiveTextClassifier.classify(text, kinds: configuration.kinds) else {
                return (with(guarded: nil), .none)
            }
            return startGuarding(
                Copy(value: value, date: date, frontmostBundleID: frontmostBundleID, source: nil, text: text))
        case .copyKeystroke(let date):
            var next = self
            next.lastCopyKeystroke = date
            return (next, .none)
        case .acceptedReplacement(let tamper):
            return startGuarding(
                Copy(
                    value: tamper.replacement, date: tamper.date, frontmostBundleID: tamper.frontmostBundleID,
                    source: nil, text: tamper.replacementText))
        }
    }

    private func pasteboardChanged(
        to value: SensitiveValue?, text: String?, date: Date, frontmostBundleID: String?, source: SourceApp?
    ) -> (AddressGuard, Outcome) {
        guard let value else {
            return (with(guarded: nil), .none)
        }
        if let guarded {
            if isTamper(of: guarded, by: value, date: date, frontmostBundleID: frontmostBundleID) {
                let tamper = Tamper(
                    original: guarded, replacement: value, date: date, frontmostBundleID: frontmostBundleID,
                    checkedKeystrokes: configuration.monitorsKeystrokes, replacementText: text)
                // 继续守护原值：再被换成第三个值时仍按原值判定
                return (self, .tampered(tamper))
            }
            if value.isSame(as: guarded.value) {
                // 用户又复制了一次同一个值：只刷新时间（原文取最新一次），来源与前台应用沿用第一次
                let refreshed = Copy(
                    value: guarded.value, date: date, frontmostBundleID: guarded.frontmostBundleID,
                    source: guarded.source, text: text)
                return (with(guarded: refreshed), .none)
            }
        }
        return startGuarding(
            Copy(value: value, date: date, frontmostBundleID: frontmostBundleID, source: source, text: text))
    }

    /// 同类型的另一个值、在时间窗内（含边界，不接受时间倒流）、前台应用没变、
    /// 且（有输入监控时）守护开始后没有按过 ⌘C / ⌘X
    private func isTamper(of guarded: Copy, by value: SensitiveValue, date: Date, frontmostBundleID: String?) -> Bool {
        let elapsed = date.timeIntervalSince(guarded.date)
        guard value.kind == guarded.value.kind, !value.isSame(as: guarded.value),
            elapsed >= 0, elapsed <= configuration.window,
            frontmostBundleID == guarded.frontmostBundleID
        else { return false }
        guard configuration.monitorsKeystrokes, let lastCopyKeystroke else { return true }
        return lastCopyKeystroke < guarded.date
    }

    private func startGuarding(_ copy: Copy) -> (AddressGuard, Outcome) {
        (with(guarded: copy), .guarding(copy))
    }

    /// 换守护对象，同时清掉记录的按键（按键只对当前守护对象有意义）
    private func with(guarded: Copy?) -> AddressGuard {
        var next = self
        next.guarded = guarded
        next.lastCopyKeystroke = nil
        return next
    }
}
