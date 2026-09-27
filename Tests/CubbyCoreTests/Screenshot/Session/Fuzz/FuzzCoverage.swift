import CoreGraphics
@testable import CubbyCore

/// 模糊测试到达过的状态与事件种类：用来证明生成器真的走到了深层状态、覆盖了全部事件
struct FuzzCoverage {
    /// 关闭时 `record` 什么都不做（主模糊测试不需要统计，省时间）
    let isEnabled: Bool
    private(set) var features: Set<String> = []

    init(enabled: Bool) {
        isEnabled = enabled
    }

    /// 必须到达的全部特征
    static var required: Set<String> {
        var names: Set<String> = [
            "phase.hovering", "phase.selecting", "phase.adjusting", "phase.annotating", "phase.editingText",
            "drag.creatingSelection", "drag.movingSelection", "drag.resizing", "drag.drawing", "drag.movingAnnotation",
            "state.windowCaptureMode", "state.hoverDepth>0", "state.discardArmed", "state.textReedit",
            "state.selectedAnnotation", "state.canRedo", "state.spaceTapPending", "state.selectionOnExternal",
            "state.selectionOnLower",
            "effect.beginTextEditing", "effect.endTextEditing", "effect.stylesChanged", "effect.showHint",
            "finish.copy", "finish.save", "finish.pin", "finish.extractText", "finish.copyColor",
            "finish.captureWindow", "finish.cancel",
            "event.mouseMoved", "event.mouseDown", "event.doubleClick", "event.mouseDragged", "event.mouseUp",
            "event.rightMouseDown", "event.modifiersChanged", "event.command", "event.styleChanged",
            "event.textChanged", "event.textCommitted", "event.toolbarAction", "event.scrolled",
            "command.escape", "command.confirm", "command.save", "command.pin", "command.extractText",
            "command.selectAll", "command.undo", "command.redo", "command.copyColor", "command.selectTool",
            "command.nudge", "command.deleteAnnotation", "command.commitText", "command.cycleHover",
            "command.selectColor", "command.adjustWeight", "drag.movingArrowEnd", "state.arrowSnapGuide",
            "toolbar.copy", "toolbar.save", "toolbar.pin", "toolbar.extractText", "toolbar.copyColor",
            "toolbar.captureWindow", "toolbar.cancel",
            "event.translation", "command.translate", "effect.translation", "translation.recognizing",
            "translation.translating", "translation.ready", "translation.partial", "translation.failed",
            "translation.noText", "translation.needsTargetLanguage", "translation.split", "translation.peek",
            "translation.hidden", "translation.retranslated",
        ]
        for tool in ScreenshotTool.allCases where tool != .pointer {
            names.insert("annotation.\(tool.rawValue)")
        }
        return names
    }

    mutating func record(_ step: FuzzStep) {
        guard isEnabled else { return }
        let session = step.session
        features.insert("phase.\(session.phase)")
        features.insert("event." + Self.name(of: step.event))
        if case .command(let command) = step.event {
            features.insert("command." + Self.name(of: command))
        }
        if case .toolbarAction(let outcome) = step.event {
            features.insert("toolbar." + Self.name(of: outcome))
        }
        if case .mouseDown(_, let count) = step.event, count >= 2 {
            features.insert("event.doubleClick")
        }
        if session.drag != .none {
            features.insert("drag." + Self.name(of: session.drag))
        }
        recordState(session)
        for effect in step.effects {
            features.insert(Self.name(of: effect))
        }
        for annotation in session.document.annotations {
            features.insert("annotation.\(annotation.tool.rawValue)")
        }
    }

