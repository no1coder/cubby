// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cubby",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        // 核心层：模型、历史记录逻辑、存储、剪贴板读写（可单元测试）
        .target(name: "CubbyCore"),
        // 应用层：菜单栏、全局热键、浮动面板、设置界面
        .executableTarget(
            name: "Cubby",
            dependencies: ["CubbyCore"]
        ),
        .testTarget(
            name: "CubbyCoreTests",
            dependencies: ["CubbyCore"]
        ),
    ]
)
