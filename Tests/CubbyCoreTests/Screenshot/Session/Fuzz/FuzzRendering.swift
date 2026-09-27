import CoreGraphics
@testable import CubbyCore

/// 把失败序列渲染成可以直接粘贴进回归测试的 Swift 代码
enum FuzzRendering {
    static func report(_ failure: ReducerFuzzRunner.Failure) -> String {
        let trace = failure.trace
        let physical = failure.nonPhysicalEvents == 0 ? "physical" : "\(failure.nonPhysicalEvents) non-physical"
        let lines = trace.events.map { "    " + swift($0) + "," }
        return """
            seed \(failure.seed): \(failure.violation.invariant.rawValue) - \(failure.violation.detail)
            topology FuzzTopologies.all[\(trace.topologyIndex)], start \(swift(trace.start)), \
            \(trace.events.count) events (\(physical)):
            \(lines.joined(separator: "\n"))
            """
    }

    static func swift(_ start: FuzzStart) -> String {
        switch start {
        case .initial(let cursor): ".initial(cursor: \(swift(cursor)))"
        case .scenario(let name): ".scenario(\(swift(name)))"
        }
    }

    static func swift(_ event: ScreenshotEvent) -> String {
        switch event {
        case .mouseMoved(let point): ".mouseMoved(\(swift(point)))"
        case .mouseDown(let point, let count): ".mouseDown(\(swift(point)), clickCount: \(count))"
        case .mouseDragged(let point): ".mouseDragged(\(swift(point)))"
        case .mouseUp(let point): ".mouseUp(\(swift(point)))"
        case .rightMouseDown(let point): ".rightMouseDown(\(swift(point)))"
        case .modifiersChanged(let modifiers): ".modifiersChanged(\(swift(modifiers)))"
        case .command(let command): ".command(\(swift(command)))"
        case .styleChanged(let style):
            ".styleChanged(AnnotationStyle(color: .\(style.color), weight: .\(style.weight)))"
        case .textChanged(let text): ".textChanged(\(swift(text)))"
        case .textCommitted(let text): ".textCommitted(\(text.map(swift) ?? "nil"))"
        case .toolbarAction(let outcome): ".toolbarAction(\(swift(outcome)))"
        case .scrolled(let delta): ".scrolled(deltaY: \(delta))"
        case .translation(let translation): ".translation(\(FuzzTranslation.swift(translation)))"
        }
    }

    static func swift(_ point: CGPoint) -> String {
        "CGPoint(x: \(point.x), y: \(point.y))"
    }

    static func swift(_ rect: CGRect) -> String {
        "CGRect(x: \(rect.minX), y: \(rect.minY), width: \(rect.width), height: \(rect.height))"
    }

    static func swift(_ modifiers: KeyModifiers) -> String {
        let names: [(KeyModifiers, String)] = [
            (.shift, ".shift"), (.option, ".option"), (.command, ".command"), (.space, ".space"),
        ]
        return "[" + names.filter { modifiers.contains($0.0) }.map(\.1).joined(separator: ", ") + "]"
    }

    static func swift(_ command: ScreenshotCommand) -> String {
        switch command {
        case .selectTool(let tool): ".selectTool(.\(tool.rawValue))"
        case .nudge(let direction, let large): ".nudge(.\(direction), large: \(large))"
        case .cycleHover(let forward): ".cycleHover(forward: \(forward))"
        case .selectColor(let color): ".selectColor(.\(color.rawValue))"
        case .adjustWeight(let heavier): ".adjustWeight(heavier: \(heavier))"
        default: ".\(command)"
        }
    }

    static func swift(_ outcome: ScreenshotOutcome) -> String {
        switch outcome {
        case .copyColor(let text): ".copyColor(\(swift(text)))"
        case .captureWindow(let id, let shadow): ".captureWindow(windowID: \(id), includeShadow: \(shadow))"
        default: ".\(outcome)"
        }
    }

    /// 字符串字面量：非 ASCII 一律写成 \u{…}，保证测试源码不出现汉字
    static func swift(_ text: String) -> String {
        let body = text.unicodeScalars.map { scalar -> String in
            switch scalar {
            case "\"": return "\\\""
            case "\\": return "\\\\"
            case "\n": return "\\n"
            case "\t": return "\\t"
            default:
                return scalar.isASCII && scalar.value >= 0x20
                    ? String(scalar) : "\\u{" + String(scalar.value, radix: 16, uppercase: true) + "}"
            }
        }
        return "\"" + body.joined() + "\""
    }

    // MARK: - 坐标化简

    /// 更易读的等价候选：坐标取整、取十的倍数
    static func simplifications(of event: ScreenshotEvent) -> [ScreenshotEvent] {
        guard let point = location(of: event) else { return [] }
        let candidates = [
            CGPoint(x: (point.x / 10).rounded() * 10, y: (point.y / 10).rounded() * 10),
            CGPoint(x: point.x.rounded(), y: point.y.rounded()),
            CGPoint(x: (point.x * 4).rounded() / 4, y: (point.y * 4).rounded() / 4),
        ]
        return candidates.filter { $0 != point }.map { replacing(event, location: $0) }
    }

    private static func location(of event: ScreenshotEvent) -> CGPoint? {
        switch event {
        case .mouseMoved(let point), .mouseDown(let point, _), .mouseDragged(let point), .mouseUp(let point),
            .rightMouseDown(let point):
            point
        default:
            nil
        }
    }

    private static func replacing(_ event: ScreenshotEvent, location point: CGPoint) -> ScreenshotEvent {
        switch event {
        case .mouseMoved: .mouseMoved(point)
        case .mouseDown(_, let count): .mouseDown(point, clickCount: count)
        case .mouseDragged: .mouseDragged(point)
        case .mouseUp: .mouseUp(point)
        case .rightMouseDown: .rightMouseDown(point)
        default: event
        }
    }
}
