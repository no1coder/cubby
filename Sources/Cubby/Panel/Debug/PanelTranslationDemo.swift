#if DEBUG
import AppKit
import CubbyCore

/// 剪贴板翻译的演示场景（README 截图，仅调试构建）：
/// - `translate-demo:text`：英文邮件，翻译卡打开在「对照」视图
/// - `translate-demo:image`：旅行应用的英文欢迎页图片，翻译卡显示译后图片
///
/// 需要 CUBBY_DATA_DIR：启动时把演示历史写进去（TranslationDemoHistory）。翻译走真实的剪贴板翻译服务
/// （分段、Vision 识别、排版与绘制），只有引擎换成按手写译文返回的 DemoTranslationEngine，不联网
enum PanelTranslationDemo: String {
    case text
    case image

    static let prefix = "translate-demo:"

    init?(scenario: String) {
        guard scenario.hasPrefix(Self.prefix) else { return nil }
        self.init(rawValue: String(scenario.dropFirst(Self.prefix.count)))
    }

    /// 译完后的视图：文本「对照」，图片「译文」
    var finalMode: TranslationViewMode {
        self == .image ? .translation : .sideBySide
    }
}

extension PanelController {
    /// 打开面板、为最新一条（已选中）打开翻译卡，译完后切到演示需要的视图
    func startTranslationDemo(_ demo: PanelTranslationDemo) {
        show()
        viewModel.toggleTranslationCard()
        Task { @MainActor [weak self] in
            // 最多等 15 秒：图片要先在本机识别文字
            for _ in 0..<150 {
                try? await Task.sleep(for: .milliseconds(100))
                guard let card = self?.viewModel.translation?.card else { return }
                if card.card?.phase == .done {
                    card.setMode(demo.finalMode)
                    return
                }
            }
        }
    }
}
#endif
