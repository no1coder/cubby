#if DEBUG
import AppKit
import CubbyCore
import ImageIO

/// 截图翻译脚本的步骤与检查
extension E2EStep {
    /// ⇧⌘T
    static var translateKey: E2EStep {
        command("t", shift: true)
    }

    /// 等翻译结束在期望的状态
    static func expectTranslationStatus(
        _ title: String, timeout: Duration = .seconds(10), _ predicate: @escaping @MainActor (TranslationStatus) -> Bool
    ) -> E2EStep {
        eventually(title, timeout: timeout) { context in
            context.session?.translation.map { predicate($0.status) } ?? false
        } detail: { context in
            "status \(context.session?.translation.map { "\($0.status)" } ?? "no translation")"
        }
    }

    static var expectTranslationReady: E2EStep {
        expectTranslationStatus("translation finished") { $0 == .ready }
    }

    /// 点翻译条上的元素（位置来自翻译条的布局记录，点击经窗口派发到 SwiftUI 按钮）
    static func clickTranslationBar(_ item: TranslationBarItem) -> E2EStep {
        action("click translation bar \(item)") { context in
            _ = await context.poll(timeout: .seconds(2)) { context.translationBarCenter(of: item) != nil }
            guard let center = context.translationBarCenter(of: item) else {
                throw E2EScriptError.unavailable("translation bar \(item)")
            }
            try await context.driver.move(to: center)
            try await context.driver.click(at: center)
        }
    }

    /// 直接触发翻译条操作（语言选单是系统菜单，合成事件驱动不了它的跟踪循环）
    static func translationBarAction(_ action: TranslationBarAction) -> E2EStep {
        E2EStep.action("translation bar action \(action)") { context in
            guard let overlay = context.world.overlay else { throw E2EScriptError.noSession }
            overlay.debugTranslationBarAction(action)
            try await context.driver.flush()
        }
    }

    /// 画布上某块的像素与冻结帧原图的差异：visible = 显示译文（大量像素不同），否则应与原图一致
    static func expectCanvasBlock(_ title: String, block index: Int, showsTranslation visible: Bool) -> E2EStep {
        eventually(title, timeout: .seconds(2)) { context in
            guard let difference = context.canvasDifference(block: index) else { return false }
            return visible
                ? difference > E2ETranslationChecks.changedFraction : difference < E2ETranslationChecks.sameFraction
        } detail: { context in
            "differing pixels \(context.canvasDifference(block: index).map { "\($0)" } ?? "unavailable")"
        }
    }

    /// 导出的 PNG 里某块与原图的差异（导出版本由「原文 | 译文」开关决定）
    static func expectExportedBlock(_ title: String, block index: Int, translated: Bool) -> E2EStep {
        eventually(title) { context in
            guard let difference = context.exportDifference(block: index) else { return false }
            return translated
                ? difference > E2ETranslationChecks.changedFraction : difference < E2ETranslationChecks.sameFraction
        } detail: { context in
            "differing pixels \(context.exportDifference(block: index).map { "\($0)" } ?? "unavailable")"
        }
    }

    /// 剪贴板文字 = 按块 id 拼接的译文（请求过的块用桩译文，其余用原文）
    static var expectCopiedTranslation: E2EStep {
        eventually("pasteboard has the translation in reading order") { context in
            guard let expected = context.expectedTranslatedText else { return false }
            return context.world.pasteboardText == expected
        } detail: { context in
            "expected \(context.expectedTranslatedText ?? "?"), got \(context.world.pasteboardText ?? "nothing")"
        }
    }
}

/// 像素比较的阈值
enum E2ETranslationChecks {
    /// 显示译文时块内至少这么多像素与原图不同
    static let changedFraction = 0.04
    /// 显示原文时与原图不同的像素不超过这么多（抗锯齿与色彩空间误差）
    static let sameFraction = 0.01
    /// 单个像素算「不同」的通道差
    static let channelTolerance = 0.12
}

extension E2EContext {
    var translationRun: TranslationRun? {
        session?.translation
    }

    /// 选区所在屏的覆盖层视图
    var selectionScreenView: OverlayScreenView? {
        world.overlay?.debugScreenViews.first { $0.debugToolbarFrame != nil } ?? world.overlay?.debugScreenViews.first
    }

