#!/bin/bash
# ============================================================
# WeChatAssistant 安装脚本
# 将 WeChatAssistant.dylib 注入到微信 macOS 客户端
# 仅支持 Apple Silicon (arm64) + 微信 4.1.x
# ============================================================

set -e

WECHAT_PATH="/Applications/WeChat.app"
DYLIB_NAME="WeChatAssistant.dylib"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/../.build/products"
DYLIB_PATH="${BUILD_DIR}/${DYLIB_NAME}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  WeChatAssistant 安装脚本${NC}"
echo -e "${GREEN}  目标: Apple Silicon (arm64)${NC}"
echo -e "${GREEN}  微信版本: 4.1.x${NC}"
echo -e "${GREEN}========================================${NC}"

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}⚠️  需要 sudo 权限来修改微信应用${NC}"
    echo "请使用: sudo bash install.sh"
    exit 1
fi

# 检查微信是否安装
if [ ! -d "$WECHAT_PATH" ]; then
    echo -e "${RED}❌ 未找到微信应用: ${WECHAT_PATH}${NC}"
    echo "请确认微信已安装到 /Applications 目录"
    exit 1
fi

# 检查芯片架构
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    echo -e "${RED}❌ 此安装脚本仅支持 Apple Silicon (M 芯片) Mac${NC}"
    echo "当前架构: $ARCH"
    exit 1
fi
echo -e "${GREEN}✅ 芯片架构: Apple Silicon (arm64)${NC}"

# 检查微信版本
WECHAT_VERSION=$(defaults read /Applications/WeChat.app/Contents/Info.plist CFBundleVersion 2>/dev/null || echo "unknown")
echo -e "${GREEN}📦 微信版本: ${WECHAT_VERSION}${NC}"

# 检查微信架构
WECHAT_ARCH=$(lipo -archs "${WECHAT_PATH}/Contents/MacOS/WeChat" 2>/dev/null || echo "unknown")
echo -e "${GREEN}🔧 微信架构: ${WECHAT_ARCH}${NC}"

# 检查 dylib 是否存在
if [ ! -f "$DYLIB_PATH" ]; then
    echo -e "${YELLOW}⚠️  未找到编译好的 dylib，正在构建...${NC}"
    cd "${SCRIPT_DIR}/.."
    make dylib
    if [ ! -f "$DYLIB_PATH" ]; then
        echo -e "${RED}❌ 构建失败${NC}"
        exit 1
    fi
fi

# 检查 dylib 架构
DYLIB_ARCH=$(lipo -archs "$DYLIB_PATH" 2>/dev/null || echo "unknown")
echo -e "${GREEN}🔧 Dylib 架构: ${DYLIB_ARCH}${NC}"

# 检查是否已安装
WECHAT_BINARY="${WECHAT_PATH}/Contents/MacOS/WeChat"
if otool -L "$WECHAT_BINARY" 2>/dev/null | grep -q "$DYLIB_NAME"; then
    echo -e "${YELLOW}⚠️  检测到 WeChatAssistant 已安装${NC}"
    echo "是否重新安装? (y/n)"
    read -r REPLY
    if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
        echo "取消安装"
        exit 0
    fi
    # 先卸载
    echo "正在卸载旧版本..."
    bash "${SCRIPT_DIR}/uninstall.sh"
fi

# 备份原始微信
BACKUP_DIR="${WECHAT_PATH}/Contents/MacOS/WeChat.backup"
if [ ! -f "$BACKUP_DIR" ]; then
    echo -e "${GREEN}💾 备份原始微信二进制...${NC}"
    cp "$WECHAT_BINARY" "$BACKUP_DIR"
    echo -e "${GREEN}✅ 备份完成: ${BACKUP_DIR}${NC}"
fi

# 检查 insert_dylib 工具
INSERT_DYLIB=$(which insert_dylib 2>/dev/null || echo "")
if [ -z "$INSERT_DYLIB" ]; then
    echo -e "${YELLOW}⚠️  未找到 insert_dylib，正在安装...${NC}"
    # 尝试用 brew 安装
    if command -v brew &>/dev/null; then
        brew install insert_dylib 2>/dev/null || true
    fi
    INSERT_DYLIB=$(which insert_dylib 2>/dev/null || echo "")
    if [ -z "$INSERT_DYLIB" ]; then
        echo -e "${RED}❌ 无法安装 insert_dylib${NC}"
        echo "请手动安装: brew install insert_dylib"
        exit 1
    fi
fi

# 复制 dylib 到微信 Frameworks 目录
echo -e "${GREEN}📋 复制动态库...${NC}"
FRAMEWORKS_DIR="${WECHAT_PATH}/Contents/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
cp "$DYLIB_PATH" "${FRAMEWORKS_DIR}/${DYLIB_NAME}"
echo -e "${GREEN}✅ 已复制到: ${FRAMEWORKS_DIR}/${DYLIB_NAME}${NC}"

# 注入 dylib 加载指令
echo -e "${GREEN}💉 注入动态库加载指令...${NC}"
INSERT_PATH="@executable_path/../Frameworks/${DYLIB_NAME}"
"$INSERT_DYLIB" "$INSERT_PATH" "$WECHAT_BINARY" --inplace --all-yes 2>/dev/null || {
    echo -e "${YELLOW}⚠️  insert_dylib 注入失败，尝试备用方案...${NC}"
    # 备用：使用 optool
    if command -v optool &>/dev/null; then
        optool install -p "$INSERT_PATH" -t "$WECHAT_BINARY"
    else
        echo -e "${RED}❌ 注入失败${NC}"
        exit 1
    fi
}
echo -e "${GREEN}✅ 注入完成${NC}"

# 重新签名
echo -e "${GREEN}🔐 重新签名...${NC}"
codesign --force --deep --sign - "$WECHAT_PATH" 2>/dev/null || {
    echo -e "${YELLOW}⚠️  签名失败，尝试 ad-hoc 签名...${NC}"
    codesign --force --sign - "$WECHAT_PATH" 2>/dev/null || {
        echo -e "${YELLOW}⚠️  签名可能不完整，但不影响使用${NC}"
    }
}
echo -e "${GREEN}✅ 签名完成${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✅ WeChatAssistant 安装完成!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "请重启微信以加载插件"
echo ""
echo "如果微信无法启动，请运行卸载脚本："
echo "  sudo bash ${SCRIPT_DIR}/uninstall.sh"
echo ""
