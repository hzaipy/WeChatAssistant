// swift-tools-version:6.0
// WeChatAssistant Package.swift - 用于 CLI 工具的 SPM 构建

import PackageDescription

let package = Package(
    name: "WeChatAssistant",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "wechat-assistant",
            targets: ["WeChatAssistantInstaller"]
        ),
        .library(
            name: "WeChatAssistant",
            type: .dynamic,
            targets: ["WeChatAssistant"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.0")
    ],
    targets: [
        .executableTarget(
            name: "WeChatAssistantInstaller",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/WeChatAssistantInstaller"
        ),
        .target(
            name: "WeChatAssistant",
            path: "Sources/WeChatAssistant",
            sources: ["main.m"]
        )
    ]
)
