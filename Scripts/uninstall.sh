#!/bin/bash
# ============================================================
# WeChatAssistant 卸载脚本
# 恢复微信原始二进制 + 清理插件文件
# ============================================================

set -e

APP_PATH="${APP_PATH:-/Applications/WeChat.app}"
FRAMEWORK_NAME="WeChatAssistant"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_PATH="${APP_PATH}/Contents/MacOS"
APP_EXECUTABLE_PATH="${MACOS_PATH}/WeChat"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ [OK]${NC} $1"; }
warn() { echo -e "${YELLOW}⚠️  [WARN]${NC} $1"; }
info() { echo -e "${BLUE}👉 [INFO]${NC} $1"; }
die()  { echo -e "${RED}❌ [FATAL]${NC} $1"; exit 1; }

run_cmd() {
    info "执行: $*"
    "$@"
}

echo ""
echo -e "${GREEN}==============================${NC}"
echo -e "${GREEN} Uninstall ${FRAMEWORK_NAME}${NC}"
echo -e "${GREEN}==============================${NC}"
echo ""

# 检查 sudo
if [ "$EUID" -ne 0 ]; then
    warn "需要 sudo 权限"
    echo "请使用: sudo bash uninstall.sh"
    exit 1
fi

# 检查微信
if [ ! -d "$APP_PATH" ]; then
    die "未找到微信: ${APP_PATH}"
fi

# 查找备份文件
BACKUP_FILES=$(ls "${MACOS_PATH}/WeChat.backup."* 2>/dev/null || echo "")
RESTORED=false

if [ -n "$BACKUP_FILES" ]; then
    # 使用最新的备份
    LATEST_BACKUP=$(echo "$BACKUP_FILES" | sort | tail -1)
    info "恢复原始微信: ${LATEST_BACKUP}"
    run_cmd cp -p "$LATEST_BACKUP" "$APP_EXECUTABLE_PATH"
    run_cmd chmod +x "$APP_EXECUTABLE_PATH"
    run_cmd rm "$LATEST_BACKUP"
    ok "已从备份恢复"
    RESTORED=true
else
    warn "未找到备份文件，尝试查找其他备份..."
    # 尝试通用备份名
    if [ -f "${MACOS_PATH}/WeChat.backup" ]; then
        run_cmd cp -p "${MACOS_PATH}/WeChat.backup" "$APP_EXECUTABLE_PATH"
        run_cmd chmod +x "$APP_EXECUTABLE_PATH"
        run_cmd rm "${MACOS_PATH}/WeChat.backup"
        ok "已从通用备份恢复"
        RESTORED=true
    fi
fi

# 清理 dylib (Frameworks 目录)
DYLIB_PATH="${APP_PATH}/Contents/Frameworks/${FRAMEWORK_NAME}.dylib"
if [ -f "$DYLIB_PATH" ]; then
    info "移除 dylib: ${DYLIB_PATH}"
    run_cmd rm "$DYLIB_PATH"
    ok "已移除 dylib"
fi

# 清理 Framework (MacOS 目录)
FW_PATH="${MACOS_PATH}/${FRAMEWORK_NAME}.framework"
if [ -d "$FW_PATH" ]; then
    info "移除 Framework: ${FW_PATH}"
    run_cmd rm -rf "$FW_PATH"
    ok "已移除 Framework"
fi

# 清理其他残留
INSTALL_STATE="${MACOS_PATH}/.${FRAMEWORK_NAME}.install_state"
if [ -f "$INSTALL_STATE" ]; then
    run_cmd rm "$INSTALL_STATE"
fi

# 重新签名
info "重新签名..."
run_cmd codesign --force --deep --sign - --timestamp=none "$APP_PATH" 2>/dev/null || warn "签名警告"
ok "签名完成"

echo ""
echo -e "${GREEN}==============================${NC}"
if [ "$RESTORED" = true ]; then
    echo -e "${GREEN}✅ ${FRAMEWORK_NAME} 已完全卸载${NC}"
else
    echo -e "${YELLOW}⚠️  ${FRAMEWORK_NAME} 已清理，但未找到原始备份${NC}"
    echo "如需完全还原，请从官网重新下载安装微信"
fi
echo -e "${GREEN}==============================${NC}"
echo ""
echo "请重启微信"