    func translationBarCenter(of item: TranslationBarItem) -> CGPoint? {
        selectionScreenView?.debugTranslationBarCenter(of: item)
    }

    /// 第 index 块（按 id）的外框（全局点）；译文被撤销后用之前记下的（rects["block<index>"]）
    func blockFrame(_ index: Int) -> CGRect? {
        translationRun?.blocks.first { $0.id == index }?.frame ?? rects["block\(index)"]
    }

    /// 「复制译文」应得的文字：桩引擎按请求过的块给出译文，其余用原文
    var expectedTranslatedText: String? {
        guard let run = translationRun, let provider = world.translationProvider else { return nil }
        let target = run.languages?.target ?? E2ETranslationProvider.defaultTarget
        let requested = Set(provider.log.requests.filter { $0.target == target }.flatMap(\.blockIDs))
        let selection = session?.selection
        let lines = run.blocks.filter { block in selection.map(block.frame.intersects) ?? true }.map { block in
            requested.contains(block.id) ? E2ETranslationProvider.translated(block.text, target: target) : block.text
        }
        return lines.joined(separator: "\n")
    }

    /// 画布（冻结帧 + 译文层）与冻结帧原图在某块区域内不同像素的比例
    func canvasDifference(block index: Int) -> Double? {
        guard let rect = blockFrame(index), let view = selectionScreenView,
            let canvas = E2EInspect.renderCanvas(view, region: rect), let original = originalImage(of: rect)
        else { return nil }
        return E2EInspect.difference(canvas, original)
    }

    /// 剪贴板 PNG 与冻结帧原图在某块区域内不同像素的比例
    func exportDifference(block index: Int) -> Double? {
        guard let rect = blockFrame(index), let png = world.pasteboardPNG, let selection = session?.selection,
            let original = originalImage(of: rect)
        else { return nil }
        let pixels = world.screen.pixelRect(selection)
        let block = world.screen.pixelRect(rect).offsetBy(dx: -pixels.minX, dy: -pixels.minY)
        return E2EInspect.crop(png: png, to: block).map { E2EInspect.difference($0, original) }
    }

    /// 冻结帧里某区域的原图
    private func originalImage(of rect: CGRect) -> E2EImage? {
        guard let frame = world.lastCapture?.frame(for: world.screen.id),
            let cropped = frame.image.cropping(to: world.screen.pixelRect(rect))
        else { return nil }
        return E2EImage(image: cropped)
    }
}

extension E2EInspect {
    /// 把画布图层树在 region（全局点）内的部分渲染成屏幕原生像素的位图（只渲染本进程的图层，不截屏）
    static func renderCanvas(_ view: OverlayScreenView, region: CGRect) -> E2EImage? {
        guard let layer = view.canvas.layer else { return nil }
        let space = view.space
        let pixels = space.screen.pixelRect(region)
        let width = Int(pixels.width)
        let height = Int(pixels.height)
        guard width > 0, height > 0,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // 图层坐标 y 向上：区域左下角对到位图原点
        let scale = space.scale
        let bottomLeft = space.layerRect(
            CGRect(
                x: space.screen.frame.minX + pixels.minX / scale, y: space.screen.frame.minY + pixels.minY / scale,
                width: pixels.width / scale, height: pixels.height / scale))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bottomLeft.minX, y: -bottomLeft.minY)
        layer.render(in: context)
        return context.makeImage().flatMap(E2EImage.init(image:))
    }

    /// 两张同尺寸位图中不同像素的比例
    static func difference(_ lhs: E2EImage, _ rhs: E2EImage) -> Double {
        let width = min(lhs.width, rhs.width)
        let height = min(lhs.height, rhs.height)
        guard width > 0, height > 0 else { return 1 }
        var differing = 0
        for y in 0..<height {
            for x in 0..<width {
                guard let left = lhs.color(x: x, y: y), let right = rhs.color(x: x, y: y) else { continue }
                if left.distance(to: right) > E2ETranslationChecks.channelTolerance {
                    differing += 1
                }
            }
        }
        return Double(differing) / Double(width * height)
    }

    /// 从 PNG 里裁出一块像素（左上原点）
    static func crop(png: Data, to rect: CGRect) -> E2EImage? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil), let cropped = image.cropping(to: rect)
        else { return nil }
        return E2EImage(image: cropped)
    }
}
#endif
