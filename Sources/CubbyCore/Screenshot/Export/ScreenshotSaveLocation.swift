import Foundation

/// 截图保存目录的解析：用户设置 > 系统截图设置（`com.apple.screencapture` 的 `location`）> 桌面
///
/// 系统截图设置可被同一用户下的任何进程改写，因此只接受已经存在的目录，否则回退桌面；
/// 只有用户亲自选择的目录（设置里选择的，或存储对话框里确认过的）才允许自动创建，
/// 以便该目录之后被删除时能重建（见 Destination.createsIfMissing 与 ScreenshotFileSaver）。
public enum ScreenshotSaveLocation {
    /// 系统截图设置所在的 defaults 域
    public static let systemDefaultsSuite = "com.apple.screencapture"
    /// 系统截图目录的键
    public static let locationKey = "location"
    private static let desktopName = "Desktop"

    /// 保存目标：目录，以及目录不存在时是否允许创建
    public struct Destination: Equatable, Sendable {
        public let directory: URL
        /// 只有用户亲自选择的目录为 true
        public let createsIfMissing: Bool

        public init(directory: URL, createsIfMissing: Bool) {
            self.directory = directory
            self.createsIfMissing = createsIfMissing
        }
    }

    /// preferred 非 nil 用之；否则读 systemDefaults["location"]（`~` 按 homeDirectory 展开，且须为已存在的目录）；
    /// 否则 home/Desktop
    public static func resolve(
        preferred: URL?,
        systemDefaults: UserDefaults?,
        homeDirectory: URL,
        directoryExists: (URL) -> Bool = isExistingDirectory
    ) -> URL {
        destination(
            preferred: preferred, systemDefaults: systemDefaults, homeDirectory: homeDirectory,
            directoryExists: directoryExists
        ).directory
    }

    /// 同 resolve，并标明该目录是否允许自动创建
    public static func destination(
        preferred: URL?,
        systemDefaults: UserDefaults?,
        homeDirectory: URL,
        directoryExists: (URL) -> Bool = isExistingDirectory
    ) -> Destination {
        if let preferred { return Destination(directory: preferred, createsIfMissing: true) }
        if let raw = systemDefaults?.string(forKey: locationKey),
            let url = expand(raw, homeDirectory: homeDirectory), directoryExists(url)
        {
            return Destination(directory: url, createsIfMissing: false)
        }
        return Destination(
            directory: homeDirectory.appendingPathComponent(desktopName, isDirectory: true), createsIfMissing: false)
    }

    /// 已存在的目录（跟随符号链接判断）；普通文件或不存在都为 false
    public static func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// 支持绝对路径与 `~` / `~/…`；空串、相对路径、`~user` 形式返回 nil
    private static func expand(_ raw: String, homeDirectory: URL) -> URL? {
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if path == "~" || path == "~/" {
            return URL(fileURLWithPath: homeDirectory.path, isDirectory: true)
        }
        if path.hasPrefix("~/") {
            let relative = String(path.dropFirst(2))
            return homeDirectory.appendingPathComponent(relative, isDirectory: true).standardizedFileURL
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }
        return nil
    }
}
