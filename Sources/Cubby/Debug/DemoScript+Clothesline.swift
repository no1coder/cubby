#if DEBUG
import AppKit
import CubbyCore

/// `demo:clothesline`：假指针在（假）菜单栏按下往下拉 → 绳子滑下 → 悬停照片（抬起、显示提示）→ 单击放大编辑并画一个框。
/// 晾衣绳的显示 / 悬停由它自己的状态机按假指针的位置算出（ClotheslineController.debugPointer），不读真实鼠标；
/// 绳上的照片由 -clotheslineItems 启动参数给出
extension AppDelegate {
    func runClotheslineDemo() async {
        guard let clothesline, let screen = NSScreen.main else { return }
        let menuBar = DemoMenuBar(on: screen)
        let cursor = DemoCursor(at: DemoWindows.appKitPoint(CGPoint(x: 1240, y: 300)))
        cursor.onMove = { [weak clothesline] location, pressed in
            clothesline?.debugPointer = (location, pressed)
        }
        clothesline.debugPointer = (cursor.location, false)
        clothesline.refresh()
        await DemoClock.pause(0.5)
        // 移到菜单栏，按住往下拉
        await cursor.move(to: DemoWindows.appKitPoint(CGPoint(x: 1180, y: 14)), duration: 0.8)
        await DemoClock.pause(0.3)
        cursor.press()
        await DemoClock.pause(0.15)
        await cursor.move(to: DemoWindows.appKitPoint(CGPoint(x: 1185, y: 130)), duration: 0.7)
        cursor.release()
        await DemoClock.pause(0.6)
        // 依次悬停两张照片
        let entries = clothesline.model.entries
        let photos = clothesline.model.layout.photos
        guard photos.count >= 3, entries.count >= 3 else { return }
        for index in [1, 2] {
            await cursor.move(to: photoCenter(photos[index].frame, on: screen), duration: 0.6)
            await DemoClock.pause(1.3)
        }
        // 单击放大编辑
        await cursor.click()
        clothesline.model.onEdit(entries[2].item)
        await DemoClock.pause(1.2)
        await drawRectangleInEdit(cursor: cursor)
        await DemoClock.pause(2.2)
        menuBar.close()
    }

    /// 照片中心（窗口坐标，左上原点）→ AppKit 屏幕坐标；绳子窗口紧贴菜单栏下沿
    private func photoCenter(_ frame: CGRect, on screen: NSScreen) -> CGPoint {
        let top = screen.visibleFrame.maxY
        return CGPoint(x: screen.frame.minX + frame.midX, y: top - frame.midY)
    }

    /// 放大编辑里用矩形工具（默认工具）框住图片中间偏右的一块：事件直接交给覆盖层的 reducer
    private func drawRectangleInEdit(cursor: DemoCursor) async {
        guard let edit = screenshots?.historyEdit, let overlay = edit.overlay as? ScreenshotOverlayController
        else { return }
        let image = edit.layout.imageRect
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: image.minX + image.width * x, y: image.minY + image.height * y)
        }
        let start = point(0.585, 0.16)
        let end = point(0.765, 0.93)
        await cursor.move(to: DemoWindows.appKitPoint(start), duration: 0.7)
        cursor.onMove = { location, pressed in
            guard pressed else { return }
            overlay.send(.mouseDragged(DemoWindows.topLeftPoint(location)))
        }
        overlay.send(.mouseDown(start, clickCount: 1))
        cursor.press()
        await cursor.move(to: DemoWindows.appKitPoint(end), duration: 0.9)
        overlay.send(.mouseUp(end))
        cursor.release()
        cursor.onMove = nil
    }
}
#endif
