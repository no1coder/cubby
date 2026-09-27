import AppKit
import CubbyCore
import os

/// 检查更新：只在用户手动触发（或开启了每周自动检查）时请求 GitHub 最新正式版本，
/// 不下载、不替换应用，只告知结果并引导前往发布页或使用 Homebrew 升级。
@MainActor
enum UpdateChecker {
    enum Result: Equatable {
        case upToDate(current: String)
        case available(version: String, releaseURL: URL)
        case failed(reason: String)
    }

    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/no1coder/cubby/releases/latest")
    static let releasesPage = URL(string: "https://github.com/no1coder/cubby/releases")
    private static let timeout: TimeInterval = 10
    private static let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Update")

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static func check() async -> Result {
        guard let latestReleaseAPI else {
            return .failed(reason: String(localized: "The update address is invalid.", comment: "Update check error"))
        }
        var request = URLRequest(
            url: latestReleaseAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Cubby/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            // 临时会话：不写缓存、不存 Cookie
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200: return evaluate(data)
            case 404: return .upToDate(current: currentVersion)  // 尚无正式发布
            default:
                return .failed(
                    reason: String(localized: "The server returned status \(status).", comment: "Update check error")
                )
            }
        } catch {
            logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            return .failed(
                reason: String(
                    localized: "The network is unavailable or the request timed out.",
                    comment: "Update check error"
                )
            )
        }
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL?
        let draft: Bool?
        let prerelease: Bool?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
        }
    }

    private static func evaluate(_ data: Data) -> Result {
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
            release.draft != true, release.prerelease != true,
            let latest = SemanticVersion(release.tagName)
        else {
            return .failed(
                reason: String(localized: "Couldn't read the release information.", comment: "Update check error")
            )
        }

        guard let current = SemanticVersion(currentVersion), current < latest else {
            return .upToDate(current: currentVersion)
        }
        return .available(version: latest.description, releaseURL: safeReleaseURL(release.htmlURL))
    }

    /// 只打开 GitHub 上的 https 链接，其余一律回退到固定的发布页
    private static func safeReleaseURL(_ url: URL?) -> URL {
        let fallback = releasesPage ?? URL(fileURLWithPath: "/")
        guard let url, url.scheme == "https", url.host == "github.com" else { return fallback }
        return url
    }
}