    private mutating func recordState(_ session: ScreenshotSession) {
        let flags: [(Bool, String)] = [
            (session.isWindowCaptureMode, "state.windowCaptureMode"),
            (session.hoverDepth > 0, "state.hoverDepth>0"),
            (session.isDiscardArmed, "state.discardArmed"),
            (session.textEditing?.existing != nil, "state.textReedit"),
            (session.selectedAnnotation != nil, "state.selectedAnnotation"),
            (session.document.canRedo, "state.canRedo"),
            (session.isSpaceTapPending, "state.spaceTapPending"),
            (session.screenID == 2 && session.phase != .selecting, "state.selectionOnExternal"),
            (session.screenID == 3 && session.phase != .selecting, "state.selectionOnLower"),
            (session.arrowSnapGuide != nil, "state.arrowSnapGuide"),
        ]
        recordTranslation(session)
        for (flag, name) in flags where flag {
            features.insert(name)
        }
    }

    /// 截图翻译到达过的阶段与查看方式
    private mutating func recordTranslation(_ session: ScreenshotSession) {
        guard let run = session.translation else { return }
        features.insert("translation." + Self.name(of: run.status))
        if run.parent != nil {
            features.insert("translation.retranslated")
        }
        switch session.translationDisplay {
        case .split: features.insert("translation.split")
        case .hidden where !run.placed.isEmpty: features.insert("translation.hidden")
        default: break
        }
        if session.isPeekingOriginal {
            features.insert("translation.peek")
        }
    }

    private static func name(of status: TranslationStatus) -> String {
        switch status {
        case .recognizing: "recognizing"
        case .translating: "translating"
        case .ready: "ready"
        case .partial: "partial"
        case .failed: "failed"
        case .noText: "noText"
        case .needsTargetLanguage: "needsTargetLanguage"
        }
    }

    // 名称用显式 switch 而不是 "\(value)"：后者走反射，逐步统计时很慢

    private static func name(of event: ScreenshotEvent) -> String {
        switch event {
        case .mouseMoved: "mouseMoved"
        case .mouseDown: "mouseDown"
        case .mouseDragged: "mouseDragged"
        case .mouseUp: "mouseUp"
        case .rightMouseDown: "rightMouseDown"
        case .modifiersChanged: "modifiersChanged"
        case .command: "command"
        case .styleChanged: "styleChanged"
        case .textChanged: "textChanged"
        case .textCommitted: "textCommitted"
        case .toolbarAction: "toolbarAction"
        case .scrolled: "scrolled"
        case .translation: "translation"
        }
    }

    private static func name(of command: ScreenshotCommand) -> String {
        switch command {
        case .escape: "escape"
        case .confirm: "confirm"
        case .save: "save"
        case .pin: "pin"
        case .extractText: "extractText"
        case .selectAll: "selectAll"
        case .undo: "undo"
        case .redo: "redo"
        case .copyColor: "copyColor"
        case .selectTool: "selectTool"
        case .nudge: "nudge"
        case .deleteAnnotation: "deleteAnnotation"
        case .commitText: "commitText"
        case .cycleHover: "cycleHover"
        case .selectColor: "selectColor"
        case .adjustWeight: "adjustWeight"
        case .translate: "translate"
        }
    }

    private static func name(of outcome: ScreenshotOutcome) -> String {
        switch outcome {
        case .copy: "copy"
        case .save: "save"
        case .pin: "pin"
        case .extractText: "extractText"
        case .copyColor: "copyColor"
        case .captureWindow: "captureWindow"
        case .cancel: "cancel"
        }
    }

    private static func name(of drag: DragState) -> String {
        switch drag {
        case .none: "none"
        case .creatingSelection: "creatingSelection"
        case .movingSelection: "movingSelection"
        case .resizing: "resizing"
        case .drawing: "drawing"
        case .movingAnnotation: "movingAnnotation"
        case .movingArrowEnd: "movingArrowEnd"
        }
    }

    private static func name(of effect: ScreenshotEffect) -> String {
        switch effect {
        case .finish(let outcome): "finish." + name(of: outcome)
        case .beginTextEditing: "effect.beginTextEditing"
        case .endTextEditing: "effect.endTextEditing"
        case .stylesChanged: "effect.stylesChanged"
        case .showHint: "effect.showHint"
        case .translation: "effect.translation"
        }
    }
}
