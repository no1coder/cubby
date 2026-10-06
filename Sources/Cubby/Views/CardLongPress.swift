import SwiftUI

/// 卡片长按（docs/TEXT-PICK-DESIGN.md P2、§2）：按下后卡片轻微缩小（0.985，减弱动态效果时不缩放），
/// 满 0.45 秒打开拆词卡；移动超过 4pt 取消（交给拖出）。与单击选中、双击粘贴同时识别（simultaneousGesture），
/// 不抢它们的事件：短按松开时长按失败，单击照常选中；双击两次都远短于 0.45 秒
struct CardLongPress: ViewModifier {
    let onLongPress: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressing && !reduceMotion ? TextPickMetrics.pressedScale : 1)
            .animation(.easeOut(duration: Motion.fade), value: isPressing)
            .simultaneousGesture(
                LongPressGesture(
                    minimumDuration: TextPickMetrics.longPressDuration,
                    maximumDistance: TextPickMetrics.longPressMaxDistance
                )
                .updating($isPressing) { pressing, state, _ in state = pressing }
                .onEnded { _ in onLongPress() }
            )
    }
}
