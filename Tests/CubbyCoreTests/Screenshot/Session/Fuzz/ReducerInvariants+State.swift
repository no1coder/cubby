import CoreGraphics
@testable import CubbyCore

/// 只看 reduce 结果本身的不变量
extension ReducerInvariantChecks {
    static func selectionGeometry(_ step: FuzzStep) -> String? {
        let session = step.session
        guard let selection = session.selection else { return nil }
        guard let id = session.screenID, let screen = step.topology.screen(id: id) else {
            return "selection \(selection) has no resolvable screen (screenID \(String(describing: session.screenID)))"
        }
        let frame = screen.frame
        if selection.width < 0 || selection.height < 0 {
            return "negative size \(selection)"
        }
        if selection.minX < frame.minX || selection.minY < frame.minY || selection.maxX > frame.maxX
            || selection.maxY > frame.maxY
        {
            return "selection \(selection) outside screen \(frame)"
        }
        let minimum = SelectionGeometry.minSize
        if session.phase != .selecting && (selection.width < minimum.width || selection.height < minimum.height) {
            return "selection \(selection) smaller than minSize in \(session.phase)"
        }
        let scaled = [
            (selection.minX - frame.minX) * screen.scale, (selection.minY - frame.minY) * screen.scale,
            selection.width * screen.scale, selection.height * screen.scale,
        ]
        if scaled.contains(where: { $0.rounded() != $0 }) {
            return "selection \(selection) not on the @\(screen.scale)x pixel grid"
        }
        return nil
    }

    static func selectionScreenPairing(_ step: FuzzStep) -> String? {
        let session = step.session
        return (session.selection == nil) == (session.screenID == nil)
            ? nil
            : "selection \(String(describing: session.selection)) vs screenID \(String(describing: session.screenID))"
    }

    static func phaseConsistency(_ step: FuzzStep) -> String? {
        let session = step.session
        let creating: Bool
        if case .creatingSelection = session.drag {
            creating = true
        } else {
            creating = false
        }
        var problems: [String] = []
        func require(_ condition: Bool, _ message: String) {
            if !condition {
                problems.append(message)
            }
        }
        require(session.phase == .hovering || session.hover == nil, "hover outside hovering")
        require((session.phase == .editingText) == (session.textEditing != nil), "textEditing vs phase")
        require((session.phase == .selecting) == creating, "creatingSelection drag vs phase")
        switch session.phase {
        case .hovering:
            require(session.selection == nil, "selection while hovering")
            require(session.tool == .pointer, "tool \(session.tool) while hovering")
            require(session.drag == .none, "drag \(session.drag) while hovering")
            require(session.selectedAnnotation == nil, "selected annotation while hovering")
        case .selecting:
            require(session.selection != nil, "no live selection while selecting")
            require(session.selectedAnnotation == nil, "selected annotation while selecting")
        case .adjusting:
            require(session.tool == .pointer, "tool \(session.tool) in adjusting")
            require(session.selection != nil, "no selection in adjusting")
        case .annotating:
            require(session.tool != .pointer, "pointer tool in annotating")
            require(session.selection != nil, "no selection in annotating")
        case .editingText:
            require(session.tool == .text, "tool \(session.tool) while editing text")
            require(session.selection != nil, "no selection while editing text")
            require(session.drag == .none, "drag \(session.drag) while editing text")
            require(session.selectedAnnotation == session.textEditing?.existing, "selected != edited annotation")
            if let existing = session.textEditing?.existing {
                require(session.document.annotation(id: existing)?.tool == .text, "edited annotation is not text")
            }
        }
        return problems.isEmpty ? nil : "\(session.phase): " + problems.joined(separator: "; ")
    }

    static func hoverDepth(_ step: FuzzStep) -> String? {
        let session = step.session
        if abs(session.scrollAccumulator) >= ScreenshotReducer.scrollStepThreshold {
            return "scroll accumulator \(session.scrollAccumulator) reached the threshold"
        }
        // §9.2：滚轮每个事件最多走一层；同一叠窗口内移动保持 depth
        if case .scrolled = step.event, abs(session.hoverDepth - step.previous.hoverDepth) > 1 {
            return "one scroll event moved \(step.previous.hoverDepth) → \(session.hoverDepth)"
        }
        if case .mouseMoved = step.event, step.previous.phase == .hovering, session.phase == .hovering,
            session.hoverCandidates == step.previous.hoverCandidates, session.hoverDepth != step.previous.hoverDepth
        {
            return "moving within the same stack changed depth"
        }
        switch session.phase {
        case .hovering:
            let expected = WindowHitTester.candidates(at: session.cursor, in: step.topology)
            if session.hoverCandidates != expected {
                return "hover candidates are stale for cursor \(session.cursor)"
            }
            if expected.isEmpty {
                return session.hoverDepth == 0 && session.hover == nil
                    ? nil : "no candidates but depth \(session.hoverDepth), hover \(String(describing: session.hover))"
            }
            guard (0..<expected.count).contains(session.hoverDepth) else {
                return "depth \(session.hoverDepth) outside 0..<\(expected.count)"
            }
            return session.hover == expected[session.hoverDepth] ? nil : "hover is not candidates[depth]"
        case .selecting:
            let upper = max(session.hoverCandidates.count - 1, 0)
            return (0...upper).contains(session.hoverDepth) ? nil : "depth \(session.hoverDepth) outside 0...\(upper)"
        case .adjusting, .annotating, .editingText:
            let clean =
                session.hoverDepth == 0 && session.hoverCandidates.isEmpty && session.scrollAccumulator == 0
            return clean ? nil : "hover state not cleared in \(session.phase)"
        }
    }

