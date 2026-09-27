import CoreGraphics

/// 工具栏相对选区的位置
public enum ToolbarSide: Equatable, Sendable {
    /// 选区下方外侧
    case below
    /// 选区上方外侧
    case above
    /// 选区内右下角（上下都放不下时的兜底）
    case inside
}

/// 工具栏与样式条的摆放结果（全局点坐标）
public struct ToolbarLayout: Equatable, Sendable {
    public let toolbar: CGRect
    /// 与工具栏同侧、更远离选区；未显示样式条时为 nil
    public let styleBar: CGRect?
    public let side: ToolbarSide

    public init(toolbar: CGRect, styleBar: CGRect?, side: ToolbarSide) {
        self.toolbar = toolbar
        self.styleBar = styleBar
        self.side = side
    }
}

/// 工具栏 / 样式条摆放（§2.6）：右对齐选区（选区比工具栏窄时居中），按「下 → 上 → 内」三档兜底，始终夹紧在屏幕内
public enum ToolbarPlacement {
    /// 样式条与工具栏之间的间距（§2.6）
    public static let styleBarSpacing: CGFloat = 6

    /// 上下两档是否放得下按「工具栏 + 样式条」整体高度判断，避免样式条被挤出屏幕。
    /// inside 档时样式条放在工具栏上方（朝选区中心），仍右对齐工具栏。
    public static func layout(
        toolbarSize: CGSize,
        styleBarSize: CGSize?,
        selection: CGRect,
        screen: CGRect,
        gap: CGFloat = 8,
        inset: CGFloat = 8
    ) -> ToolbarLayout {
        let toolbar = fitted(toolbarSize, in: screen)
        let style = styleBarSize.map { fitted($0, in: screen) }
        let stackHeight = toolbar.height + (style.map { styleBarSpacing + $0.height } ?? 0)
        let box = selection.standardized

        let side: ToolbarSide
        let toolbarY: CGFloat
        if box.maxY + gap + stackHeight <= screen.maxY {
            side = .below
            toolbarY = box.maxY + gap
        } else if box.minY - gap - stackHeight >= screen.minY {
            side = .above
            toolbarY = box.minY - gap - toolbar.height
        } else {
            side = .inside
            toolbarY = box.maxY - inset - toolbar.height
        }

        // 选区比工具栏窄时以选区中心对齐（评审 P2-10：极小选区旁挂一条长工具栏会显得脱节），否则右对齐
        let toolbarX =
            box.width < toolbar.width
            ? box.midX - toolbar.width / 2
            : (side == .inside ? box.maxX - inset : box.maxX) - toolbar.width
        let toolbarFrame = clamped(
            CGRect(x: toolbarX, y: toolbarY, width: toolbar.width, height: toolbar.height),
            in: screen
        )
        let styleFrame = style.map { styleBarFrame(size: $0, toolbar: toolbarFrame, side: side, screen: screen) }
        return ToolbarLayout(toolbar: toolbarFrame, styleBar: styleFrame, side: side)
    }

    /// 样式条：below 时在工具栏下方，above / inside 时在工具栏上方；右对齐工具栏
    private static func styleBarFrame(size: CGSize, toolbar: CGRect, side: ToolbarSide, screen: CGRect) -> CGRect {
        let y =
            side == .below
            ? toolbar.maxY + styleBarSpacing
            : toolbar.minY - styleBarSpacing - size.height
        return clamped(CGRect(x: toolbar.maxX - size.width, y: y, width: size.width, height: size.height), in: screen)
    }

    private static func fitted(_ size: CGSize, in screen: CGRect) -> CGSize {
        CGSize(width: min(size.width, screen.width), height: min(size.height, screen.height))
    }

    private static func clamped(_ rect: CGRect, in screen: CGRect) -> CGRect {
        SelectionGeometry.clamped(rect, to: screen)
    }
}
