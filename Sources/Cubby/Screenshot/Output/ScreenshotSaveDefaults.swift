import CubbyCore
import Foundation

/// 截图保存目录的 App 层默认值：读取系统截图设置与当前用户的主目录
extension ScreenshotSaveLocation {
    /// 当前实际使用的保存目录：用户设置 > 系统截图位置（须已存在）> 桌面
    static func resolved(preferred: URL?) -> URL {
        destination(preferred: preferred).directory
    }

    /// 同上，并标明目录不存在时是否允许创建（只有用户在设置里选择的目录允许）
    static func destination(preferred: URL?) -> Destination {
        destination(
            preferred: preferred,
            systemDefaults: UserDefaults(suiteName: systemDefaultsSuite),
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }
}

extension ScreenshotFileSaver {
    /// 桌面：首选目录不可用或拒绝写入时的回退位置（不自动创建）
    static var desktopDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }
}
