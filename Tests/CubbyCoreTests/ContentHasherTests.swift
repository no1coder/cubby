import Foundation
import Testing
@testable import CubbyCore

@Suite("ContentHasher 内容指纹")
struct ContentHasherTests {
    @Test("相同内容得到相同哈希")
    func sameContentSameHash() {
        #expect(ContentHasher.hash(text: "hello") == ContentHasher.hash(text: "hello"))
        #expect(ContentHasher.hash(imageData: Data([1, 2, 3])) == ContentHasher.hash(imageData: Data([1, 2, 3])))
        #expect(ContentHasher.hash(filePaths: ["/a", "/b"]) == ContentHasher.hash(filePaths: ["/a", "/b"]))
    }

    @Test("不同内容得到不同哈希")
    func differentContentDifferentHash() {
        #expect(ContentHasher.hash(text: "hello") != ContentHasher.hash(text: "hello "))
        #expect(ContentHasher.hash(text: "a") != ContentHasher.hash(text: "A"))
        #expect(ContentHasher.hash(filePaths: ["/a"]) != ContentHasher.hash(filePaths: ["/b"]))
    }

    @Test("不同类型的相同字节不冲突")
    func typePrefixesAvoidCollision() {
        let raw = "/tmp/report.pdf"
        let text = ContentHasher.hash(text: raw)
        let files = ContentHasher.hash(filePaths: [raw])
        let image = ContentHasher.hash(imageData: Data(raw.utf8))
        #expect(Set([text, files, image]).count == 3)
        #expect(text.hasPrefix("text:"))
        #expect(files.hasPrefix("files:"))
        #expect(image.hasPrefix("image:"))
    }

    @Test("sha256 输出与已知向量一致（小写十六进制）")
    func knownVectors() {
        #expect(
            ContentHasher.sha256(Data())
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        #expect(
            ContentHasher.hash(text: "abc")
                == "text:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test("Unicode 与 emoji 文本可稳定哈希")
    func unicodeText() {
        let value = "剪贴板 📋 café"
        let hash = ContentHasher.hash(text: value)
        #expect(hash == ContentHasher.hash(text: value))
        #expect(hash.dropFirst("text:".count).count == 64)
        #expect(hash.dropFirst("text:".count).allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("hash(imageDigest:) 与 hash(imageData:) 对同一数据结果一致")
    func imageDigestMatchesImageData() {
        let data = Data("png-bytes".utf8)
        let digest = ContentHasher.sha256(data)
        #expect(ContentHasher.hash(imageDigest: digest) == ContentHasher.hash(imageData: data))
        #expect(ContentHasher.hash(imageDigest: digest) == "image:" + digest)
    }

    @Test("hash(imageDigest:) 原样拼接前缀，不再次计算哈希")
    func imageDigestIsNotRehashed() {
        #expect(ContentHasher.hash(imageDigest: "abc") == "image:abc")
        #expect(ContentHasher.hash(imageDigest: "") == "image:")
    }
}
