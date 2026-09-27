import AppKit
import CubbyCore

// 面板控制器里的剪贴板翻译接线（docs/CLIP-TRANSLATION-DESIGN.md §1、§4）：创建翻译控制器、
// 把粘贴 / 复制译文接到粘贴流程，把「去设置 / 下载语言」交给翻译服务

extension PanelController {

    /// clipTranslation 变化时重建翻译控制器；nil 或 macOS 26 以下时翻译不可用（K8）
    func configureTranslation() {
        guard #available(macOS 26, *), let translator = clipTranslation else {
            viewModel.translation?.tearDown()
            viewModel.translation = nil
            return
        }
        let environment = ClipTranslationEnvironment(
            translator: translator,
            item: { [weak store] id in store?.item(id: id) },
            pasteTarget: { [weak viewModel] in viewModel?.target },
            translatedImageURL: { [weak store] entry in store?.translatedImageURL(for: entry) },
            timings: translationTimings
        )
        let controller = ClipTranslationController(environment: environment)
        controller.onPaste = { [weak self] request in self?.performTranslation(request) }
        controller.onCopy = { [weak self] request in self?.copyTranslation(request) ?? false }
        controller.onResolve = { [weak self] failure in self?.resolve(failure, with: translator) }
        controller.onNotice = { [weak self] message in
            self?.viewModel.showToast(.info(message, symbolName: "exclamationmark.triangle"))
        }
        viewModel.translation?.tearDown()
        viewModel.translation = controller
    }

    /// 「去设置 / 下载语言」：面板先无动画隐藏（同打开设置），再交给翻译服务；面板已关，不自动重试（§4）
    private func resolve(_ failure: TranslationFailure, with translator: any ClipTranslating) {
        hide(animated: false)
        Task { @MainActor in
            _ = await translator.resolve(failure)
        }
    }

    /// 粘贴译文：写入后提升原条目，投递段与条目粘贴相同；HUD 注明引擎（A7）
    func performTranslation(_ request: TranslationPasteRequest) {
        guard paster.write(request) else {
            reportPasteFailure(request)
            return
        }
        // 富文本条目的译文按纯文本写入时，HUD 注明「纯文本」
        let plainText =
            request.result.imageURL == nil && request.result.richText != nil
            && !paster.writesRichText(request.style)
        paster.deliver(
            promoting: request.item.id, copyOnly: false, target: viewModel.target, anchor: anchor,
            copied: PanelPaster.translationMessage(request, pasted: false, plainText: plainText),
            pasted: PanelPaster.translationMessage(request, pasted: true, plainText: plainText)
        ) { hide(animated: false) }
    }

    /// 写剪贴板失败：在请求来源处提示（卡片底栏、⌥↩ 的行内问题、底栏轻提示）
    private func reportPasteFailure(_ request: TranslationPasteRequest) {
        NSSound.beep()
        let message = TranslationCopy.inlineIssue(.pasteFailed, plan: nil)
        switch request.origin {
        case .card: viewModel.translation?.card.showFlash(TranslationFlash(message: message, isWarning: true))
        case .inline: viewModel.translation?.inline.reportPasteFailure(for: request.item)
        case .peek, .menu: viewModel.showToast(.error(message))
        }
    }

    /// 复制译文（⌘C、右键「复制译文」）：写入剪贴板，面板留着
    func copyTranslation(_ request: TranslationPasteRequest) -> Bool {
        paster.write(request)
    }
}
