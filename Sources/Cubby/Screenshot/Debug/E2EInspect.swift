#if DEBUG
import AppKit
import CubbyCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// 解码后的 PNG：尺寸与逐像素 sRGB 读数（左上原点）
struct E2EImage {
    let width: Int
    let height: Int
    private let pixels: [UInt8]

    /// 不是合法 PNG 时为 nil
    init?(png: Data) {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
            CGImageSourceGetType(source) as String? == UTType.png.identifier,
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        self.init(image: image)
    }

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.pixels = buffer
    }

    /// (x, y) 像素处的颜色；越界为 nil
    func color(x: Int, y: Int) -> RGBAColor? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let offset = (y * width + x) * 4
        return RGBAColor(
            red: Double(pixels[offset]) / 255, green: Double(pixels[offset + 1]) / 255,
            blue: Double(pixels[offset + 2]) / 255, alpha: Double(pixels[offset + 3]) / 255)
    }
}

extension RGBAColor {
    /// 各通道差的最大值（0...1）
    func distance(to other: RGBAColor) -> Double {
        max(abs(red - other.red), abs(green - other.green), abs(blue - other.blue))
    }

    var hexDescription: String {
        ColorFormatter.string(self, format: .hex)
    }
}

/// 读取 SwiftUI 宿主视图的根视图（任意 Content），用于读出 HUD 的文案
@MainActor
protocol E2ERootViewProviding {
    var e2eRootView: Any { get }
}

extension NSHostingView: E2ERootViewProviding {
    var e2eRootView: Any {
        rootView
    }
}

/// 读取界面状态：HUD 文案（反射 SwiftUI 根视图的存储属性，不依赖无障碍树——没有辅助客户端时它是空的）、
/// 样式条色块的位置（按 OverlayTokens 的布局常量计算）
@MainActor
enum E2EInspect {
    /// 当前可见的 HUD（HUDToast 面板）：内容视图（每次提示都会新建）与文案
    static func visibleHUD() -> (view: NSView, text: String)? {
        for window in NSApp.windows where window.isVisible {
            guard let content = window.contentView as? (NSView & E2ERootViewProviding) else { continue }
            let root = content.e2eRootView
            guard String(describing: Swift.type(of: root)).contains("HUDToastView"),
                let message = Mirror(reflecting: root).children.first(where: { $0.label == "message" })?.value
                    as? String
            else { continue }
            return (content, message)
        }
        return nil
    }

    /// 当前光标（本进程最近一次 set 的光标）的名称
    static var cursorName: String {
        let current = NSCursor.current
        let known: [(String, NSCursor)] = [
            ("arrow", .arrow), ("iBeam", .iBeam), ("crosshair", .crosshair), ("move", OverlayCursors.move),
            ("camera", OverlayCursors.camera),
        ]
        return known.first { $0.1 === current }?.0 ?? "other"
    }

    /// 工具栏按钮的中心（全局点）。布局与 ScreenshotToolbar 一致：
    /// 内边距｜指针 + 8 工具｜分隔｜撤销 重做｜分隔｜提取文字（翻译）贴图 保存｜分隔｜取消 完成，项间距 toolbarSpacing
    static func toolbarCenter(of item: E2EToolbarItem, toolbar frame: CGRect, hasTranslate: Bool) -> CGPoint? {
        let tools = ScreenshotTool.allCases.map { E2EToolbarItem.tool($0) }
        let output: [E2EToolbarItem?] = hasTranslate ? [.extractText, .translate] : [.extractText]
        let layout: [E2EToolbarItem?] =
            tools + [nil, .undo, .redo, nil] + output + [.pin, .save, nil, .cancel, .done]
        let button = OverlayTokens.toolbarButtonSize
        let spacing = OverlayTokens.toolbarSpacing
        var x = frame.minX + OverlayTokens.toolbarPadding
        for entry in layout {
            let width = entry == nil ? 1 + spacing * 2 : button
            if entry == item {
                return CGPoint(x: x + width / 2, y: frame.midY)
            }
            x += width + spacing
        }
        return nil
    }

    /// 样式条上第 index 个色块的中心（全局点）。布局与 ScreenshotStyleBar 一致：
    /// 内边距｜三档粗细（各一个按钮宽）｜分隔线（1 pt + 两侧间距）｜8 个色块（与按钮等宽的命中区），项间距 toolbarSpacing
    static func swatchCenter(_ color: AnnotationColor, styleBar frame: CGRect) -> CGPoint? {
        guard let index = AnnotationColor.allCases.firstIndex(of: color) else { return nil }
        let button = OverlayTokens.toolbarButtonSize
        let spacing = OverlayTokens.toolbarSpacing
        let separator = 1 + spacing * 2
        // 色块命中区与粗细按钮统一为 toolbarButtonSize（见 ScreenshotStyleBar.ColorSwatchButton）
        let swatch = button
        let weights = CGFloat(StrokeWeight.allCases.count) * (button + spacing)
        let firstSwatch = OverlayTokens.toolbarPadding + weights + separator + spacing
        let x = frame.minX + firstSwatch + CGFloat(index) * (swatch + spacing) + swatch / 2
        return CGPoint(x: x, y: frame.midY)
    }
}
/// 工具栏上的按钮
enum E2EToolbarItem: Equatable, CustomStringConvertible {
    case tool(ScreenshotTool)
    case undo
    case redo
    case extractText
    case translate
    case pin
    case save
    case cancel
    case done

    var description: String {
        switch self {
        case .tool(let tool): "\(tool)"
        case .undo: "undo"
        case .redo: "redo"
        case .extractText: "extract text"
        case .translate: "translate"
        case .pin: "pin"
        case .save: "save"
        case .cancel: "cancel"
        case .done: "done"
        }
    }
}
#endif
