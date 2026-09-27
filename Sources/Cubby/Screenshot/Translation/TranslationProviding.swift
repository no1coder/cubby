import CoreGraphics
import CubbyCore

// 截图翻译在 App 层的契约（docs/TRANSLATION-DESIGN.md §4.3）。修改需经协调者同意。

/// 截图覆盖层取得「翻译设置 + 引擎」的入口。
/// T2 提供正式实现，在 AppDelegate 里赋给 `ScreenshotCoordinator.translation`；T1 使用，E2E 用桩
@MainActor
protocol TranslationProviding: AnyObject {
    /// 用户选定的目标语言（BCP-47）；nil = 自动（规则见设计文档 §3.4）。翻译条的语言选单读写它，会持久化
    var targetLanguage: String? { get set }
    /// 语言选单的候选（BCP-47，按显示顺序）
    var selectableLanguages: [String] { get }
    /// 按当前设置创建引擎（设置里选了大模型且已配置 → 大模型；否则系统翻译）；不可用时给出原因
    func makeEngine() -> Result<any TranslationEngine, TranslationFailure>
    /// 该失败能否由用户去某处解决（未配置 / 密钥无效 → 设置；语言包未下载 → 下载）
    func canResolve(_ failure: TranslationFailure) -> Bool
    /// 带用户去解决（打开「设置 › 翻译」或系统的语言包下载），在用户处理完后返回（设置窗口关闭 / 下载结束或取消）。
    /// 返回 true 表示值得重试。调用方在此期间暂停覆盖层（与存储对话框相同的暂停 / 恢复机制）
    func resolve(_ failure: TranslationFailure) async -> Bool
}

/// 截图翻译的文字识别与分块（T3 提供正式实现，基于 macOS 26 的 Vision 文档识别）
protocol TranslationTextRecognizing: Sendable {
    /// 识别选区（全局点）内的文字，按版面分块；块 id 从 0 起按阅读顺序连续编号；
    /// 行坐标为全局点、左上原点。没有文字时返回空数组；任务取消时抛出 CancellationError
    func blocks(in frame: FrozenFrame, selection: CGRect) async throws -> [TextBlock]
}
