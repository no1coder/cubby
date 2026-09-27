import CoreGraphics
import Foundation

// 截图翻译的跨模块契约（docs/TRANSLATION-DESIGN.md §4）。
// 这里只放三条实现线共用的类型与协议；修改需经协调者同意，实现放在各自拥有的文件里。

/// OCR 识别出的一行文字。坐标与标注一致：全局点，左上原点
public struct RecognizedLine: Equatable, Sendable {
    public let text: String
    public let frame: CGRect

    public init(text: String, frame: CGRect) {
        self.text = text
        self.frame = frame
    }
}

/// 一段文字的水平对齐方式（由各行左 / 中 / 右边缘推断）
public enum TextBlockAlignment: Equatable, Sendable {
    case leading
    case center
    case trailing
}

/// 一个翻译单元：按版面合并的若干行（一个段落，或一个界面标签）。
/// 译文按 id 对回原位，引擎不需要也不应该理解坐标
public struct TextBlock: Equatable, Sendable, Identifiable {
    public let id: Int
    /// 从上到下
    public let lines: [RecognizedLine]
    public let alignment: TextBlockAlignment
    /// 送去翻译的原文：行按文字规则拼接（拉丁文字以空格连接并去掉行尾连字符，CJK 直接相连）
    public let text: String

    public init(id: Int, lines: [RecognizedLine], alignment: TextBlockAlignment, text: String) {
        self.id = id
        self.lines = lines
        self.alignment = alignment
        self.text = text
    }

    /// 各行外框的并集
    public var frame: CGRect {
        lines.dropFirst().reduce(lines.first?.frame ?? .null) { $0.union($1.frame) }
    }
}

/// 一块的译文
public struct BlockTranslation: Equatable, Sendable {
    public let blockID: Int
    public let text: String

    public init(blockID: Int, text: String) {
        self.blockID = blockID
        self.text = text
    }
}

/// 语言对：BCP-47 标识（例如 "en"、"zh-Hans"、"ja"）；source 为 nil 表示自动检测
public struct TranslationLanguages: Equatable, Sendable {
    public let source: String?
    public let target: String

    public init(source: String?, target: String) {
        self.source = source
        self.target = target
    }
}

/// 翻译失败的原因（界面按此给出可操作的提示；不携带原文或密钥）
public enum TranslationFailure: Error, Equatable, Sendable {
    /// 没有可用的引擎（未配置大模型，且系统翻译不可用）
    case notConfigured
    /// 密钥无效或无权限（401 / 403）
    case unauthorized
    /// 频率或额度受限（429）
    case rateLimited
    /// 离线、超时、无法连接
    case network
    /// 服务端错误（5xx 等）
    case server(status: Int)
    /// 语言对不受支持
    case unsupportedLanguages
    /// 系统翻译的语言包尚未下载
    case languageNotInstalled
    /// 返回内容无法解析
    case invalidResponse
}

/// 翻译引擎：系统翻译（本机）或兼容 OpenAI 接口的大模型
public protocol TranslationEngine: Sendable {
    /// 界面上显示的引擎名（例如「系统翻译」「DeepSeek」），用于告知用户文字发往何处
    var displayName: String { get }
    /// 是否把文字发送到本机以外
    var sendsTextOffDevice: Bool { get }
    /// 按块流式返回译文：顺序不限；同一块至多返回一次；未返回的块保留原文。
    /// 出错时以 TranslationFailure 结束；任务取消时尽快结束
    func translate(_ blocks: [TextBlock], languages: TranslationLanguages) -> AsyncThrowingStream<
        BlockTranslation, any Error
    >
}
