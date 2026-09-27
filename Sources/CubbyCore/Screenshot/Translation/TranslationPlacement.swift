import CoreGraphics
import Foundation

// 版面的值类型（实现线 T3 拥有，docs/TRANSLATION-DESIGN.md §3.5、§4.2）。
// 契约：TranslatedBlock 的 blockID / eraseFrame / text / textFrame 字段与公开 init 的参数；其余字段为 T3 的实现细节。

/// 与屏幕像素无关的 sRGB 颜色，分量 0…1
public struct PixelColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = PixelColor(red: 1, green: 1, blue: 1)
    public static let black = PixelColor(red: 0, green: 0, blue: 0)

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// 盖住原文的方式：纯色背景直接用同色填平；复杂背景用半透明衬底（颜色为衬底主色，不含 0.74 透明度）
public enum TranslationBackdrop: Equatable, Sendable {
    case solid(PixelColor)
    case plate(PixelColor)
}

/// 排好的一行译文：文字与起点（基线左端，全局点）
public struct TranslatedLine: Equatable, Sendable {
    public let text: String
    public let origin: CGPoint

    public init(text: String, origin: CGPoint) {
        self.text = text
        self.origin = origin
    }
}

/// 衬底下的模糊背景（冻结帧对应区域的像素，已模糊），铺满 eraseFrame
///
/// `@unchecked Sendable` 的理由：CGImage 不可变。相等性按图像对象判断（同一次 place 的结果才相等）。
public struct TranslationPlateImage: Equatable, @unchecked Sendable {
    public let image: CGImage

    public init(image: CGImage) {
        self.image = image
    }

    public static func == (lhs: TranslationPlateImage, rhs: TranslationPlateImage) -> Bool {
        lhs.image === rhs.image
    }
}

/// 一块译文的最终版面（全局点）：先按 backdrop 盖住原文，再在 textFrame 里画译文。
/// eraseFrame 是这一块绘制内容的外框（抹除区域 ∪ 衬底 ∪ 文字）
public struct TranslatedBlock: Equatable, Sendable {
    public let blockID: Int
    public let eraseFrame: CGRect
    public let backdrop: TranslationBackdrop
    public let text: String
    /// 各行译文的排版外框（含字形外伸）
    public let textFrame: CGRect
    /// 点
    public let fontSize: CGFloat
    public let isBold: Bool
    public let textColor: PixelColor
    public let alignment: TextBlockAlignment
    /// 纯色背景时逐行填色的矩形（已对齐像素）；衬底时为 [eraseFrame]
    public let eraseRects: [CGRect]
    /// 衬底的模糊背景；纯色背景或未生成时为 nil（此时衬底只画主色）
    public let plateImage: TranslationPlateImage?
    /// 译文语言（BCP-47，决定 CJK 字形）；nil 时由系统按文字推断
    public let language: String?
    public let lines: [TranslatedLine]

    /// 由调用方给定版面参数（测试与桩使用）：在 textFrame 内按字号、对齐自动换行
    public init(
        blockID: Int, eraseFrame: CGRect, backdrop: TranslationBackdrop, text: String, textFrame: CGRect,
        fontSize: CGFloat, isBold: Bool, textColor: PixelColor, alignment: TextBlockAlignment
    ) {
        let style = TranslationTypesetter.Style(fontSize: fontSize, isBold: isBold, language: nil)
        self.init(
            blockID: blockID, eraseFrame: eraseFrame, backdrop: backdrop, text: text, textFrame: textFrame,
            style: style, textColor: textColor, alignment: alignment, eraseRects: [eraseFrame], plateImage: nil,
            lines: TranslationTypesetter.wrap(text, style: style, in: textFrame, alignment: alignment))
    }

    init(
        blockID: Int, eraseFrame: CGRect, backdrop: TranslationBackdrop, text: String, textFrame: CGRect,
        style: TranslationTypesetter.Style, textColor: PixelColor, alignment: TextBlockAlignment,
        eraseRects: [CGRect], plateImage: TranslationPlateImage?, lines: [TranslatedLine]
    ) {
        self.blockID = blockID
        self.eraseFrame = eraseFrame
        self.backdrop = backdrop
        self.text = text
        self.textFrame = textFrame
        self.fontSize = style.fontSize
        self.isBold = style.isBold
        self.textColor = textColor
        self.alignment = alignment
        self.eraseRects = eraseRects
        self.plateImage = plateImage
        self.language = style.language
        self.lines = lines
    }

    var style: TranslationTypesetter.Style {
        TranslationTypesetter.Style(fontSize: fontSize, isBold: isBold, language: language)
    }
}
