import Foundation

/// 跨界面复用的产品文案：引导页与关于页必须保持同一口径
enum AppCopy {
    /// 产品口号
    static var tagline: String {
        String(localized: "Everything you copy, one shortcut away.", comment: "Product tagline")
    }
}
