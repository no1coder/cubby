#if DEBUG
import CubbyCore
import Foundation
import Security

/// 调试走查（--scenario settings:translation）用的假数据：只在内存里，不接触钥匙串，也不请求真实服务
@MainActor
enum DebugTranslationFixtures {
    /// `--fake-translation-key <预设 id>`：为该预设预置一个明显的假密钥（绑定到该预设的默认地址，用于查看掩码显示）
    static var fakeKeys: [String: LLMStoredKey] {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--fake-translation-key"), arguments.indices.contains(index + 1),
            let preset = LLMProviderPreset.preset(id: arguments[index + 1]),
            let url = URL(string: preset.defaultBaseURL)
        else { return [:] }
        return [preset.id: LLMStoredKey(key: "sk-fake-cubby-walkthrough-0000", boundTo: url)]
    }

    /// `--fake-keychain-failure`：内存密钥存储的每次读写都失败（模拟用户拒绝访问钥匙串）
    static var simulatesKeychainFailure: Bool {
        CommandLine.arguments.contains("--fake-keychain-failure")
    }

    /// 总是失败的后端
    final class UnavailableBackend: LLMSecretBackend {
        func read(account: String) throws -> Data? {
            throw KeychainError(status: errSecAuthFailed)
        }

        func write(_ data: Data, account: String) throws {
            throw KeychainError(status: errSecAuthFailed)
        }

        func delete(account: String) throws {
            throw KeychainError(status: errSecAuthFailed)
        }
    }

    /// `--translation-probes`：打开设置页后自动刷新模型列表并测试连接（配合本机桩服务查看结果状态）。
    /// 只允许本机地址：走查绝不请求真实服务
    static func runProbesIfRequested(_ model: TranslationSettingsModel) {
        guard CommandLine.arguments.contains("--translation-probes") else { return }
        guard case .success(let url) = LLMBaseURL.validate(model.settings.effectiveTranslationBaseURL),
            LLMBaseURL.isLoopback(url)
        else {
            NSLog("--translation-probes ignored: the base URL is not a loopback address")
            return
        }
        model.refreshModels()
        model.testConnection()
    }

    /// `--scenario translation:download`：用当前引擎翻译一句英文；语言包缺失时走 resolve（显示下载窗口），
    /// 结果打印到标准输出。只用于确认系统下载界面会出现，不替用户确认下载
    @available(macOS 26, *)
    static func runDownloadScenario(_ provider: any TranslationProviding) {
        Task {
            guard case .success(let engine) = provider.makeEngine() else { return }
            let block = TextBlock(id: 0, lines: [], alignment: .leading, text: "Save your changes before closing.")
            do {
                for try await _ in engine.translate(
                    [block], languages: TranslationLanguages(source: "en", target: "zh-Hans"))
                {}
                print("translation:download finished without failure")
            } catch let failure as TranslationFailure {
                print("translation:download failure \(failure), resolving")
                let retry = await provider.resolve(failure)
                print("translation:download resolve returned \(retry)")
            } catch {
                print("translation:download ended: \(type(of: error))")
            }
        }
    }
}
#endif
