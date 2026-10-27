// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "YiKey",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "YiKeyCore"),
        // Homebrew librime（brew install librime），通过 pkg-config 找头文件和库
        .systemLibrary(name: "CRime", pkgConfig: "rime", providers: [.brew(["librime"])]),
        .executableTarget(
            name: "YiKey",
            dependencies: ["YiKeyCore", "CRime"],
            // IMKit / Translation 的 SDK 类型缺少 Sendable 标注，严格并发检查会误报
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "YiKeyCoreTests",
            dependencies: ["YiKeyCore"]
        ),
    ]
)
