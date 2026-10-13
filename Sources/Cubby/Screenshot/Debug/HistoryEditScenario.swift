#if DEBUG
import AppKit
import CubbyCore

/// `--scenario screenshot:edit-history`：晾衣绳放大编辑一张生成的图片（不截屏、不读历史）。
/// `screenshot:edit-history:annotated` 上屏后再用 reducer 事件画几处标注（不合成系统输入），对照设计稿截图用
extension ScreenshotCoordinator {
    func startHistoryEditDemo(annotated: Bool) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
            let png = HistoryEditDemoImage.png()
        else {
            logger.error("History edit demo: couldn't create the demo image")
            return
        }
        let item = ClipItem(
            kind: .image,
            payload: .image(
                ImageRef(
                    name: "history-edit-demo", width: HistoryEditDemoImage.width, height: HistoryEditDemoImage.height)
            ),
            source: SourceApp(bundleID: "com.apple.iWork.Keynote", name: "Keynote"),
            createdAt: Date().addingTimeInterval(-26 * 60),
            contentHash: "history-edit-demo"
        )
        let started = editHistoryImage(item, imageData: png, on: screen) { [logger] result in
            logger.notice("History edit demo finished: \(String(describing: result), privacy: .public)")
        }
        guard started, annotated, let edit = historyEdit,
            let overlay = edit.overlay as? ScreenshotOverlayController
        else { return }
        HistoryEditDemoImage.annotate(overlay, image: edit.layout.imageRect)
    }
}

/// 演示图片（日落：紫色渐变、太阳、两道山丘，与设计稿 ClotheslineEdit 相似）与演示标注
@MainActor
private enum HistoryEditDemoImage {
    static let width = 1600
    static let height = 1000

    /// 演示图片的 PNG（只在内存中）；DPI 144，与 Retina 截图一致
    static func png() -> Data? {
        draw().flatMap { ScreenshotExporter.pngData($0, scale: 2) }
    }

    private static func draw() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let w = CGFloat(width)
        let h = CGFloat(height)
        let colors = [rgb(0x24, 0x1B, 0x4A), rgb(0x3B, 0x26, 0x6E)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
        }
        context.setFillColor(rgb(0xF6, 0xC2, 0x8B))
        context.fillEllipse(in: CGRect(x: w * 0.43, y: h * 0.38, width: w * 0.22, height: w * 0.22))
        context.setFillColor(rgb(0x7B, 0x52, 0xB9))
        hill(
            context, from: CGPoint(x: 0, y: h * 0.22), peak: CGPoint(x: w * 0.5, y: h * 0.48),
            to: CGPoint(x: w, y: h * 0.25))
        context.setFillColor(rgb(0x4E, 0x2F, 0x8A))
        hill(
            context, from: CGPoint(x: w * 0.33, y: 0), peak: CGPoint(x: w * 0.78, y: h * 0.4),
            to: CGPoint(x: w, y: h * 0.25))
        context.setFillColor(rgb(0xB8, 0xA8, 0xE0))
        context.fill(CGRect(x: w * 0.08, y: h * 0.86, width: w * 0.2, height: 8))
        context.fill(CGRect(x: w * 0.08, y: h * 0.83, width: w * 0.13, height: 6))
        return context.makeImage()
    }

    private static func hill(_ context: CGContext, from start: CGPoint, peak: CGPoint, to end: CGPoint) {
        context.beginPath()
        context.move(to: CGPoint(x: start.x, y: 0))
        context.addLine(to: start)
        context.addQuadCurve(to: end, control: CGPoint(x: peak.x, y: peak.y * 2 - (start.y + end.y) / 2))
        context.addLine(to: CGPoint(x: end.x, y: 0))
        context.closePath()
        context.fillPath()
    }

    private static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> CGColor {
        CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }

    /// 用 reducer 事件画标注：矩形、箭头、两个序号、荧光笔、马赛克，最后回到矩形工具
    static func annotate(_ overlay: ScreenshotOverlayController, image rect: CGRect) {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        func stroke(_ points: [CGPoint]) {
            guard let first = points.first, let last = points.last else { return }
            overlay.send(.mouseDown(first, clickCount: 1))
            points.dropFirst().forEach { overlay.send(.mouseDragged($0)) }
            overlay.send(.mouseUp(last))
        }
        func click(_ at: CGPoint) {
            overlay.send(.mouseDown(at, clickCount: 1))
            overlay.send(.mouseUp(at))
        }
        stroke([point(0.06, 0.08), point(0.2, 0.15), point(0.31, 0.19)])
        overlay.send(.command(.selectTool(.arrow)))
        stroke([point(0.32, 0.17), point(0.5, 0.22), point(0.6, 0.36)])
        overlay.send(.command(.selectTool(.number)))
        click(point(0.06, 0.08))
        click(point(0.62, 0.42))
        overlay.send(.command(.selectTool(.highlighter)))
        stroke([point(0.7, 0.74), point(0.8, 0.73), point(0.93, 0.72)])
        overlay.send(.command(.selectTool(.mosaic)))
        stroke([point(0.4, 0.58), point(0.46, 0.59), point(0.52, 0.58), point(0.58, 0.59)])
        overlay.send(.command(.selectTool(.rectangle)))
    }
}
#endif
