import AppKit
import CubbyCore
import SwiftUI

/// 截图覆盖层专属的视觉常量（设计文档 §2.4 / §2.5 / §2.6 / §2.10）
///
/// 通用圆角、字号从 `DesignTokens.swift` 取；这里只放截图覆盖层独有的尺寸与透明度。
enum OverlayTokens {
    // MARK: - 遮罩与描边

    /// 选区 / 悬停目标之外的遮罩
    ///
    /// 窗口服务器在显示器的色彩空间里做 alpha 混合（窗口设为 sRGB 也不变，实测）：
    /// Apple 显示屏（P3，传递函数同 sRGB）上灰阶混合与 sRGB 完全一致；
    /// 但传递函数不同的第三方显示器（如 DELL U2718QM，gamma≈2.2）上，black 0.4 换算回 sRGB 只相当于 0.35。
    /// 取 0.45：这类显示器上约为规格的 0.4，Apple 显示屏上介于 CleanShot（0.4）与微信（0.5）之间，选区更「跳」
    static let dimAlpha: CGFloat = 0.45
    /// 悬停窗口 / 整屏描边：2 pt 强调色，画在目标内侧
    static let hoverStrokeWidth: CGFloat = 2
    /// 选区描边：1 pt 强调色（紧贴选区外侧）
    static let selectionStrokeWidth: CGFloat = 1
    /// 选区描边外再加 1 pt 半透明黑，浅色内容上也看得见
    static let selectionOuterStrokeWidth: CGFloat = 1
    static let selectionOuterAlpha: CGFloat = 0.25

    // MARK: - 纯净窗口模式

    /// 窗口模式下目标窗口上的强调色填充
    static let windowModeFillAlpha: CGFloat = 0.22
    /// 窗口模式描边（比普通悬停更粗，一眼区分）
    static let windowModeStrokeWidth: CGFloat = 3
    /// 窗口目标（悬停描边、窗口模式填充）的圆角：与 macOS 窗口一致；整屏目标保持直角
    static let windowCornerRadius: CGFloat = 10
    /// 窗口中央的相机徽标直径
    static let windowModeBadgeDiameter: CGFloat = 56
    /// 相机符号字号
    static let windowModeBadgeSymbolSize: CGFloat = 24
    /// 徽标白边与阴影
    static let windowModeBadgeBorderAlpha: CGFloat = 0.9
    static let windowModeBadgeBorderWidth: CGFloat = 2
    static let windowModeBadgeShadowOpacity: Float = 0.3
    static let windowModeBadgeShadowRadius: CGFloat = 6
    static let windowModeBadgeShadowOffsetY: CGFloat = -2

    // MARK: - 手柄

    static let handleDiameter: CGFloat = 8
    static let handleHoverDiameter: CGFloat = 10
    static let handleStrokeWidth: CGFloat = 1.5
    /// 1x 屏上手柄描边：1.5 px 会落在半像素上发糊，取整到 2 px
    static let handleStrokeWidthLowDensity: CGFloat = 2
    /// 手柄悬停放大的时长
    static let handleAnimationDuration: TimeInterval = 0.1
    /// 手柄的极淡阴影（白底上也能看出手柄边界）
    static let handleShadowOpacity: Float = 0.25
    static let handleShadowRadius: CGFloat = 1
    static let handleShadowOffsetY: CGFloat = -0.5

    // MARK: - 箭头吸附辅助线

    /// 1 pt 强调色、不透明度 0.4，沿箭头方向延长到屏幕边缘
    static let snapGuideWidth: CGFloat = 1
    static let snapGuideAlpha: CGFloat = 0.4

    // MARK: - 标注选中框

    /// 1 pt 强调色虚线（4-2），外扩 `AnnotationRenderer.selectionOutlineInset`
    static let annotationOutlineWidth: CGFloat = 1
    static let annotationOutlineDash: [NSNumber] = [4, 2]

    // MARK: - 标签（尺寸标签、悬停窗口标签）

