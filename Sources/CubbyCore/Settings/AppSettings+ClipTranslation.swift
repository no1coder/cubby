import Foundation

/// 剪贴板条目翻译的设置操作（存储属性见 AppSettings，docs/CLIP-TRANSLATION-DESIGN.md §0.1 A8、§7）
extension AppSettings {
    /// 粘贴到该应用（bundle id）时总是译为的语言；没有记住时为 nil
    public func clipTranslationTarget(for bundleID: String) -> String? {
        clipTranslationTargets.language(for: bundleID)
    }

    /// 记住（language 非 nil）或忘记（nil）粘贴到该应用时的目标语言；无法识别的语言视为忘记
    public func rememberClipTranslationTarget(_ language: String?, for bundleID: String) {
        let updated = clipTranslationTargets.setting(language, for: bundleID)
        guard updated != clipTranslationTargets else { return }
        clipTranslationTargets = updated
    }

    /// 打开「复制时自动翻译」时一并打开「在卡片上显示译文」（否则自动翻译的结果在列表里看不到，原型的约定）
    public func setTranslatesClipsOnCopy(_ isOn: Bool) {
        translatesClipsOnCopy = isOn
        if isOn { showsTranslationOnCards = true }
    }
}
