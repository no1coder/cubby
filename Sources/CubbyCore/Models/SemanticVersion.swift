import Foundation

/// 语义化版本号（SemVer 2.0）：比较规则遵循官方优先级，预发布版本低于同号正式版本
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// 预发布标识，例如 1.2.0-beta.3 → ["beta", "3"]
    public let prerelease: [String]

    public init(major: Int, minor: Int, patch: Int, prerelease: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// 解析 "1.2.3"、"v1.2.3"、"1.2"（补 0）、"1.2.3-beta.1"、"1.2.3+build.5"（忽略构建元数据）
    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let withoutBuild = text.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let parts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = parts.first.map { $0.split(separator: ".", omittingEmptySubsequences: false) } ?? []
        guard (2...3).contains(core.count),
            let major = Self.number(core[0]),
            let minor = Self.number(core[1])
        else { return nil }
        let patch = core.count == 3 ? Self.number(core[2]) : 0
        guard let patch else { return nil }

        let prerelease =
            parts.count == 2 ? parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
        guard prerelease.allSatisfy(Self.isValidIdentifier) else { return nil }
        self.init(major: major, minor: minor, patch: patch, prerelease: prerelease)
    }

    public var isPrerelease: Bool {
        !prerelease.isEmpty
    }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : core + "-" + prerelease.joined(separator: ".")
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let lhsCore = [lhs.major, lhs.minor, lhs.patch]
        let rhsCore = [rhs.major, rhs.minor, rhs.patch]
        if lhsCore != rhsCore { return lhsCore.lexicographicallyPrecedes(rhsCore) }
        // 核心版本相同：有预发布标识的更低
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true), (true, false): return false
        case (false, true): return true
        case (false, false): return precedes(lhs.prerelease, rhs.prerelease)
        }
    }

    /// 预发布标识逐个比较：数字按数值、数字低于字母数字、字母数字按 ASCII；前缀相同时较短者更低
    private static func precedes(_ lhs: [String], _ rhs: [String]) -> Bool {
        for (left, right) in zip(lhs, rhs) where left != right {
            switch (Int(left), Int(right)) {
            case (let l?, let r?): return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return left < right
            }
        }
        return lhs.count < rhs.count
    }

    private static func number(_ part: Substring) -> Int? {
        guard !part.isEmpty, part.allSatisfy(\.isASCIIDigit),
            part == "0" || !part.hasPrefix("0")
        else { return nil }
        return Int(part)
    }

    private static func isValidIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.allSatisfy { $0.isASCIIDigit || $0.isASCIILetter || $0 == "-" }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isASCIILetter: Bool { isASCII && isLetter }
}
