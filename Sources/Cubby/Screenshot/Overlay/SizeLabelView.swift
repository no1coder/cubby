import AppKit
import CubbyCore

/// 选区尺寸标签（§2.5）：`W × H`（像素），11 pt semibold 等宽数字，白字，`black 0.65` 胶囊，内边距 3 × 7
///
/// 位置由 `SizeLabelPlacement.layout` 决定：上方外侧 → 下方外侧 → 内侧左上。
final class SizeLabelView: OverlayPassthroughView {
    private var text = ""

    private static var font: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: FontSize.caption, weight: .semibold)
    }

    private static var attributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.white]
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(OverlayTokens.labelBackgroundAlpha).cgColor
        layer?.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 文本对应的胶囊尺寸（取整到点，保证摆放后像素对齐）
    static func size(for text: String) -> CGSize {
        let textSize = (text as NSString).size(withAttributes: attributes)
        return CGSize(
            width: (textSize.width + OverlayTokens.labelHorizontalPadding * 2).rounded(.up),
            height: (textSize.height + OverlayTokens.labelVerticalPadding * 2).rounded(.up)
        )
    }

    /// 更新文本与位置（视图坐标）；文本不变时不重绘
    func show(text: String, frame: CGRect) {
        if self.frame != frame {
            self.frame = frame
            layer?.cornerRadius = frame.height / 2
        }
        if self.text != text {
            self.text = text
            needsDisplay = true
        }
        isHidden = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let string = text as NSString
        let size = string.size(withAttributes: Self.attributes)
        let origin = CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        string.draw(at: origin, withAttributes: Self.attributes)
    }
}

#if DEBUG
extension SizeLabelView {
    /// 仅调试构建（e2e）：当前文本
    var debugText: String {
        text
    }
}
#endif
