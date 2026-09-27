import CubbyCore
import SwiftUI

/// 翻译卡的状态页（原型 stateHTML）：失败、疑似密钥、原文已是目标语言、不支持、已取消。
/// 圆形图标 + 标题 + 说明 + 操作按钮（去设置 / 下载语言 / 重试 / 仍然翻译）
struct TranslationStateView: View {
    enum Tone {
        case warning
        case info
        case lock

        var tint: Color {
            switch self {
            case .warning: TranslationPalette.warning
            case .info: .secondary
            case .lock: TranslationPalette.lock
            }
        }

        var fill: Color {
            switch self {
            case .warning: TranslationPalette.warning.opacity(0.16)
            case .info: Color.primary.opacity(0.08)
            case .lock: TranslationPalette.lock.opacity(0.16)
            }
        }
    }

    struct Action {
        let title: String
        let isPrimary: Bool
        let perform: () -> Void
    }

    let symbol: String
    let tone: Tone
    let title: String
    let detail: String?
    let actions: [Action]

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tone.tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(tone.fill))
                .padding(.bottom, 2)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: FontSize.body, weight: .semibold))
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(size: FontSize.footnote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 340)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                        Button(action.title, action: action.perform)
                            .buttonStyle(CapsuleButtonStyle(isPrimary: action.isPrimary))
                            .e2eAnchor("card.action.\(index)")
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(.top, 26)
        .padding(.horizontal, 30)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, minHeight: TranslationCardMetrics.stateMinHeight)
        .accessibilityElement(children: .contain)
    }
}

extension TranslationStateView {
    /// 卡片阶段对应的状态页；正常显示内容的阶段为 nil
    @MainActor
    static func make(for card: TranslationCard, controller: TranslationCardController) -> TranslationStateView? {
        switch card.phase {
        case .failed(let failure):
            let text = TranslationCopy.failure(failure, plan: card.plan)
            return TranslationStateView(
                symbol: "exclamationmark.triangle", tone: .warning, title: text.title, detail: text.detail,
                actions: failureActions(failure, controller: controller))
        case .needsSecretConfirmation:
            return TranslationStateView(
                symbol: "key.fill", tone: .lock, title: TranslationCopy.secretTitle(),
                detail: TranslationCopy.secretDetail(card.plan),
                actions: [
                    Action(title: TranslationCopy.translateAnyway, isPrimary: false, perform: controller.confirmSecret)
                ])
        case .alreadyTarget(let language):
            return TranslationStateView(
                symbol: "character.bubble", tone: .info, title: TranslationCopy.alreadyTargetTitle(language),
                detail: TranslationCopy.alreadyTargetDetail, actions: [])
        case .unsupported(let reason):
            return TranslationStateView(
                symbol: "nosign", tone: .info, title: TranslationCopy.unsupportedTitle(reason),
                detail: reason == .noText ? TranslationCopy.noTextDetail : TranslationCopy.unsupportedDetail,
                actions: [])
        case .cancelled:
            return TranslationStateView(
                symbol: "xmark", tone: .info, title: TranslationCopy.cancelledTitle,
                detail: TranslationCopy.cancelledDetail,
                actions: [Action(title: TranslationCopy.retry, isPrimary: true, perform: controller.retry)])
        default:
            return nil
        }
    }

    @MainActor
    private static func failureActions(
        _ failure: TranslationFailure, controller: TranslationCardController
    ) -> [Action] {
        if controller.environment.translator.canResolve(failure) {
            return [
                Action(
                    title: TranslationCopy.resolveAction(failure), isPrimary: true, perform: controller.resolveFailure)
            ]
        }
        switch failure {
        case .network, .rateLimited, .server, .invalidResponse:
            return [Action(title: TranslationCopy.retry, isPrimary: true, perform: controller.retry)]
        default:
            return []
        }
    }
}