    /// 胶囊底色 `black 0.78`：接近不透明，底下的内容不会透上来显脏
    static let labelBackgroundAlpha: CGFloat = 0.78
    /// 胶囊内边距：上下 3、左右 7
    static let labelVerticalPadding: CGFloat = 3
    static let labelHorizontalPadding: CGFloat = 7
    /// 标签与选区 / 目标的间距（= `SizeLabelPlacement.defaultGap`：8 pt 给放大后的角手柄留出余量）
    static let labelGap: CGFloat = SizeLabelPlacement.defaultGap
    /// 标签、工具栏距屏幕边缘的最小距离
    static let screenMargin: CGFloat = 6
    /// 悬停标签的应用图标边长
    static let hoverIconSize: CGFloat = 16
    /// 悬停标签第二行提示的不透明度
    static let hoverHintOpacity: Double = 0.62
    /// 窗口模式标签（强调色底）上的提示：白 0.62 在蓝底上对比不足，提到 0.92
    static let hoverHintOpacityOnAccent: Double = 0.92
    /// 窗口模式标签的强调色底不透明度
    static let hoverAccentFillOpacity: Double = 0.92
    /// 悬停标签：两行间距、首行元素间距、应用名最大宽度、两行版的上下内边距、单行胶囊的圆角
    static let hoverLineSpacing: CGFloat = 2
    static let hoverItemSpacing: CGFloat = 6
    static let hoverTitleMaxWidth: CGFloat = 220
    static let hoverTwoLineVerticalPadding: CGFloat = 5
    static let hoverCapsuleRadius: CGFloat = 11
    /// 「2 / 4」层级徽章：内边距与底色
    static let depthBadgeHorizontalPadding: CGFloat = 5
    static let depthBadgeVerticalPadding: CGFloat = 1
    static let depthBadgeOpacity: Double = 0.2

    // MARK: - 放大镜

    /// 15 × 15 网格（105 × 105 pt，常驻 hovering 时少遮挡内容）
    static let magnifierRadius = 7
    /// 每个源像素画成 7 pt 方格
    static let magnifierCellSize: CGFloat = 7
    static let magnifierGridLineAlpha: CGFloat = 0.12
    /// 信息区底色（网格本身是不透明像素）：0.9，底下的高亮描边不会透上来
    static let magnifierBackgroundAlpha: CGFloat = 0.9
    static let magnifierBorderAlpha: CGFloat = 0.2
    /// 外圈深色发丝线（白色内容上的边界）
    static let magnifierOuterBorderAlpha: CGFloat = 0.35
    /// 内圈白线距边缘的距离（在外圈 1 pt 深色线内侧、居中于第二个点上）
    static let magnifierInnerBorderInset: CGFloat = 1.5
    /// 中心十字辅助线的强调色不透明度
    static let magnifierCrosshairAlpha: CGFloat = 0.5
    /// 网格下方信息区高度（两行 11 pt 等宽数字 + 上下留白）
    static let magnifierInfoHeight: CGFloat = 38
    /// 信息区左右留白；文本放不下（如 `rgb(255, 255, 255)`）时退到 10 pt
    static let magnifierInfoPadding: CGFloat = 4
    /// 放大镜与光标的偏移（同 `MagnifierPlacement` 默认 offset）
    static let magnifierOffset: CGFloat = 20

    static var magnifierGridSide: CGFloat {
        CGFloat(magnifierRadius * 2 + 1) * magnifierCellSize
    }

    static var magnifierSize: CGSize {
        CGSize(width: magnifierGridSide, height: magnifierGridSide + magnifierInfoHeight)
    }

    // MARK: - 工具栏与样式条

