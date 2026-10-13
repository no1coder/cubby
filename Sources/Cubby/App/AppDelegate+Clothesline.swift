import AppKit
import CubbyCore

// 晾衣绳的接线（docs/UI-UPGRADE-PLAN.md 第 5 节）
extension AppDelegate {
    /// 菜单栏「显示晾衣绳」与快捷键：显示 / 收起
    func toggleClothesline() {
        clothesline?.toggle()
    }

    /// 开关晾衣绳：开启时开始轮询指针、面板里出现「挂到晾衣绳」入口；关闭时收起并隐藏入口。
    /// 全局快捷键另由 registerHotKeys / 设置监听注册（截图走查时不注册）
    func applyClotheslineEnabled() {
        guard let clothesline else { return }
        // 入口是否出现由 settings.clotheslineEnabled 决定（可观察），闭包常设
        panel?.viewModel.onToggleClothesline = { [weak clothesline] item in clothesline?.toggle(item) }
        if settings.clotheslineEnabled {
            clothesline.start()
        } else {
            clothesline.stop()
        }
        statusBar?.refreshAppearance()
    }

    /// 历史变化（删除、清空、超出上限）后绳上只保留仍在历史里的图片；绳子变化时更新菜单栏上的张数
    func observeClothesline() {
        observe({ [settings] in settings.clotheslineEnabled }) { [weak self] in
            self?.applyClotheslineEnabled()
            self?.registerClotheslineHotKey()
        }
        observe({ [settings] in settings.clotheslineHotKey }) { [weak self] in self?.registerClotheslineHotKey() }
        observe({ [weak self] in self?.store?.revision }) { [weak self] in self?.clothesline?.refresh() }
        observe({ [settings] in settings.clothesline }) { [weak self] in
            self?.clothesline?.refresh()
            self?.statusBar?.refreshAppearance()
        }
    }
}

// MARK: - 放大编辑与截图自动挂上
extension AppDelegate {
    func makeClothesline(store: ClipStore, screenshots: ScreenshotCoordinator) -> ClotheslineController {
        let clothesline = ClotheslineController(store: store, settings: settings)
        clothesline.onEdit = { [weak self, weak clothesline, weak screenshots] item in
            guard let clothesline, let screenshots else { return }
            self?.editOnClothesline(item, clothesline: clothesline, screenshots: screenshots)
        }
        return clothesline
    }

    /// 单击绳上的照片：在指针所在屏幕放大标注；「完成并晾回」时新条目接替原位置
    fileprivate func editOnClothesline(
        _ item: ClipItem, clothesline: ClotheslineController, screenshots: ScreenshotCoordinator
    ) {
        guard let data = store?.imageData(for: item),
            let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
                ?? NSScreen.main
        else { return }
        clothesline.beginEditing(item.id)
        let started = screenshots.editHistoryImage(item, imageData: data, on: screen) { [weak clothesline] result in
            guard let clothesline else { return }
            if case .hungBack(let newID) = result { clothesline.replace(item.id, with: newID) }
            clothesline.endEditing()
        }
        if !started {
            clothesline.endEditing()
            NSSound.beep()
        }
    }

    /// 设置 › 截图「截图后挂到晾衣绳」：截图写入历史后挂上（绳子短暂滑下）
    func hangScreenshotIfEnabled(_ item: ClipItem) {
        guard settings.clotheslineEnabled, settings.hangsScreenshotsOnClothesline, item.kind == .image else { return }
        clothesline?.hang(item)
    }
}

#if DEBUG
extension AppDelegate {
    /// 截图走查：显示绳子并放大编辑第二张照片（绳子浮在覆盖层上、原位置为虚线空位）
    func debugEditOnClothesline() {
        guard let clothesline, let screenshots else { return }
        clothesline.debugShow(hoveringSecond: false)
        guard let entry = clothesline.model.entries.dropFirst().first else { return }
        editOnClothesline(entry.item, clothesline: clothesline, screenshots: screenshots)
    }
}
#endif
