import SwiftUI
import CubbyCore

/// 设置 › 翻译 › 大模型：服务商、接入地址、API Key（存钥匙串，只显示掩码）、模型、测试连接、隐私说明
struct TranslationLLMSection: View {
    @Bindable var model: TranslationSettingsModel

    private enum Field: Hashable {
        case baseURL
        case model
    }

    @FocusState private var focus: Field?

    private static let fieldWidth: CGFloat = 230

    var body: some View {
        Section {
            Picker("Provider", selection: provider) {
                ForEach(LLMProviderPreset.all) { preset in
                    Text(verbatim: preset.displayName).tag(preset.id)
                }
            }
            baseURLRow
            if model.showsKeyField {
                apiKeyRow
            }
            modelRow
            testRow
        } header: {
            Text("Large Language Model")
        } footer: {
            Label(privacyNote, systemImage: "lock.fill")
                .foregroundStyle(.secondary)
        }
        .onChange(of: focus) { old, _ in
            // 离开输入框即提交
            switch old {
            case .baseURL: model.commitBaseURL()
            case .model: model.commitModel()
            case nil: break
            }
        }
    }

    private var baseURLRow: some View {
        LabeledContent {
            HStack(spacing: 6) {
                TextField("Base URL", text: $model.baseURLText, prompt: Text(verbatim: "https://…/v1"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(width: Self.fieldWidth)
                    .focused($focus, equals: .baseURL)
                    .onSubmit(model.commitBaseURL)
                    .autocorrectionDisabled()
                if model.preset.endpoints.count > 1 {
                    Menu {
                        ForEach(model.preset.endpoints, id: \.url) { endpoint in
                            Button {
                                model.selectEndpoint(endpoint.url)
                            } label: {
                                Text(verbatim: "\(endpoint.regionName) · \(endpoint.url)")
                            }
                        }
                    } label: {
                        Image(systemName: "globe")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(Text("Choose a region"))
                }
            }
        } label: {
            Text("Base URL")
            if let issue = model.baseURLIssue {
                Text(TranslationSettingsCopy.message(for: issue))
                    .foregroundStyle(.red)
            }
        }
    }

    /// 密钥一行：已保存（掩码 + 移除）/ 无法访问钥匙串（重试）/ 未保存或属于其他主机（输入框 + 保存）
    private var apiKeyRow: some View {
        LabeledContent {
            switch model.keyState {
            case .available:
                HStack(spacing: 8) {
                    Text(verbatim: model.savedKeyMask ?? "")
                        .monospaced()
                        .foregroundStyle(.secondary)
                    Button("Remove", role: .destructive, action: model.removeKey)
                }
            case .inaccessible:
                Button("Try Again", action: model.retryKeychain)
            case .missing, .savedForOtherHost:
                HStack(spacing: 6) {
                    SecureField("API Key", text: $model.keyDraft, prompt: Text("Paste API key"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(width: Self.fieldWidth - 60)
                        .onSubmit(model.saveKey)
                    Button("Save Key", action: model.saveKey)
                        .disabled(model.keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        } label: {
            Text("API Key")
            keyNote
        }
    }

    /// 密钥一行的说明：操作错误、钥匙串无法访问、密钥属于其他主机，否则「存储在钥匙串中」
    @ViewBuilder private var keyNote: some View {
        if let error = model.keyError {
            Text(error).foregroundStyle(.red)
        } else {
            switch model.keyState {
            case .inaccessible:
                Text(TranslationSettingsCopy.keychainUnavailable).foregroundStyle(.red)
            case .savedForOtherHost(let savedHost):
                Text(
                    TranslationSettingsCopy.keySavedForOtherHost(
                        savedHost, currentHost: model.host ?? model.baseURLText)
                )
                .foregroundStyle(.orange)
            case .available, .missing:
                Label("Stored in Keychain", systemImage: "lock.fill")
            }
        }
    }

    private var modelRow: some View {
        LabeledContent {
            HStack(spacing: 6) {
                TextField("Model", text: $model.modelText, prompt: Text("Model name"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(width: Self.fieldWidth - 80)
                    .focused($focus, equals: .model)
                    .onSubmit(model.commitModel)
                    .autocorrectionDisabled()
                Menu {
                    ForEach(modelChoices, id: \.self) { name in
                        Button(name) { model.selectModel(name) }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(modelChoices.isEmpty)
                .help(Text("Choose a model"))
                Button("Refresh", action: model.refreshModels)
                    .disabled(model.modelsState == .running)
            }
        } label: {
            Text("Model")
            ProbeStatus(state: model.modelsState)
        }
    }

    private var testRow: some View {
        HStack(spacing: 10) {
            Button("Test Connection", action: model.testConnection)
                .disabled(model.testState == .running)
            ProbeStatus(state: model.testState)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    /// 模型选单：已获取的列表；尚未获取时只有预设的建议模型
    private var modelChoices: [String] {
        guard model.models.isEmpty else { return model.models }
        return model.preset.suggestedModel.map { [$0] } ?? []
    }

    private var provider: Binding<String> {
        Binding {
            model.settings.translationProviderID
        } set: {
            model.selectPreset($0)
        }
    }

    private var privacyNote: String {
        guard let host = model.host else {
            return String(
                localized:
                    "Images are never uploaded. Text under mosaic and text that looks like a secret is never sent.",
                comment: "Translation settings privacy note when the base URL is not set")
        }
        if model.preset.isLocalService, model.baseURLIsLoopback {
            return String(
                localized:
                    "When translating, text recognized in the selection is sent to Ollama on this Mac (\(host)) and never leaves it. Images are never uploaded.",
                comment: "Translation settings privacy note for a local Ollama. %@ = host")
        }
        return String(
            localized:
                "When translating, text recognized in the selection is sent to \(host). Images are never uploaded. Text under mosaic and text that looks like a secret is never sent.",
            comment: "Translation settings privacy note. %@ = host name of the translation service")
    }
}

/// 探测状态：进行中显示小菊花，成功为绿色，失败为红色
private struct ProbeStatus: View {
    let state: TranslationSettingsModel.ProbeState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .running:
            ProgressView().controlSize(.small)
        case .succeeded(let message):
            Text(verbatim: message).foregroundStyle(.green)
        case .failed(let message):
            Text(verbatim: message).foregroundStyle(.red)
        }
    }
}
