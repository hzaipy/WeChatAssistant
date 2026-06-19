#!/bin/bash
# ============================================================
# WeChatAssistant 卸载脚本
# 从微信中移除 dylib 并恢复备份
# ============================================================

set -e

WECHAT_PATH="/Applications/WeChat.app"
DYLIB_NAME="WeChatAssistant.dylib"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  WeChatAssistant 卸载脚本${NC}"
echo -e "${GREEN}========================================${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}⚠️  需要 sudo 权限${NC}"
    echo "请使用: sudo bash uninstall.sh"
    exit 1
fi

WECHAT_BINARY="${WECHAT_PATH}/Contents/MacOS/WeChat"
BACKUP="${WECHAT_PATH}/Contents/MacOS/WeChat.backup"
FRAMEWORKS_DYLIB="${WECHAT_PATH}/Contents/Frameworks/${DYLIB_NAME}"

# 恢复备份
if [ -f "$BACKUP" ]; then
    echo -e "${GREEN}🔄 恢复原始微信二进制...${NC}"
    cp "$BACKUP" "$WECHAT_BINARY"
    rm "$BACKUP"
    echo -e "${GREEN}✅ 已恢复${NC}"
else
    echo -e "${YELLOW}⚠️  未找到备份文件${NC}"
fi

# 移除 dylib
if [ -f "$FRAMEWORKS_DYLIB" ]; then
    echo -e "${GREEN}🗑 移除动态库...${NC}"
    rm "$FRAMEWORKS_DYLIB"
    echo -e "${GREEN}✅ 已移除${NC}"
fi

# 重新签名
echo -e "${GREEN}🔐 重新签名...${NC}"
codesign --force --deep --sign - "$WECHAT_PATH" 2>/dev/null || true
echo -e "${GREEN}✅ 签名完成${NC}"

echo ""
echo -e "${GREEN}✅ WeChatAssistant 已卸载${NC}"
echo "请重启微信"
