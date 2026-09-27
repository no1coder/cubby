import Foundation
import os

/// 找到并读取使用说明：界面语言为简体中文时读 USER-GUIDE.zh-Hans.md，否则读 USER-GUIDE.md。
/// 文件由 scripts/build-app.sh 复制进 .app 的 Resources；调试构建直接运行 .build/debug/Cubby（没有包内资源）时
/// 回退到仓库的 docs/ 目录。
enum GuideSource {
    /// 读取并解析后的文档，以及它所在的目录（解析文内相对链接）
    struct Loaded: Sendable {
        let document: GuideDocument
        let directory: URL
    }

    private static let englishName = "USER-GUIDE"
    private static let chineseName = "USER-GUIDE.zh-Hans"
    private static let fileExtension = "md"
    private static let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "UserGuide")

    /// 与界面语言一致（界面语言由系统在包内的 lproj 中选出）
    static var preferredFileName: String {
        Bundle.main.preferredLocalizations.first == "zh-Hans" ? chineseName : englishName
    }

    /// 读取并解析（在后台线程调用）；找不到或读不出时返回 nil 并记录日志
    static func load(fileName: String) -> Loaded? {
        guard let url = locate(fileName: fileName) else {
            logger.error("User guide \(fileName, privacy: .public).md is missing from the app bundle")
            return nil
        }
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let document = try GuideParser.parse(markdown)
            return Loaded(document: document, directory: url.deletingLastPathComponent())
        } catch {
            logger.error("Couldn't read the user guide: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func locate(fileName: String) -> URL? {
        if let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension) {
            return url
        }
        #if DEBUG
        return repositoryDocs(fileName: fileName)
        #else
        return nil
        #endif
    }

    #if DEBUG
    /// 调试构建：本文件位于 Sources/Cubby/UserGuide/，去掉文件名后再向上三级是仓库根目录
    private static func repositoryDocs(fileName: String) -> URL? {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appending(components: "docs", "\(fileName).\(fileExtension)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    #endif
}

/// 文内链接的去向：只打开 http / https；#锚点在文内跳转；相对路径只打开文档目录里现有的 Markdown；其余一律忽略
enum GuideLinkTarget: Equatable {
    case web(URL)
    case anchor(String)
    case localFile(URL)
    case ignored

    private static let webSchemes: Set<String> = ["http", "https"]
    private static let localExtension = "md"

    static func resolve(_ url: URL, relativeTo directory: URL?) -> GuideLinkTarget {
        if let scheme = url.scheme?.lowercased() {
            return webSchemes.contains(scheme) && url.host() != nil ? .web(url) : .ignored
        }
        let path = url.path(percentEncoded: false)
        if path.isEmpty {
            guard let fragment = url.fragment(percentEncoded: false), !fragment.isEmpty else { return .ignored }
            return .anchor(fragment.lowercased())
        }
        guard let directory, url.pathExtension.lowercased() == localExtension else { return .ignored }
        let base = directory.standardizedFileURL
        let file = base.appending(path: path).standardizedFileURL
        // 不允许 ../ 跳出文档目录
        guard file.path.hasPrefix(base.path + "/"), FileManager.default.fileExists(atPath: file.path) else {
            return .ignored
        }
        return .localFile(file)
    }
}
