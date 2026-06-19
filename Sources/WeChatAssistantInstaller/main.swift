//
//  main.swift
//  WeChatAssistantInstaller
//
//  CLI 安装管理工具
//  用法: wechat-assistant <command>
//

import Foundation
import ArgumentParser

// MARK: - 主命令
@main
struct WeChatAssistantCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wechat-assistant",
        abstract: "macOS 微信助手 - 安装管理工具",
        discussion: """
        一款 macOS 微信增强助手，支持消息防撤回、退群监控、主题更换等功能。
        仅支持 Apple Silicon (M1/M2/M3/M4) + 微信 4.1.x 系列。

        项目地址: https://github.com/wechat-assistant
        """,
        version: "1.0.0",
        subcommands: [
            Install.self,
            Uninstall.self,
            Status.self,
            Themes.self,
            Patch.self
        ]
    )
}

// MARK: - 全局选项
struct GlobalOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "微信应用路径")
    var app: String = "/Applications/WeChat.app"
}

// MARK: - install 命令
struct Install: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "安装微信助手插件"
    )

    @Option(name: .shortAndLong, help: "微信应用路径")
    var app: String = "/Applications/WeChat.app"

    @Flag(name: .shortAndLong, help: "跳过签名验证")
    var skipSign: Bool = false

    mutating func run() async throws {
        print("🔧 WeChatAssistant 安装程序")
        print("==============================")

        // 检查系统
        let arch = try await runShell("uname -m").trimmingCharacters(in: .whitespacesAndNewlines)
        guard arch == "arm64" else {
            print("❌ 仅支持 Apple Silicon (M 芯片) Mac")
            print("   当前架构: \(arch)")
            throw ExitCode.failure
        }
        print("✅ 架构: Apple Silicon (arm64)")

        // 检查微信
        guard FileManager.default.fileExists(atPath: app) else {
            print("❌ 未找到微信: \(app)")
            throw ExitCode.failure
        }

        // 获取微信版本
        let plistPath = "\(app)/Contents/Info.plist"
        let version = try await runShell("/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' \(plistPath)")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        print("📦 微信版本: \(version)")

        // 检查版本兼容性
        print("🔍 检查版本兼容性...")
        let configURL = "https://raw.githubusercontent.com/wechat-assistant/wechat-assistant/main/config.json"
        // TODO: 下载并匹配 config.json

        print("""
        ╔══════════════════════════════════╗
        ║  请使用以下命令完成安装:       ║
        ║                                ║
        ║  sudo bash Scripts/install.sh  ║
        ║                                ║
        ╚══════════════════════════════════╝
        """)
    }
}

// MARK: - uninstall 命令
struct Uninstall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "卸载微信助手插件"
    )

    mutating func run() async throws {
        print("🗑 卸载 WeChatAssistant...")
        print("请运行: sudo bash Scripts/uninstall.sh")
    }
}

// MARK: - status 命令
struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "查看插件状态"
    )

    @Option(name: .shortAndLong, help: "微信应用路径")
    var app: String = "/Applications/WeChat.app"

    mutating func run() async throws {
        print("📊 WeChatAssistant 状态")
        print("======================")

        // 检查微信
        let wechatBinary = "\(app)/Contents/MacOS/WeChat"
        guard FileManager.default.fileExists(atPath: wechatBinary) else {
            print("❌ 未找到微信")
            throw ExitCode.failure
        }

        // 检查 dylib 注入状态
        let otoolOutput = try await runShell("otool -L \(wechatBinary) 2>/dev/null")
        if otoolOutput.contains("WeChatAssistant.dylib") {
            print("✅ WeChatAssistant 已安装")
        } else {
            print("❌ WeChatAssistant 未安装")
        }

        // 检查备份
        let backup = "\(app)/Contents/MacOS/WeChat.backup"
        if FileManager.default.fileExists(atPath: backup) {
            print("✅ 原始备份存在")
        } else {
            print("⚠️  原始备份不存在")
        }

        // 版本信息
        let plistPath = "\(app)/Contents/Info.plist"
        let version = try await runShell("/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' \(plistPath)")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        print("📦 微信版本: \(version)")
    }
}

// MARK: - themes 命令
struct Themes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "管理主题"
    )

    @Flag(name: .shortAndLong, help: "列出所有可用主题")
    var list: Bool = false

    @Option(name: .shortAndLong, help: "切换到指定主题")
    var switchTo: String?

    mutating func run() async throws {
        if list {
            print("🎨 可用主题:")
            print("  • Default  - 微信默认配色")
            print("  • Dark     - 深色暗黑主题")
            print("  • Minimal  - 极简黑白主题")
        } else if let theme = switchTo {
            print("🔄 切换到主题: \(theme)")
            print("请重启微信以应用主题")
        } else {
            print(Themes.helpMessage())
        }
    }
}

// MARK: - patch 命令
struct Patch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "对微信应用二进制补丁（仅限 arm64）"
    )

    @Option(name: .shortAndLong, help: "微信应用路径")
    var app: String = "/Applications/WeChat.app"

    @Option(name: .shortAndLong, help: "补丁配置文件路径或 URL")
    var config: String = "https://raw.githubusercontent.com/wechat-assistant/wechat-assistant/main/config.json"

    mutating func run() async throws {
        print("🔨 执行二进制补丁...")
        print("架构: arm64")
        print("目标: \(app)")
        print("配置: \(config)")

        let wechatBinary = "\(app)/Contents/MacOS/WeChat"
        guard FileManager.default.fileExists(atPath: wechatBinary) else {
            print("❌ 未找到微信二进制: \(wechatBinary)")
            throw ExitCode.failure
        }

        // 获取版本
        let plistPath = "\(app)/Contents/Info.plist"
        let version = try await runShell("/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' \(plistPath)")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        print("微信版本: \(version)")

        // 下载/加载配置
        print("加载补丁配置...")
        // TODO: 实现补丁逻辑
        print("补丁功能将在后续版本中实现")
    }
}

// MARK: - 辅助函数
func runShell(_ command: String) async throws -> String {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/bash")

    try task.run()
    task.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}
