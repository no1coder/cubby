import Foundation

/// 「测试连接」的结果
public struct LLMConnectionTestResult: Equatable, Sendable {
    /// 「Hello」的译文
    public let translation: String
    public let duration: Duration
}

/// 设置界面的两个探测：获取模型列表、测试连接（§3.6）
public enum LLMServiceProbe {
    /// 模型列表的请求上限
    public static let modelListTimeout: Duration = .seconds(20)
    /// 最多保留的模型数（聚合服务可能返回数百个）
    static let maxModels = 1000

    /// `GET {baseURL}/models`：丢弃不合格的模型名，按名称排序、去重。失败抛出 TranslationFailure（或取消）
    public static func models(
        for endpoint: LLMEndpoint, session: URLSession, timeout: Duration = modelListTimeout
    ) async throws -> [String] {
        let request = LLMHTTP.request(endpoint, path: "models", method: "GET", accept: "application/json")
        do {
            let data = try await LLMHTTP.load(request, session: session, timeout: timeout)
            guard let list = try? JSONDecoder().decode(ModelList.self, from: data) else {
                throw TranslationFailure.invalidResponse
            }
            // 模型名会出现在菜单、翻译条与设置中：不合格的整个丢弃
            let names = Set(list.data.compactMap { LLMModelName.validated($0.id) })
            return Array(names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.prefix(maxModels))
        } catch {
            throw LLMFailureMapping.map(error)
        }
    }

    /// 把一块「Hello」译为目标语言，返回译文与耗时。失败抛出 TranslationFailure（或取消）
    public static func testConnection(
        _ engine: LLMTranslationEngine, target: String
    ) async throws -> LLMConnectionTestResult {
        let started = ContinuousClock.now
        let block = TextBlock(id: 0, lines: [], alignment: .leading, text: "Hello")
        let stream = engine.translate([block], languages: TranslationLanguages(source: "en", target: target))
        for try await translation in stream {
            return LLMConnectionTestResult(translation: translation.text, duration: ContinuousClock.now - started)
        }
        throw TranslationFailure.invalidResponse
    }

    private struct ModelList: Decodable {
        struct Model: Decodable {
            let id: String
        }

        let data: [Model]
    }
}
