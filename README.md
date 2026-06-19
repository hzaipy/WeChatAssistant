# 微信助手 WeChatAssistant

macOS 微信增强助手，支持消息防撤回、退群监控、主题更换等功能。

## 系统要求

- **Mac**: Apple Silicon (M1/M2/M3/M4)
- **系统**: macOS 12 (Monterey) 或更高版本
- **微信**: 4.1.x 系列（官网 DMG 版本）

> ⚠️ 不支持 Intel Mac，不支持微信 3.x 版本

## 功能

- ✅ **消息防撤回** - 拦截撤回消息，保留聊天记录
- ✅ **退群监控** - 实时监控群成员退出并推送通知
- ✅ **主题更换** - 内置多套主题，支持全局配色替换
- ✅ **阻止自动更新** - 防止微信自动更新覆盖插件
- ✅ **偏好设置面板** - 图形化管理所有功能

## 安装

### 方式一：从源码构建（推荐）

```bash
git clone https://github.com/wechat-assistant/wechat-assistant.git
cd wechat-assistant
make all
sudo bash Scripts/install.sh
```

### 方式二：Homebrew（即将推出）

```bash
brew install wechat-assistant/tap/wechat-assistant
wechat-assistant install
```

## 使用

安装完成后重启微信，菜单栏将出现「微信助手」菜单：

- **偏好设置** - 打开设置面板
- **消息防撤回** - 开关防撤回功能
- **退群监控** - 开关退群监控
- **主题更换** - 开关主题功能
- **主题** - 选择预设主题
- **撤回消息历史** - 查看所有被撤回的消息

## 卸载

```bash
sudo bash Scripts/uninstall.sh
```

或使用 CLI 工具：

```bash
wechat-assistant uninstall
```

## 项目结构

```
WeChatAssistant/
├── Sources/
│   ├── WeChatAssistant/       # 动态库源码
│   │   ├── Hook/              # Hook 模块
│   │   ├── Managers/          # 业务逻辑
│   │   ├── Models/            # 数据模型
│   │   ├── Views/             # UI 组件
│   │   ├── WindowControllers/ # 窗口控制器
│   │   └── Utils/             # 工具类
│   └── WeChatAssistantInstaller/ # CLI 安装工具
├── Resources/Themes/           # 主题资源
├── Scripts/                    # 安装/卸载脚本
└── Makefile                    # 构建系统
```

## 技术架构

```
┌─────────────────────────────────┐
│       UI Layer (AppKit)         │  ← 设置面板、通知
├─────────────────────────────────┤
│    Business Logic (Managers)    │  ← 功能管理
├─────────────────────────────────┤
│       Hook Layer                │  ← Method Swizzling
├─────────────────────────────────┤
│   WeChat Runtime (4.1.x QT)     │  ← 微信原生方法
└─────────────────────────────────┘
```

### 微信 4.1.x 适配策略

微信 4.x 采用 QT + C++ 重构，丧失了部分 OC Runtime 特性。我们采用混合策略：

1. **Method Swizzling** - 对有 Runtime 暴露的方法进行 Hook
2. **动态类/方法发现** - 遍历所有微信类，搜索目标方法
3. **二进制补丁** - 对关键函数直接修改 ARM64 汇编指令（参考 WeChatTweak）

## 常见问题

### Q: 微信更新后插件失效怎么办？
A: 微信更新后需要重新安装。我们正在开发自动检测和重新注入功能。

### Q: 支持 App Store 版本的微信吗？
A: 目前仅支持官网 DMG 版本。App Store 版本有额外的沙盒限制。

### Q: 插件是否安全？
A: 本插件仅修改微信客户端的本地行为，不会上传任何数据。源码完全开源可审计。

### Q: 会不会被微信封号？
A: 本插件在本地层面工作，不涉及服务端交互。但任何第三方修改都有理论上的风险，请自行评估。

## 开发

```bash
# 构建
make all

# 仅构建 dylib
make dylib

# 仅构建 CLI
make cli

# 清理
make clean
```

## 致谢

本项目参考了以下优秀开源项目：

- [WeChatTweak](https://github.com/sunnyyoung/WeChatTweak) - 微信防撤回与多开
- [WeChatPlugin-MacOS](https://github.com/TKkk-iOSer/WeChatPlugin-MacOS) - 微信功能插件
- [WeChatExtension-ForMac](https://github.com/MustangYM/WeChatExtension-ForMac) - Mac 微信功能拓展

## License

AGPL-3.0
