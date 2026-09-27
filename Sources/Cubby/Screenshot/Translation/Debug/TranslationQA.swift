#if DEBUG
import AppKit
import CubbyCore
import Foundation

/// 截图翻译视觉验收：`Cubby --translate-qa <corpus.json> <outdir>`（仅调试构建）
///
/// 用合成语料跑真实流水线（识别 → 分块 → 候选 → 版面 → 绘制），把原图 / 译文 / 对比图 / 调试图与 index.html
/// 写到 outdir，然后退出。只处理合成图片：不截屏、不读剪贴板、不联网。
enum TranslationQA {
    private static let argument = "--translate-qa"

    /// 命令行请求：语料路径与输出目录；没有 --translate-qa 时为 nil
    static var requested: (corpus: URL, output: URL)? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 2) else { return nil }
        return (URL(fileURLWithPath: arguments[index + 1]), URL(fileURLWithPath: arguments[index + 2]))
    }

    /// 异步运行，结束时以退出码 0（全部场景完成）或 1 退出进程
    static func launch(_ request: (corpus: URL, output: URL)) {
        Task.detached {
            let code = await run(corpus: request.corpus, output: request.output)
            exit(code)
        }
    }

    private static func run(corpus: URL, output: URL) async -> Int32 {
        do {
            let scenes = try JSONDecoder().decode(TranslationQACorpus.self, from: Data(contentsOf: corpus)).scenes
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let only = ProcessInfo.processInfo.environment["CUBBY_QA_SCENES"]?.split(separator: ",").map(String.init)
            var results: [TranslationQARunner.SceneResult] = []
            for scene in scenes where only?.contains(scene.id) ?? true {
                guard let result = try await TranslationQARunner.run(scene) else {
                    print("QA: \(scene.id): cannot render")
                    return 1
                }
                try TranslationQAReport.writeImages(result, to: output)
                print(TranslationQAReport.summaryLine(result))
                results.append(result)
            }
            try TranslationQAReport.writeIndex(results, to: output)
            print("QA: \(results.count) scenes → \(output.path)/index.html")
            return 0
        } catch {
            print("QA: failed: \(error)")
            return 1
        }
    }
}
#endif
