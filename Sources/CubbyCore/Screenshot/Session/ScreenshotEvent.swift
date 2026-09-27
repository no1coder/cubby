import CoreGraphics
import Foundation

/// 会话的出口（§2.8）
public enum ScreenshotOutcome: Equatable, Sendable {
    case copy
    case save
    case pin
    case extractText
    /// 取色：参数为放大镜第二行当前显示的文本（HEX 或 RGB）
    case copyColor(String)
    /// 纯净窗口截图（契约扩展）：由 App 层按窗口 id 单独采集；includeShadow = 是否带系统窗口阴影
    case captureWindow(windowID: UInt32, includeShadow: Bool)
    case cancel
}

/// 覆盖层翻译后交给 reducer 的输入事件；坐标一律为全局点（§3.2）
public enum ScreenshotEvent: Equatable, Sendable {
    case mouseMoved(CGPoint)
    case mouseDown(CGPoint, clickCount: Int)
    case mouseDragged(CGPoint)
    case mouseUp(CGPoint)
    case rightMouseDown(CGPoint)
    /// 修饰键变化（含覆盖层自行维护的空格）
    case modifiersChanged(KeyModifiers)
    case command(ScreenshotCommand)
    /// 样式条点击
    case styleChanged(AnnotationStyle)
    /// 契约扩展：编辑器文本变化（NSTextView didChange 时发送），使 reducer 能在任何提交时机拿到文本
    case textChanged(String)
    /// 显式提交；nil / 空白 = 丢弃
    case textCommitted(String?)
    /// 工具栏按钮（出口）
    case toolbarAction(ScreenshotOutcome)
    /// 契约扩展：滚轮 / 触控板竖直滚动（点，AppKit scrollingDeltaY 的符号）；hovering 时逐层切换窗口
    case scrolled(deltaY: CGFloat)
    /// 契约扩展：截图翻译（用户操作与流水线回报，见 ScreenshotTranslation.swift）
    case translation(TranslationEvent)
}

/// 需要覆盖层以 HUD 显示的提示（契约扩展）
public enum ScreenshotHint: Equatable, Sendable {
    /// 有标注时第一次按 Esc（PM Q1）
    case pressEscapeAgainToDiscard
    /// 翻译进行中按 Esc：只取消了翻译（有标注，再按 Esc 会先进入待确认）
    case translationCancelled
    /// 翻译进行中按 Esc：只取消了翻译；再按一次 Esc 关闭截图
    case translationCancelledPressEscapeAgain
    /// 翻译失败 / 没有文字时按 Esc：关闭了翻译条
    case translationClosed

    /// 本地化文案（英文 key）
    public var message: String {
        switch self {
        case .pressEscapeAgainToDiscard:
            String(
                localized: "Press Esc again to discard",
                comment: "Screenshot HUD after the first Esc when annotations exist")
        case .translationCancelled:
            String(
                localized: "Translation cancelled",
                comment: "Screenshot HUD after Esc stops a translation in progress")
        case .translationCancelledPressEscapeAgain:
            String(
                localized: "Translation cancelled · Press Esc again to close",
                comment:
                    "Screenshot HUD after Esc stops a translation in progress and nothing else is on the screenshot")
        case .translationClosed:
            String(
                localized: "Translation closed",
                comment: "Screenshot HUD after Esc closes a failed translation")
        }
    }
}

/// reducer 要求覆盖层执行的副作用
public enum ScreenshotEffect: Equatable, Sendable {
    /// 结束会话：覆盖层立即 orderOut，按 outcome 导出并回调委托
    case finish(ScreenshotOutcome)
    /// 打开文字编辑器
    case beginTextEditing(TextEditingState, initialText: String)
    /// 关闭文字编辑器（文本已由 reducer 提交，覆盖层无需回传）
    case endTextEditing
    /// 工具样式变化，需持久化到 AppSettings.annotationStyles
    case stylesChanged(ToolStyles)
    /// 契约扩展：显示提示 HUD
    case showHint(ScreenshotHint)
    /// 契约扩展：截图翻译流水线要执行的动作（识别、翻译、重试、取消）
    case translation(TranslationEffect)
}