    static func selectedAnnotation(_ step: FuzzStep) -> String? {
        guard let id = step.session.selectedAnnotation,
            step.documentChanged || id != step.previous.selectedAnnotation
        else { return nil }
        return step.session.document.annotation(id: id) == nil ? "selected id \(id.rawValue) not in document" : nil
    }

    static func numbering(_ step: FuzzStep) -> String? {
        guard step.documentChanged else { return nil }
        let document = step.session.document
        let numbers = document.annotations.filter { $0.tool == .number }
        for (index, annotation) in numbers.enumerated() where document.numberLabel(for: annotation.id) != index + 1 {
            return "number #\(index) labelled \(String(describing: document.numberLabel(for: annotation.id)))"
        }
        let labelled = document.annotations.first { $0.tool != .number && document.numberLabel(for: $0.id) != nil }
        if let other = labelled {
            return "non-number \(other.tool) has a number label"
        }
        if document.nextNumber != numbers.count + 1 {
            return "nextNumber \(document.nextNumber) != \(numbers.count + 1)"
        }
        guard case .mouseDown = step.event else { return nil }
        let before = Set(step.previous.document.annotations.map(\.id))
        let placed = numbers.filter { !before.contains($0.id) }
        let expectedLabel = step.previous.document.nextNumber
        if let annotation = placed.first, document.numberLabel(for: annotation.id) != expectedLabel {
            return "placed number labelled \(String(describing: document.numberLabel(for: annotation.id)))"
        }
        return nil
    }

    static func uniqueIDs(_ step: FuzzStep) -> String? {
        let drawing: Annotation?
        if case .drawing(let annotation) = step.session.drag {
            drawing = annotation
        } else {
            drawing = nil
        }
        guard step.documentChanged || drawing != nil else { return nil }
        let ids = step.session.document.annotations.map(\.id)
        if Set(ids).count != ids.count {
            return "duplicate annotation ids"
        }
        if let drawing, ids.contains(drawing.id) {
            return "annotation being drawn is already in the document"
        }
        return nil
    }

    static func undoRedo(_ step: FuzzStep) -> String? {
        let session = step.session
        let previous = step.previous
        let document = session.document
        if step.documentChanged {
            if document.canUndo && document.undone().redone() != document {
                return "document undo → redo is not identity"
            }
            if document.canRedo && document.redone().undone() != document {
                return "document redo → undo is not identity"
            }
        }
        guard isSelectionPhase(session.phase), !session.isPointerBusy else { return nil }
        // reducer 的撤销只取决于文档、阶段、鼠标是否空闲与选中标注；都没变时结果与上一步检查的相同
        let unchanged =
            !step.documentChanged && previous.phase == session.phase && !previous.isPointerBusy
            && previous.selectedAnnotation == session.selectedAnnotation
        guard !unchanged else { return nil }
        let undone = ScreenshotReducer.reduce(session, event: .command(.undo), topology: step.topology)
        guard undone.session.document != document else { return nil }
        if let id = undone.session.selectedAnnotation, undone.session.document.annotation(id: id) == nil {
            return "undo left a dangling selected annotation"
        }
        guard undone.session.document.canRedo else { return "undo changed the document but canRedo is false" }
        let redone = ScreenshotReducer.reduce(undone.session, event: .command(.redo), topology: step.topology)
        return redone.session.document == document ? nil : "reducer undo → redo did not restore the document"
    }

    static func dragNeedsPress(_ step: FuzzStep) -> String? {
        step.session.drag != .none && step.session.press == nil ? "drag \(step.session.drag) without press" : nil
    }

    static func spaceTap(_ step: FuzzStep) -> String? {
        let session = step.session
        guard session.isSpaceTapPending else { return nil }
        let valid = session.phase == .hovering && session.press == nil && session.modifiers.contains(.space)
        return valid ? nil : "space tap pending in \(session.phase), press \(session.press != nil)"
    }

    static func modifiers(_ step: FuzzStep) -> String? {
        let session = step.session
        if session.modifiers != step.expectedModifiers {
            return "modifiers \(session.modifiers.rawValue) != sent \(step.expectedModifiers.rawValue)"
        }
        let format: ColorFormat = session.modifiers.contains(.shift) ? .rgb : .hex
        return session.colorFormat == format ? nil : "colorFormat \(session.colorFormat) with modifiers"
    }
}
