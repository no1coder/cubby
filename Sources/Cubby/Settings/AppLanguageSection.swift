import CubbyCore
import SwiftUI

/// 设置 › 通用 › 语言：界面语言跟随系统，或固定为英文 / 简体中文。
/// 系统只在启动时读取界面语言，所以选择与本次显示的语言不同时提示重新打开
struct AppLanguageSection: View {
    private let store: AppLanguageStore
    /// 本次启动实际显示的界面语言
    private let runningLocalization = Bundle.main.preferredLocalizations.first ?? AppLanguage.supportedLocalizations[0]
    /// 用 -AppleLanguages 启动参数指定了语言（开发与走查截图）：参数域优先于偏好域，重新打开也不会改变，不提示
    private let isSetByLaunchArguments =
        UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[AppLanguageStore.key] != nil

    @State private var selection: AppLanguage

    init() {
        let store = AppLanguageStore()
        self.store = store
        // 首帧即为已保存的选择，避免「重新打开」一行闪现、窗口高度跳动
        _selection = State(initialValue: store.language)
    }

    var body: some View {
        Section {
            Picker("Interface language", selection: Binding(get: { selection }, set: { select($0) })) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(verbatim: title(of: language)).tag(language)
                }
            }
            if needsRelaunch {
                relaunchRow
            }
        } header: {
            Text("Language")
        } footer: {
            Text(
                "Only changes Cubby's own menus and text. Automatic translation still translates into your system language."
            )
            .foregroundStyle(.secondary)
        }
        // 可能在「系统设置 › 语言与地区 › 应用程序」中改过：设置窗口是单例、关闭后再打开不会重新 onAppear，
        // 所以在任一窗口成为主窗口时（包括重新打开设置）以偏好域为准
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            syncWithStore()
        }
    }

    private var needsRelaunch: Bool {
        !isSetByLaunchArguments
            && selection.resolvedLocalization(systemPreferences: SystemLanguages.preferred) != runningLocalization
    }

    private func syncWithStore() {
        let stored = store.language
        if stored != selection { selection = stored }
    }

    /// 语言用本名显示（用户总能认出自己的语言）；跟随系统时附上系统当前对应的语言
    private func title(of language: AppLanguage) -> String {
        guard let localization = language.localization else {
            let resolved = language.resolvedLocalization(systemPreferences: SystemLanguages.preferred)
            let name = TranslationLanguageCatalog.nativeName(of: resolved)
            return String(
                localized: "System Default (\(name))",
                comment: "Settings: app language option that follows macOS; the argument is the language's own name")
        }
        return TranslationLanguageCatalog.nativeName(of: localization)
    }

    private func select(_ language: AppLanguage) {
        store.setLanguage(language)
        selection = store.language
    }

    /// 重新打开失败时由 AppRelauncher 提示，当前实例保留
    private var relaunchRow: some View {
        HStack(spacing: 8) {
            Label("The new language takes effect after Cubby restarts", systemImage: "arrow.clockwise")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Restart Now") {
                AppRelauncher.relaunch(extraArguments: [AppRelauncher.showSettingsArgument])
            }
        }
    }
}
