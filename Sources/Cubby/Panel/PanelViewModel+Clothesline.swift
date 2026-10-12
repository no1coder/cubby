import AppKit
import CubbyCore

/// 晾衣绳的入口（docs/UI-UPGRADE-PLAN.md 第 5 节）：右键菜单「挂到晾衣绳 ⌘L」、悬停工具条、预览底部「晾起来」。只支持图片
extension PanelViewModel {
    /// 面板里是否出现晾衣绳入口：读可观察的设置，开关切换后界面随之刷新（闭包本身不可观察）
    var offersClothesline: Bool {
        settings.clotheslineEnabled && onToggleClothesline != nil
    }

    /// 「晾着」角标：关闭晾衣绳时不显示（与菜单栏张数一致）
    func isOnClothesline(_ item: ClipItem) -> Bool {
        settings.clotheslineEnabled && settings.clothesline.contains(item.id)
    }

    /// 挂上或取下；不是图片时提示音
    func toggleClothesline(_ item: ClipItem) {
        guard item.kind == .image, offersClothesline, let onToggleClothesline else {
            NSSound.beep()
            return
        }
        onToggleClothesline(item)
    }

    func toggleClotheslineForSelection() {
        guard let item = selectedItem else { return }
        toggleClothesline(item)
    }
}
