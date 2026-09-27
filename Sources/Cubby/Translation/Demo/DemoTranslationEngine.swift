#if DEBUG
import CubbyCore
import Foundation

/// 演示翻译引擎（仅调试构建，README 与宣传截图用）：按 DemoTranslationTable 的手写译文逐块返回。
/// 确定性、不联网、不调用系统翻译；表里没有的块原样返回（保持原文），并把原文写到标准错误，便于补表
struct DemoTranslationEngine: TranslationEngine {
    let displayName: String
    /// 每块之间的间隔：让译文像真实引擎一样逐块出现
    let blockDelay: Duration

    var sendsTextOffDevice: Bool {
        false
    }

    func translate(_ blocks: [TextBlock], languages: TranslationLanguages) -> AsyncThrowingStream<
        BlockTranslation, any Error
    > {
        let delay = blockDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for block in blocks {
                        try await Task.sleep(for: delay)
                        let translated = DemoTranslationTable.translation(of: block.text, target: languages.target)
                        if translated == nil { DemoTranslationLog.missing(block.text) }
                        continuation.yield(BlockTranslation(blockID: block.id, text: translated ?? block.text))
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

/// 译文表缺项的提示：写到标准错误（只有在终端里运行调试构建的人能看到），补表时对照原文。
/// 演示场景只处理合成的演示内容，不会出现用户的文字
enum DemoTranslationLog {
    static func missing(_ text: String) {
        let line = "Demo translation: no entry for \"\(text)\" (key \(DemoTranslationTable.key(text)))\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}

/// 演示场景用的翻译服务：截图覆盖层（TranslationProviding）与面板的剪贴板翻译（ClipTranslationProviding）
/// 共用同一个演示引擎。目标语言固定为简体中文，只保存在内存里，不读写用户的翻译设置
@available(macOS 26, *)
@MainActor
final class DemoTranslationProvider: ClipTranslationProviding {
    var targetLanguage: String? = DemoTranslationTable.target
    let selectableLanguages = TranslationLanguageCatalog.selectable(preferred: SystemLanguages.preferred)
    private let engine: DemoTranslationEngine

    init(blockDelay: Duration = .milliseconds(90)) {
        // 显示名与真实的系统翻译一致（界面上是「系统翻译」）：演示代替的正是默认的本机引擎
        let name = SystemTranslationEngine(missingLanguages: MissingLanguagePair()).displayName
        engine = DemoTranslationEngine(displayName: name, blockDelay: blockDelay)
    }

    func makeEngine() -> Result<any TranslationEngine, TranslationFailure> {
        .success(engine)
    }

    func makeClipEngine(prompt: LLMTranslationPrompt.Profile) -> Result<ClipEngine, TranslationFailure> {
        .success(ClipEngine(engine: engine, input: .plainText, host: nil))
    }

    func makeOnDeviceEngine() -> any TranslationEngine {
        engine
    }

    func isInstalled(_ languages: TranslationLanguages) async -> Bool {
        true
    }

    func canResolve(_ failure: TranslationFailure) -> Bool {
        false
    }

    func resolve(_ failure: TranslationFailure) async -> Bool {
        false
    }
}
#endif
