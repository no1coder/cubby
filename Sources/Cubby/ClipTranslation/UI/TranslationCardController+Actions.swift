import AppKit
import CubbyCore

// 翻译卡上的结果操作：复制译文（⌘C）、存为新条目（⌘S）（§4、§2.6）；粘贴见 TranslationCardController.paste

extension TranslationCardController {
    /// 复制译文并留在面板
    func copy() {
        guard let current = card, let result = current.result, let item = environment.item(current.itemID) else {
            NSSound.beep()
            showFlash(TranslationFlash(message: TranslationCopy.noTranslationYet(card?.phase), isWarning: true))
            return
        }
        let request = TranslationPasteRequest(item: item, result: result, style: .standard, origin: .card)
        let copied = onCopy?(request) ?? false
        showFlash(
            copied
                ? TranslationFlash(message: TranslationCopy.copiedFlash(isImage: current.isImage), isWarning: false)
                : TranslationFlash(message: TranslationCopy.copyFailed, isWarning: true))
    }

    /// 存为新条目：受暂停记录、疑似密钥、长度上限约束（由翻译服务判断）
    func save() {
        guard let result = card?.result else {
            NSSound.beep()
            showFlash(TranslationFlash(message: TranslationCopy.saveNeedsTranslation, isWarning: true))
            return
        }
        let saved = environment.translator.saveAsNewItem(result)
        showFlash(
            saved
                ? TranslationFlash(message: TranslationCopy.savedFlash, isWarning: false)
                : TranslationFlash(message: TranslationCopy.saveFailed, isWarning: true))
    }
}
