import CryptoKit
import Foundation

/// 生成内容指纹；按类型加前缀，避免文本与文件路径等不同类型内容相互冲突
public enum ContentHasher {
    public static func hash(text: String) -> String {
        "text:" + sha256(Data(text.utf8))
    }

    public static func hash(imageData: Data) -> String {
        hash(imageDigest: sha256(imageData))
    }

    /// 已算好 SHA256 时直接复用，避免对大图重复计算
    public static func hash(imageDigest: String) -> String {
        "image:" + imageDigest
    }

    public static func hash(filePaths: [String]) -> String {
        "files:" + sha256(Data(filePaths.joined(separator: "\n").utf8))
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
