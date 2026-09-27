#if DEBUG
import AppKit
import CubbyCore

/// 端到端测试与演示场景的翻译桩：不联网、确定性的流式译文，可注入各种失败
///
/// 译文 = 前缀 + 原文大写：默认目标语言（简体中文）前缀为 "[T] "，其他目标语言为 "[<代码大写>] "（例如 "[JA] "），
/// 换语言重译时一眼可辨
@MainActor
final class E2ETranslationProvider: TranslationProviding {
    /// 引擎的行为
    struct Script: Sendable {
        /// 首包延迟（大模型式）
        var firstDelay: Duration = .zero
        /// 每块之间的延迟
        var blockDelay: Duration = .milliseconds(40)
        /// 到达顺序倒序（验证按 id 放回，不认顺序）
        var reversed = false
        /// 创建引擎就失败（直到 resolve 成功）：未配置、密钥无效、语言包未下载……
        var setupFailure: TranslationFailure?
        /// 送出这么多块之后以 streamFailure 结束（部分失败）；只对第一次请求生效
        var failAfter: Int?
        var streamFailure = TranslationFailure.network
        var sendsTextOffDevice = false
        var engineName = "Stub Translate"
    }

    nonisolated static let defaultTarget = "zh-Hans"

    var targetLanguage: String? = E2ETranslationProvider.defaultTarget
    let selectableLanguages = ["zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es"]
    var script: Script
    /// resolve() 模拟用户在设置里处理所花的时间
    var resolveDelay: Duration = .milliseconds(400)
    /// 每次翻译请求的块 id 与目标语言（验证重试只发缺失的块、换语言不重新识别）
    let log = E2ETranslationLog()
    private(set) var resolveRequests: [TranslationFailure] = []

    init(script: Script = Script()) {
        self.script = script
    }

    nonisolated static func translated(_ text: String, target: String) -> String {
        let tag = target == defaultTarget ? "T" : target.uppercased()
        return "[\(tag)] " + text.uppercased()
    }

    func makeEngine() -> Result<any TranslationEngine, TranslationFailure> {
        if let failure = script.setupFailure {
            return .failure(failure)
        }
        let failAfter = log.requests.isEmpty ? script.failAfter : nil
        return .success(E2EStubEngine(script: script, failAfter: failAfter, log: log))
    }

    func canResolve(_ failure: TranslationFailure) -> Bool {
        [.notConfigured, .unauthorized, .languageNotInstalled].contains(failure)
    }

    /// 模拟用户去设置里配置好（或下载完语言）：之后创建引擎不再失败
    func resolve(_ failure: TranslationFailure) async -> Bool {
        resolveRequests.append(failure)
        try? await Task.sleep(for: resolveDelay)
        script.setupFailure = nil
        return true
    }
}

/// 翻译请求记录（引擎在任意线程调用，内部加锁）
final class E2ETranslationLog: @unchecked Sendable {
    struct Request: Equatable {
        let blockIDs: [Int]
        let target: String
    }

    private let lock = NSLock()
    private var entries: [Request] = []

    var requests: [Request] {
        lock.withLock { entries }
    }

    func append(_ request: Request) {
        lock.withLock { entries.append(request) }
    }
}

/// 桩引擎：按脚本的延迟逐块返回
struct E2EStubEngine: TranslationEngine {
    let script: E2ETranslationProvider.Script
    let failAfter: Int?
    let log: E2ETranslationLog

    var displayName: String { script.engineName }
    var sendsTextOffDevice: Bool { script.sendsTextOffDevice }

    func translate(_ blocks: [TextBlock], languages: TranslationLanguages) -> AsyncThrowingStream<
        BlockTranslation, any Error
    > {
        log.append(E2ETranslationLog.Request(blockIDs: blocks.map(\.id), target: languages.target))
        let ordered = script.reversed ? Array(blocks.reversed()) : blocks
        let script = script
        let failAfter = failAfter
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Task.sleep(for: script.firstDelay)
                    for (index, block) in ordered.enumerated() {
                        if let failAfter, index >= failAfter {
                            throw script.streamFailure
                        }
                        try await Task.sleep(for: script.blockDelay)
                        let text = E2ETranslationProvider.translated(block.text, target: languages.target)
                        continuation.yield(BlockTranslation(blockID: block.id, text: text))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// 桩识别器：返回落在夹具文字上的确定性块（选区内的才返回），可设延迟；记录调用次数
final class E2EStubRecognizer: TranslationTextRecognizing, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let delay: Duration

    init(delay: Duration = .milliseconds(150)) {
        self.delay = delay
    }

    /// 识别次数（换语言不应重新识别）
    var calls: Int {
        lock.withLock { count }
    }

    func blocks(in frame: FrozenFrame, selection: CGRect) async throws -> [TextBlock] {
        lock.withLock { count += 1 }
        try await Task.sleep(for: delay)
        let all = E2ETranslationFixture.blocks(on: frame.screen)
        let inside = all.filter { selection.intersects($0.frame) }
        return inside.enumerated().map { index, block in
            TextBlock(id: index, lines: block.lines, alignment: block.alignment, text: block.text)
        }
    }
}

/// 夹具画面（FixturePainter）底部文字行上的块：拉丁句子拆成三块（其中一块是纯数字），加上中英混排的一行
enum E2ETranslationFixture {
    /// 与 FixturePainter 相同的文字与位置（局部点：距屏幕底边 200 / 176 pt，字号 15）
    static let fontSize: CGFloat = 15
    static let latinWords = ["The quick brown fox", "jumps over the lazy dog", "0123456789"]
    static let cjkLine = "\u{622A}\u{56FE}\u{6D4B}\u{8BD5} Cubby Fixture"
    static let left: CGFloat = 24
    static let latinFromBottom: CGFloat = 200
    static let cjkFromBottom: CGFloat = 176

    static func blocks(on screen: CaptureScreen) -> [TextBlock] {
        let height = TextLayout.size(of: "Hg", fontSize: fontSize, maxWidth: .infinity).height
        let space =
            TextLayout.size(of: "a b", fontSize: fontSize, maxWidth: .infinity).width
            - TextLayout.size(of: "ab", fontSize: fontSize, maxWidth: .infinity).width
        var x = left
        var lines: [RecognizedLine] = []
        for word in latinWords {
            let width = TextLayout.size(of: word, fontSize: fontSize, maxWidth: .infinity).width
            let local = CGRect(x: x, y: screen.frame.height - latinFromBottom, width: width, height: height)
            lines.append(
                RecognizedLine(text: word, frame: local.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)))
            x += width + space
        }
        let cjkWidth = TextLayout.size(of: cjkLine, fontSize: fontSize, maxWidth: .infinity).width
        let cjk = CGRect(x: left, y: screen.frame.height - cjkFromBottom, width: cjkWidth, height: height)
        lines.append(RecognizedLine(text: cjkLine, frame: cjk.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)))
        return lines.enumerated().map { index, line in
            TextBlock(id: index, lines: [line], alignment: .leading, text: line.text)
        }
    }
}
#endif