    static let toolbarButtonSize: CGFloat = 28
    static let toolbarPadding: CGFloat = 4
    static let toolbarSpacing: CGFloat = 2
    /// 分组竖线高度
    static let toolbarSeparatorHeight: CGFloat = 16
    /// 工具栏与选区的间距、inside 档的内缩
    static let toolbarGap: CGFloat = 8
    /// 出现时淡入 + 轻微缩放
    static let toolbarAppearDuration: TimeInterval = 0.12
    static let toolbarAppearScale: CGFloat = 0.96
    /// 分组竖线：浅色玻璃上 0.1 几乎看不见
    static let toolbarSeparatorOpacity: Double = 0.15
    /// 激活工具的底色（强调色）不透明度
    static let activeFillOpacity: Double = 0.2
    /// 激活底块在按钮之间滑动的时长（减弱动态效果时不做）
    static let activeSlideDuration: TimeInterval = 0.15
    /// 「完成」实心按钮悬停时的不透明度
    static let prominentHoverOpacity: Double = 0.85
    /// 按钮悬停底色（`primary`）与禁用图标（`secondary`）的不透明度
    static let buttonHoverOpacity: Double = 0.08
    static let disabledIconOpacity: Double = 0.45
    /// 样式条未选中圆点 / 字母：浅色玻璃上用近黑（深色玻璃上为白）
    static let lightGlyphOpacity: Double = 0.85
    /// 选中色块的环：浅色玻璃上用近黑（深色玻璃上为白）；环与色块之间留 1 pt 缝
    static let lightSwatchRingOpacity: Double = 0.8
    static let swatchRingGap: CGFloat = 1
    /// 色块描边：1 pt `white 0.6`，白色色块另加 `black 0.2`
    static let swatchBorderOpacity: Double = 0.6
    static let whiteSwatchBorderOpacity: Double = 0.2
    /// 色块悬停放大
    static let swatchHoverScale: CGFloat = 1.12
    static let swatchHoverDuration: TimeInterval = 0.1
    /// 玻璃与内容之间的底色层（窗口背景色）：压在棋盘格、代码等高对比内容上时图标仍清晰
    static let glassUnderlayOpacity: CGFloat = 0.35
    /// 样式条色块
    static let swatchDiameter: CGFloat = 16
    static let swatchRingWidth: CGFloat = 2
    /// 样式条粗细圆点（三档）：比例约 1 : 1.6 : 2.2，与线宽 2 / 3 / 5 的感受一致
    static let weightDotDiameters: [CGFloat] = [5, 8, 11]
    /// 文字工具字号档用字母 A 的三种字号：这是表示 S / M / L 的图形而不是正文，
    /// 台阶需要一眼可辨，因此不受字号阶梯限制
    static let weightLetterSizes: [CGFloat] = [10, 13, 17]

    // MARK: - 文字编辑

    /// 编辑框内边距（在文字 origin 之外）
    static let textEditorInset: CGFloat = 4
    static let textEditorBorderWidth: CGFloat = 1
    static let textEditorDash: [NSNumber] = [4, 2]
    /// 光标停在最长行末尾时需要的额外宽度，避免插入点被裁掉
    static let textEditorCaretAllowance: CGFloat = 2

    // MARK: - 提示 HUD

    static let hintDisplayDuration: Duration = .milliseconds(1500)
    /// 提示胶囊的左右 / 上下内边距（合计）
    static let hintHorizontalPadding: CGFloat = 28
    static let hintVerticalPadding: CGFloat = 14
    static let hintFadeDuration: TimeInterval = 0.25
    static let hintBackgroundAlpha: CGFloat = 0.78

    // MARK: - 首用引导

    /// 引导条底边距屏幕底边的距离（避开常见的程序坞高度）
    static let onboardingBottomInset: CGFloat = 100
    static let onboardingHorizontalPadding: CGFloat = 14
    static let onboardingVerticalPadding: CGFloat = 7
    static let onboardingShadowOpacity: Float = 0.25
    static let onboardingShadowRadius: CGFloat = 8
    static let onboardingShadowOffsetY: CGFloat = -2

    // MARK: - 实时层与光标

    /// 实时层在标注外接矩形外扩的距离，容纳抗锯齿边缘
    static let liveLayerPadding: CGFloat = 2
    /// 自绘光标（移动、相机）：符号字号、白色描边宽度、画布留白
    static let moveCursorPointSize: CGFloat = 15
    static let cameraCursorPointSize: CGFloat = 16
    static let cursorOutlineWidth: CGFloat = 1.5
    static let cursorCanvasPadding: CGFloat = 2
}

/// 强调色与颜色换算
@MainActor
enum OverlayColors {
    /// 系统强调色（sRGB）
    static var accent: NSColor {
        NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
    }

    static func cgColor(_ color: RGBAColor) -> CGColor {
        CGColor(
            srgbRed: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        )
    }

    static func nsColor(_ color: RGBAColor) -> NSColor {
        NSColor(
            srgbRed: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        )
    }

    static func swiftUIColor(_ color: AnnotationColor) -> Color {
        let rgba = color.rgba
        return Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

/// 动效开关：遵循「减弱动态效果」
@MainActor
enum OverlayMotion {
    static var isReduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 激活底块滑动；减弱动态效果时为 nil（直接跳到位）
    static var slideAnimation: Animation? {
        isReduced ? nil : .easeOut(duration: OverlayTokens.activeSlideDuration)
    }
}
