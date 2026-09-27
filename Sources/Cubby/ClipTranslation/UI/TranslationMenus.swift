import AppKit
import CubbyCore
import SwiftUI

/// 语言选单与引擎选单：程序化弹出 NSMenu（预览面板不可成为 key，SwiftUI Menu 的可靠性无法保证，R1 的回退方案）。
/// 菜单项的动作用闭包（ClosureMenuItem），E2E 可以直接构造菜单并执行某一项而不必真的弹出
@MainActor
enum TranslationMenus {
    /// 语言选单：候选语言（自称）、原文语言置灰，分隔线后是「粘贴到 <App> 时总是译为此语言」
    static func languageMenu(for card: TranslationCard, controller: TranslationCardController) -> NSMenu {
        let menu = NSMenu()
        let translator = controller.environment.translator
        let source = card.plan?.detectedSource
        let current = card.isReversed ? nil : card.plan?.languages.target
        for code in translator.selectableLanguages {
            let isSource = source.map { controller.environment.isSameLanguage($0, code) } ?? false
            let item = ClosureMenuItem(title: TranslationCopy.nativeLanguageName(code)) {
                controller.choose(target: code)
            }
            item.state = current.map { controller.environment.isSameLanguage($0, code) } == true ? .on : .off
            item.isEnabled = !isSource
            if isSource {
                item.attributedTitle = sourceTitle(code)
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(rememberItem(card: card, controller: controller))
        menu.autoenablesItems = false
        return menu
    }

    /// 引擎选单：说明当前引擎与文字去向，外加「翻译设置…」
    static func engineMenu(for plan: ClipTranslationPlan?, openSettings: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if let plan {
            let header = NSMenuItem(title: TranslationCopy.engineMenuHeader(plan), action: nil, keyEquivalent: "")
            header.image = NSImage(
                systemSymbolName: plan.sendsTextOffDevice ? "cloud" : "laptopcomputer", accessibilityDescription: nil)
            header.state = .on
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())
        }
        menu.addItem(ClosureMenuItem(title: TranslationCopy.translationSettings, handler: openSettings))
        return menu
    }

    /// 在视图左下方弹出
    static func popUp(_ menu: NSMenu, below view: NSView) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }

    private static func rememberItem(card: TranslationCard, controller: TranslationCardController) -> NSMenuItem {
        let target = controller.environment.pasteTarget()
        let item = ClosureMenuItem(title: TranslationCopy.rememberTargetMenuItem(app: target?.name ?? "")) {
            controller.toggleRememberTarget()
        }
        let remembered = target?.bundleID.flatMap { controller.environment.translator.rememberedTarget(for: $0) }
        let current = card.plan?.languages.target
        let isRemembered = zip([remembered].compactMap { $0 }, [current].compactMap { $0 })
            .contains { controller.environment.isSameLanguage($0, $1) }
        item.state = isRemembered ? .on : .off
        item.isEnabled = !card.isReversed && current != nil && target?.bundleID != nil
        return item
    }

    /// 原文语言：名称后以次要色注明「原文语言」
    private static func sourceTitle(_ code: String) -> NSAttributedString {
        let title = NSMutableAttributedString(
            string: TranslationCopy.nativeLanguageName(code),
            attributes: [.foregroundColor: NSColor.disabledControlTextColor, .font: NSFont.menuFont(ofSize: 0)])
        title.append(
            NSAttributedString(
                string: "  " + TranslationCopy.sourceLanguageMenuNote,
                attributes: [
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                ]))
        return title
    }
}

/// 取得 SwiftUI 按钮背后的 NSView，作为菜单弹出的锚点
struct MenuAnchor: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = AnchorView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class AnchorView: NSView {
        var onResolve: ((NSView) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { onResolve?(self) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
