import CubbyCore
import Foundation

/// 「设置 › 翻译」的提示文案（校验问题、探测结果）
enum TranslationSettingsCopy {
    static var keychainError: String {
        String(
            localized: "Couldn't access the Keychain. Try again.",
            comment: "Translation settings: saving or removing the API key failed")
    }

    /// 钥匙串读取失败（用户拒绝访问或钥匙串已锁定）：本次运行内不再自动重试
    static var keychainUnavailable: String {
        String(
            localized: "Couldn't access the Keychain, so the saved API key can't be used.",
            comment: "Translation settings: reading the saved API key from the Keychain failed")
    }

    /// 保存的密钥属于另一个主机：绝不发往当前地址，需要重新填写
    static func keySavedForOtherHost(_ savedHost: String, currentHost: String) -> String {
        String(
            localized: "The API key was saved for \(savedHost). Enter it again for \(currentHost).",
            comment: "Translation settings: the stored key belongs to another host. %1$@ = old host, %2$@ = new host")
    }

    /// currentHost：当前地址的主机名（提示重新填写密钥时使用）
    static func message(for issue: LLMConfigurationIssue, currentHost: String) -> String {
        switch issue {
        case .invalidBaseURL(let error): message(for: error)
        case .missingModel:
            String(localized: "Choose or enter a model.", comment: "Translation settings: model is missing")
        case .missingAPIKey:
            String(localized: "Enter and save an API key.", comment: "Translation settings: API key is missing")
        case .keySavedForOtherHost(let savedHost): keySavedForOtherHost(savedHost, currentHost: currentHost)
        case .keychainUnavailable: keychainUnavailable
        }
    }

    static func message(for error: LLMBaseURLError) -> String {
        switch error {
        case .empty:
            String(localized: "Enter the base URL.", comment: "Translation settings: base URL is empty")
        case .malformed:
            String(localized: "This isn't a valid URL.", comment: "Translation settings: base URL is invalid")
        case .insecure:
            String(
                localized: "Use https://. Plain http:// is only allowed for localhost.",
                comment: "Translation settings: base URL uses http for a remote host")
        case .unsupportedComponents:
            String(
                localized: "Remove the user name, password, query or fragment from the URL.",
                comment: "Translation settings: base URL has extra components")
        }
    }

    /// 探测失败的原因（只含主机名与状态码，不含密钥或返回内容）
    static func message(for error: any Error, host: String) -> String {
        guard let failure = error as? TranslationFailure else {
            return String(localized: "Something went wrong. Try again.", comment: "Translation settings: unknown error")
        }
        switch failure {
        case .unauthorized:
            return String(
                localized: "The API key was rejected. Check that it's correct and has access.",
                comment: "Translation settings: 401 / 403")
        case .rateLimited:
            return String(
                localized: "Too many requests, or the account is out of credit.",
                comment: "Translation settings: 402 / 429")
        case .network:
            return String(
                localized: "Couldn't connect to \(host).", comment: "Translation settings: network error. %@ = host")
        case .server(let status):
            return String(
                localized: "The service returned an error (\(status)).",
                comment: "Translation settings: HTTP error. %lld = status code")
        default:
            return String(
                localized: "The response couldn't be read. Check the model name.",
                comment: "Translation settings: invalid response")
        }
    }

    static func modelCount(_ count: Int) -> String {
        String(localized: "\(count) models", comment: "Translation settings: number of models fetched")
    }

    /// 「已连接 · 模型 · 耗时 ·「译文」」
    static func connected(_ result: LLMConnectionTestResult, model: String) -> String {
        let components = result.duration.components
        let milliseconds = Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
        return String(
            localized: "Connected · \(model) · \(milliseconds) ms · “\(result.translation)”",
            comment:
                "Translation settings: connection test succeeded. %1$@ = model, %2$lld = ms, %3$@ = translation of Hello"
        )
    }
}
