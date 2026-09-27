import AppKit
import SwiftUI

/// 系统搜索框（放大镜、清除按钮、esc 清空）：输入即搜索，↩ 跳到下一处命中，focusRequest 变化时获得焦点
struct GuideSearchField: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = String(
            localized: "Search the Guide", comment: "User guide window: search field placeholder")
        field.sendsSearchStringImmediately = true
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.handledFocusRequest != focusRequest {
            context.coordinator.handledFocusRequest = focusRequest
            field.window?.makeFirstResponder(field)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: GuideSearchField
        /// 创建时已有的请求不算：打开窗口时焦点留在正文
        var handledFocusRequest: Int

        init(parent: GuideSearchField) {
            self.parent = parent
            self.handledFocusRequest = parent.focusRequest
        }

        @objc func searchChanged(_ sender: NSSearchField) {
            if parent.text != sender.stringValue {
                parent.text = sender.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }
    }
}
