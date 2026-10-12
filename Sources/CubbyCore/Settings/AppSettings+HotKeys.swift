import Foundation

/// 按动作读写全局快捷键：设置里的冲突检查、热键注册失败时回退到上一个可用的快捷键共用
public extension AppSettings {
    /// 该动作当前的快捷键；nil 表示已关闭
    func hotKey(for action: HotKeyAction) -> HotKey? {
        switch action {
        case .togglePanel: hotKey
        case .screenshot: screenshotHotKey
        case .images: imagesHotKey
        case .clothesline: clotheslineHotKey
        }
    }

    /// 写入该动作的快捷键；nil 为关闭。面板快捷键不可关闭，写入 nil 被忽略
    func setHotKey(_ newValue: HotKey?, for action: HotKeyAction) {
        switch action {
        case .togglePanel: if let newValue { hotKey = newValue }
        case .screenshot: screenshotHotKey = newValue
        case .images: imagesHotKey = newValue
        case .clothesline: clotheslineHotKey = newValue
        }
    }
}
