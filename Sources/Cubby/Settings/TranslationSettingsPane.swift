import SwiftUI
import CubbyCore

/// 设置 › 翻译（仅 macOS 26，docs/prototypes/screenshot-translate.html「设置 › 翻译」）：
/// 引擎（系统翻译 / 大模型）、目标语言、系统翻译的语言包说明或大模型配置，以及剪贴板条目翻译
struct TranslationSettingsPane: View {
    @Bindable var model: TranslationSettingsModel
    let store: ClipStore

    private var settings: AppSettings {
        model.settings
    }

    var body: some View {
        Form {
            Section {
                Picker("Translation engine", selection: engine) {
                    EngineOption(
                        title: "System Translation",
                        detail: "On this Mac, free and works offline (built-in macOS Translation)"
                    )
                    .tag(TranslationEngineKind.system)
                    EngineOption(
                        title: "Large language model",
                        detail: "OpenAI-compatible: DeepSeek, Qwen, Kimi, Ollama and more"
                    )
                    .tag(TranslationEngineKind.llm)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            } header: {
                Text("Translation Engine")
            }

            Section {
                Picker("Translate into", selection: target) {
                    Text("Automatic (follow system)").tag(String?.none)
                    Divider()
                    ForEach(TranslationLanguageCatalog.selectable(preferred: Locale.preferredLanguages), id: \.self) {
                        Text(verbatim: TranslationLanguageCatalog.nativeName(of: $0)).tag(Optional($0))
                    }
                }
            } footer: {
                Text(automaticTargetNote)
                    .foregroundStyle(.secondary)
            }

            switch settings.translationEngine {
            case .system: systemSection
            case .llm: TranslationLLMSection(model: model)
            }

            ClipTranslationSettingsSection(settings: settings, store: store)
        }
        .formStyle(.grouped)
        .onAppear { model.reload() }
    }

    private var systemSection: some View {
        Section {
            LabeledContent {
                Button("Manage Languages…", action: SystemTranslationSettings.open)
            } label: {
                Text("Language packs")
                Text("System Settings › General › Language & Region › Translation Languages")
            }
        } footer: {
            Label(
                "The first time you translate a language, macOS asks to download its language pack. After that, translation works offline. System Translation runs on this Mac, and text never leaves it.",
                systemImage: "lock.fill"
            )
            .foregroundStyle(.secondary)
        }
    }

    private var engine: Binding<TranslationEngineKind> {
        Binding {
            settings.translationEngine
        } set: {
            model.selectEngine($0)
        }
    }

    private var target: Binding<String?> {
        Binding {
            settings.translationTargetLanguage
        } set: {
            settings.translationTargetLanguage = $0
        }
    }

    /// 自动规则的说明，带上当前系统语言的名字（系统语言为英语时，英文原文需要在翻译条上选择目标语言）
    private var automaticTargetNote: String {
        let system = Locale.preferredLanguages.lazy.compactMap(TranslationLanguageCatalog.normalize).first ?? "en"
        let name = TranslationLanguageCatalog.localizedName(of: system)
        guard system != "en" else {
            return String(
                localized:
                    "Automatic translates into your system language (\(name)). If the text is already in English, choose a language from the translation bar while taking a screenshot.",
                comment: "Translation settings footer when the system language is English. %@ = language name")
        }
        return String(
            localized:
                "Automatic follows your system language (\(name)). Text that's already in that language is translated into English. You can also switch languages from the translation bar while taking a screenshot.",
            comment: "Translation settings footer. %@ = the system language name")
    }
}

/// 引擎单选项：标题 + 说明
private struct EngineOption: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
