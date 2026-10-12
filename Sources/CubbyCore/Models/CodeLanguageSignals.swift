import Foundation

/// 去掉首尾空白的一行，附带大写形式（SQL 关键字不区分大小写）
struct CodeLine: Sendable {
    let text: String
    let upper: String

    init(_ text: String) {
        self.text = text
        self.upper = text.uppercased()
    }
}

/// 一条语言特征：某一行命中即为该语言加 `weight` 分
struct CodeLanguageSignal: Sendable {
    let weight: Int
    let matches: @Sendable (CodeLine) -> Bool

    /// 行首是其中任一前缀（区分大小写）
    static func prefix(_ prefixes: [String], _ weight: Int) -> Self {
        Self(weight: weight) { line in prefixes.contains { line.text.hasPrefix($0) } }
    }

    /// 行内包含其中任一片段（区分大小写）
    static func contains(_ needles: [String], _ weight: Int) -> Self {
        Self(weight: weight) { line in needles.contains { line.text.contains($0) } }
    }

    /// 行首是其中任一前缀（不区分大小写，前缀须写成大写）
    static func upperPrefix(_ prefixes: [String], _ weight: Int) -> Self {
        Self(weight: weight) { line in prefixes.contains { line.upper.hasPrefix($0) } }
    }

    /// 行内包含其中任一片段（不区分大小写，片段须写成大写）
    static func upperContains(_ needles: [String], _ weight: Int) -> Self {
        Self(weight: weight) { line in needles.contains { line.upper.contains($0) } }
    }

    static func custom(_ weight: Int, _ predicate: @escaping @Sendable (CodeLine) -> Bool) -> Self {
        Self(weight: weight, matches: predicate)
    }
}

/// 各语言的特征表。权重按区分度给：只有该语言才有的写法 3～6 分，几种语言共有的写法 1～2 分
enum CodeLanguageSignals {
    static let all: [(language: CodeLanguage, signals: [CodeLanguageSignal])] = [
        (.swift, swift), (.javascript, javascript), (.python, python), (.go, go), (.rust, rust),
        (.shell, shell), (.html, html), (.css, css), (.sql, sql),
    ]

    static let swift: [CodeLanguageSignal] = [
        .prefix(["import SwiftUI", "import Foundation", "import UIKit", "import AppKit", "import Combine"], 4),
        .contains(["some View", "@State", "@Published", "@MainActor", "@Binding", "@Observable", "@Environment"], 4),
        .contains(["@main", "@objc", "@escaping", "@ViewBuilder"], 3),
        .contains(["VStack", "HStack", "ZStack", "Spacer()", ".padding(", ".frame("], 3),
        // SwiftUI 的修饰符链：Text("…") 换行接 .font(.headline)、.foregroundStyle(.purple)
        .contains(["Text(\"", ".font(.", ".foregroundStyle(", ".foregroundColor(", ".background(."], 3),
        .prefix(["guard ", "extension ", "protocol "], 3),
        .contains(["(_ ", "if let ", "guard let ", "?? "], 2),
        .contains(["\\.", "\\("], 2),
        .contains(["private var ", "private let ", "private func ", "public func ", "static func "], 2),
        .prefix(["func "], 2),
        .prefix(["let ", "var "], 1),
        .contains(["(.", ") -> "], 1),
    ]

    static let javascript: [CodeLanguageSignal] = [
        .contains(["console.", "document.", "window.", "require(", "module.exports"], 4),
        .prefix(
            [
                "export default", "export const", "export function", "export class", "export interface",
                "export type", "export {",
            ], 4),
        .custom(4) { $0.text.hasPrefix("import ") && ($0.text.contains(" from '") || $0.text.contains(" from \"")) },
        .custom(6) { $0.text.hasPrefix("#!") && $0.text.contains("node") },
        .prefix(["function ", "async function "], 3),
        .prefix(["const "], 3),
        .contains([" === ", " !== "], 3),
        .contains([": string", ": number", ": boolean", ": any", ": void"], 2),
        .contains(["=>", "function("], 2),
        .prefix(["interface "], 2),
        .contains(["${"], 1),
        .custom(1) { $0.text.hasSuffix(";") },
        .custom(1) { ($0.text.hasPrefix("let ") || $0.text.hasPrefix("var ")) && $0.text.hasSuffix(";") },
    ]

    static let python: [CodeLanguageSignal] = [
        .contains(["__init__", "__name__", "__main__"], 4),
        .prefix(["elif "], 4),
        .custom(4) { $0.text.hasPrefix("from ") && $0.text.contains(" import ") },
        .custom(6) { $0.text.hasPrefix("#!") && $0.text.contains("python") },
        .prefix(["def ", "except"], 3),
        .contains(["(self"], 3),
        .custom(1, endsPythonBlock),
        .custom(2, isPlainImport),
        .contains(["lambda "], 2),
        .contains(["self.", " None", " True", " False", "f\"", "f'", "print("], 1),
    ]

    static let go: [CodeLanguageSignal] = [
        .prefix(["package ", "func ("], 4),
        .contains(["fmt.", "err != nil"], 4),
        .custom(4) {
            $0.text.hasPrefix("type ") && ($0.text.hasSuffix(" struct {") || $0.text.hasSuffix(" interface {"))
        },
        .prefix(["import (", "import \""], 3),
        .contains([" := "], 3),
        .prefix(["go func", "defer "], 2),
        .contains(["chan "], 2),
        .prefix(["func "], 2),
    ]

    static let rust: [CodeLanguageSignal] = [
        .contains(["let mut ", "println!", "format!", "vec!", "panic!", "assert_eq!", "macro_rules!"], 4),
        .prefix(["impl ", "impl<", "#["], 4),
        .custom(4) { $0.text.hasPrefix("use ") && $0.text.contains("::") },
        .custom(3, isTypedConstant),
        .prefix(["fn ", "pub fn ", "async fn ", "pub(crate) fn ", "mod ", "pub struct ", "pub enum ", "trait "], 3),
        .contains(["&mut ", "&self", "&str", "Option<", "Result<", "Vec<", ".unwrap()", "Box<"], 2),
        .contains([": u8", ": u32", ": u64", ": i32", ": i64", ": usize", ": f32", ": f64"], 2),
        .prefix(["pub "], 1),
        .contains(["::", ") -> "], 1),
    ]

    /// `const MAX: u32 = 10;`：带类型标注的常量（TS 的 `const x: number` 另有类型特征加分）
    private static let isTypedConstant: @Sendable (CodeLine) -> Bool = { line in
        guard line.text.hasPrefix("const ") || line.text.hasPrefix("static "),
            let colon = line.text.firstIndex(of: ":"), let equals = line.text.firstIndex(of: "=")
        else { return false }
        return colon < equals
    }

    /// Python 的块语句：以块关键字开头、以冒号结尾
    private static let pythonBlockKeywords = [
        "def ", "class ", "if ", "elif ", "else", "for ", "while ", "try", "except", "with ", "finally",
    ]

    private static let endsPythonBlock: @Sendable (CodeLine) -> Bool = { line in
        line.text.hasSuffix(":") && pythonBlockKeywords.contains { line.text.hasPrefix($0) }
    }

    /// `import os`、`import numpy as np`：import 后只有模块名
    private static let isPlainImport: @Sendable (CodeLine) -> Bool = { line in
        guard line.text.hasPrefix("import ") else { return false }
        return line.text.dropFirst(7).allSatisfy { $0.isLetter || $0.isNumber || " _.,".contains($0) }
    }
}
