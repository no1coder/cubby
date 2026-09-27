import Testing
@testable import CubbyCore

@Suite("SemanticVersion 语义化版本")
struct SemanticVersionTests {
    @Test(
        "解析常见写法",
        arguments: [
            ("1.2.3", "1.2.3"),
            ("v1.2.3", "1.2.3"),
            ("V0.2.0", "0.2.0"),
            ("1.2", "1.2.0"),
            (" 1.2.3 ", "1.2.3"),
            ("1.2.3-beta.1", "1.2.3-beta.1"),
            ("1.2.3+build.5", "1.2.3"),
            ("1.2.3-rc.1+exp.sha.5114f85", "1.2.3-rc.1"),
        ])
    func parses(_ input: String, _ expected: String) throws {
        let version = try #require(SemanticVersion(input))
        #expect(version.description == expected)
    }

    @Test(
        "拒绝非法版本号",
        arguments: [
            "", "1", "1.2.3.4", "a.b.c", "1..3", "01.2.3", "1.2.03", "1.2.3-", "1.2.3-beta..1", "1.2.3-β", "-1.2.3",
        ])
    func rejects(_ input: String) {
        #expect(SemanticVersion(input) == nil)
    }

    @Test("核心版本按数值比较，而非字符串")
    func comparesNumerically() throws {
        let versions = try ["0.2.0", "0.10.0", "0.9.9", "1.0.0", "0.2.10", "0.2.2"].map {
            try #require(SemanticVersion($0))
        }
        #expect(versions.sorted().map(\.description) == ["0.2.0", "0.2.2", "0.2.10", "0.9.9", "0.10.0", "1.0.0"])
    }

    @Test("预发布版本低于同号正式版本，并按 SemVer 规则排序")
    func prereleasePrecedence() throws {
        // semver.org 官方示例顺序
        let ordered = [
            "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
            "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0",
        ]
        let versions = try ordered.map { try #require(SemanticVersion($0)) }
        #expect(versions.shuffled().sorted().map(\.description) == ordered)
        for (lower, higher) in zip(versions, versions.dropFirst()) {
            #expect(lower < higher)
        }
    }

    @Test("相等与预发布标记")
    func equalityAndPrereleaseFlag() throws {
        let tagged = try #require(SemanticVersion("v1.2.0"))
        let plain = try #require(SemanticVersion("1.2"))
        #expect(tagged == plain)
        #expect(!tagged.isPrerelease)
        #expect(try #require(SemanticVersion("1.2.0-beta")).isPrerelease)
        #expect(!(tagged < plain) && !(plain < tagged))
    }
}
