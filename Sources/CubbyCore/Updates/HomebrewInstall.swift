import Foundation

/// 是否用 Homebrew 安装（docs/UPDATE-REMINDER-DESIGN.md U8）：Caskroom 里有 cubby 目录即视为是，
/// 此时横幅的主按钮改为复制升级命令
public enum HomebrewInstall {
    public static let upgradeCommand = "brew upgrade --cask cubby"
    /// Apple 芯片与 Intel 的 Homebrew 前缀
    public static let caskroomPaths = ["/opt/homebrew/Caskroom/cubby", "/usr/local/Caskroom/cubby"]

    /// - Parameters:
    ///   - caskroomPaths: 要检查的位置（测试注入）
    ///   - fileExists: 判断路径是否存在（测试注入）
    public static func isInstalled(
        caskroomPaths: [String] = caskroomPaths,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Bool {
        caskroomPaths.contains(where: fileExists)
    }
}
