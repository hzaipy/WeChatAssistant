#!/bin/bash
# ============================================================
# WeChatAssistant 安装脚本
# 借鉴 SovietExtension 的版本匹配 + 架构检测 + 三步签名
# 仅支持 Apple Silicon (arm64) + 微信 4.1.9+ 
# ============================================================

set -e

# ---- 配置 ----
APP_PATH="${APP_PATH:-/Applications/WeChat.app}"
FRAMEWORK_NAME="WeChatAssistant"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/.build/products"
FRAMEWORK_SRC="${BUILD_DIR}/${FRAMEWORK_NAME}.dylib"

# 如果源码目录存在 framework 则优先使用
if [ -d "${SCRIPT_DIR}/../Sources/WeChatAssistant" ]; then
    DYLIB_MODE="dylib"
    LOAD_DYLIB_PATH="@executable_path/../Frameworks/${FRAMEWORK_NAME}.dylib"
    FRAMEWORK_DST_PATH=""
else
    DYLIB_MODE="framework"
    LOAD_DYLIB_PATH="@executable_path/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}"
    FRAMEWORK_SRC="${SCRIPT_DIR}/Plugin/${FRAMEWORK_NAME}.framework"
fi

MACOS_PATH="${APP_PATH}/Contents/MacOS"
APP_EXECUTABLE_PATH="${MACOS_PATH}/WeChat"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ---- 工具函数 ----
ok()   { echo -e "${GREEN}✅ [OK]${NC} $1"; }
warn() { echo -e "${YELLOW}⚠️  [WARN]${NC} $1"; }
info() { echo -e "${BLUE}👉 [INFO]${NC} $1"; }
die()  { echo -e "${RED}❌ [FATAL]${NC} $1"; exit 1; }

run_cmd() {
    info "执行: $*"
    "$@"
}

# ---- 版本支持文件 ----
SUPPORTED_VERSIONS_FILE="${SCRIPT_DIR}/supported_versions.txt"
if [ ! -f "$SUPPORTED_VERSIONS_FILE" ]; then
    # 创建默认支持文件
    cat > "$SUPPORTED_VERSIONS_FILE" << 'VEOF'
# WeChatAssistant 支持的微信版本列表
# 格式：DisplayVersion|CFBundleShortVersionString|CFBundleVersion|Note
4.1.9.58|4.1.9|268602|Pointer Hook
4.1.10.53|4.1.10|268853|Inline Hook
VEOF
    ok "已创建默认版本支持文件"
fi

echo ""
echo -e "${GREEN}==============================${NC}"
echo -e "${GREEN} Install ${FRAMEWORK_NAME}${NC}"
echo -e "${GREEN}==============================${NC}"
echo ""

# ---- 步骤 1: 系统环境检查 ----
info "检查系统环境..."

# 芯片架构检查
HOST_ARCH=$(uname -m)
if [ "$HOST_ARCH" != "arm64" ]; then
    die "仅支持 Apple Silicon (M 芯片) Mac，当前架构: ${HOST_ARCH}"
fi
ok "芯片架构: Apple Silicon (arm64)"

# 微信安装检查
if [ ! -d "$APP_PATH" ]; then
    die "未找到微信: ${APP_PATH}"
fi
ok "微信路径: ${APP_PATH}"

# ---- 步骤 2: 版本检测 ----
info "检测微信版本..."

read_plist() {
    /usr/libexec/PlistBuddy -c "Print $1" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo ""
}

APP_SHORT_VERSION=$(read_plist CFBundleShortVersionString)
APP_BUILD_VERSION=$(read_plist CFBundleVersion)
APP_BUNDLE_ID=$(read_plist CFBundleIdentifier)

if [ -z "$APP_SHORT_VERSION" ] || [ -z "$APP_BUILD_VERSION" ]; then
    die "无法读取微信版本信息"
fi

info "  CFBundleShortVersionString: ${APP_SHORT_VERSION}"
info "  CFBundleVersion:            ${APP_BUILD_VERSION}"
info "  CFBundleIdentifier:         ${APP_BUNDLE_ID}"

# 匹配支持版本
MATCHED_DISPLAY_VERSION=""
MATCHED_NOTE=""
VERSION_MATCHED=false

is_build_token() {
    local token="$1"
    [ "$token" = "*" ] && return 0
    [[ "$token" =~ ^[0-9]+$ ]] && return 0
    return 1
}

while IFS='|' read -r f1 f2 f3 f4; do
    [ -z "$f1" ] && continue
    [[ "$f1" =~ ^[[:space:]]*# ]] && continue

    local display_version short_version build_version note

    if [ -n "$f3" ] && is_build_token "$f3"; then
        # 新格式: DisplayVersion|ShortVersion|BuildVersion|Note
        display_version="$f1"; short_version="$f2"
        build_version="$f3"; note="$f4"
    else
        # 旧格式兼容
        display_version="$f1"; short_version="$f1"
        build_version="$f2"; note="$f3"
    fi

    if { [ "$short_version" = "$APP_SHORT_VERSION" ] || [ "$short_version" = "*" ]; } && \
       { [ "$build_version" = "$APP_BUILD_VERSION" ] || [ "$build_version" = "*" ]; }; then
        MATCHED_DISPLAY_VERSION="$display_version"
        MATCHED_NOTE="$note"
        VERSION_MATCHED=true
        ok "版本检查通过: ${display_version}"
        [ -n "$note" ] && info "  备注: ${note}"
        break
    fi
done < "$SUPPORTED_VERSIONS_FILE"

if [ "$VERSION_MATCHED" = false ]; then
    warn "当前版本 ${APP_SHORT_VERSION} (${APP_BUILD_VERSION}) 不在支持列表中"
    warn "支持的版本:"
    grep -v '^#' "$SUPPORTED_VERSIONS_FILE" | grep -v '^$' | while IFS='|' read -r f1 f2 f3 f4; do
        [ -z "$f1" ] && continue
        echo "  - $f1 ($f3)"
    done
    echo ""
    
    if [ "${FORCE_INSTALL:-0}" = "1" ]; then
        warn "--force 模式，跳过版本检查"
    else
        echo -n "是否继续安装? [y/N]: "
        read -r REPLY
        if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
            die "安装已取消"
        fi
        warn "强制安装，可能存在兼容性问题"
    fi
    MATCHED_DISPLAY_VERSION="${APP_SHORT_VERSION}"
fi

BACKUP_PATH="${APP_EXECUTABLE_PATH}.backup.${MATCHED_DISPLAY_VERSION}.${APP_BUILD_VERSION}"

# ---- 步骤 3: 检查/构建 dylib ----
if [ "$DYLIB_MODE" = "dylib" ]; then
    if [ ! -f "$FRAMEWORK_SRC" ]; then
        info "未找到编译好的 dylib，正在构建..."
        cd "$PROJECT_DIR"
        make dylib 2>&1 || die "构建失败，请检查编译环境"
        if [ ! -f "$FRAMEWORK_SRC" ]; then
            die "构建产物未找到: ${FRAMEWORK_SRC}"
        fi
    fi
    ok "Dylib 已就绪: ${FRAMEWORK_SRC}"
fi

# ---- 步骤 4: 备份原始微信 ----
backup_executable() {
    if [ -f "$BACKUP_PATH" ]; then
        # 检查备份是否干净
        if otool -L "$BACKUP_PATH" 2>/dev/null | grep -q "$FRAMEWORK_NAME"; then
            die "备份文件已被注入，请手动清理: ${BACKUP_PATH}"
        fi
        ok "复用已有备份: ${BACKUP_PATH}"
        return
    fi

    # 检查当前主程序是否已注入
    if otool -L "$APP_EXECUTABLE_PATH" 2>/dev/null | grep -q "$FRAMEWORK_NAME"; then
        # 已有注入但无备份
        warn "检测到已有注入但无干净备份"
        warn "将尝试卸载后重新安装"
        if [ -f "${SCRIPT_DIR}/uninstall.sh" ]; then
            bash "${SCRIPT_DIR}/uninstall.sh"
        fi
    fi

    info "备份原始微信: ${BACKUP_PATH}"
    run_cmd cp -p "$APP_EXECUTABLE_PATH" "$BACKUP_PATH"
    ok "备份完成"
}

backup_executable

# ---- 步骤 5: 恢复干净主程序 ----
info "从备份恢复干净主程序..."
run_cmd cp -p "$BACKUP_PATH" "$APP_EXECUTABLE_PATH"
run_cmd chmod +x "$APP_EXECUTABLE_PATH"
ok "已恢复干净主程序"

# ---- 步骤 6: 复制 dylib ----
info "复制动态库..."
if [ "$DYLIB_MODE" = "dylib" ]; then
    FRAMEWORKS_DIR="${APP_PATH}/Contents/Frameworks"
    run_cmd mkdir -p "$FRAMEWORKS_DIR"
    run_cmd cp "$FRAMEWORK_SRC" "${FRAMEWORKS_DIR}/${FRAMEWORK_NAME}.dylib"
    ok "已复制到 Frameworks 目录"
else
    FRAMEWORK_DST_PATH="${MACOS_PATH}/${FRAMEWORK_NAME}.framework"
    if [ -d "$FRAMEWORK_DST_PATH" ]; then
        run_cmd rm -rf "$FRAMEWORK_DST_PATH"
    fi
    run_cmd cp -R "$FRAMEWORK_SRC" "$FRAMEWORK_DST_PATH"
    ok "已复制 Framework"
fi

# ---- 步骤 7: 注入 dylib ----
info "注入动态库加载指令..."

select_insert_dylib() {
    local candidates=(
        "${SCRIPT_DIR}/insert_dylib_${HOST_ARCH}"
        "${SCRIPT_DIR}/insert_dylib"
        "$(which insert_dylib 2>/dev/null || echo '')"
    )

    for candidate in "${candidates[@]}"; do
        [ -z "$candidate" ] && continue
        [ ! -f "$candidate" ] && continue
        chmod +x "$candidate" 2>/dev/null || true
        xattr -rd com.apple.quarantine "$candidate" 2>/dev/null || true
        echo "$candidate"
        return
    done

    # 尝试 brew 安装
    if command -v brew &>/dev/null; then
        info "通过 Homebrew 安装 insert_dylib..."
        brew install insert_dylib 2>/dev/null || true
        local brew_path=$(which insert_dylib 2>/dev/null || echo '')
        if [ -n "$brew_path" ]; then
            echo "$brew_path"
            return
        fi
    fi

    die "未找到 insert_dylib，请安装: brew install insert_dylib"
}

INSERT_DYLIB=$(select_insert_dylib)
ok "insert_dylib: ${INSERT_DYLIB}"

info "执行注入..."
INSERT_OUTPUT=$("$INSERT_DYLIB" --all-yes "$LOAD_DYLIB_PATH" "$BACKUP_PATH" "$APP_EXECUTABLE_PATH" 2>&1) || {
    if echo "$INSERT_OUTPUT" | grep -qi "Bad CPU type"; then
        die "insert_dylib 架构不匹配，请确认 dylib 和微信都是 arm64 架构"
    fi
    die "注入失败: ${INSERT_OUTPUT}"
}
ok "注入完成"

run_cmd chmod +x "$APP_EXECUTABLE_PATH"

# ---- 步骤 8: 三步重签名 ----
sign_app() {
    info "重新签名..."

    # 第一步：签名 dylib
    if [ "$DYLIB_MODE" = "dylib" ]; then
        run_cmd codesign --force --deep --sign - --timestamp=none \
            "${APP_PATH}/Contents/Frameworks/${FRAMEWORK_NAME}.dylib" 2>/dev/null || warn "dylib 签名警告"
    else
        run_cmd codesign --force --deep --sign - --timestamp=none \
            "${FRAMEWORK_DST_PATH}" 2>/dev/null || warn "Framework 签名警告"
    fi
    ok "第一步: dylib 签名完成"

    # 第二步：签名 WeChatAppEx.app（如果存在）
    APP_EX_PATH="${MACOS_PATH}/WeChatAppEx.app"
    if [ -d "$APP_EX_PATH" ]; then
        run_cmd xattr -rd com.apple.quarantine "$APP_EX_PATH" 2>/dev/null || true
        run_cmd codesign --force --deep --sign - --timestamp=none "$APP_EX_PATH" 2>/dev/null || true

        WEAPP_PATH="${APP_EX_PATH}/Contents/Frameworks/WeChatAppEx Framework.framework/Versions/C/Helpers/WeApp.app"
        if [ -d "$WEAPP_PATH" ]; then
            run_cmd codesign --force --deep --sign - --timestamp=none "$WEAPP_PATH" 2>/dev/null || true
        fi
        ok "第二步: WeChatAppEx.app 签名完成"
    fi

    # 第三步：签名整个 WeChat.app
    run_cmd codesign --force --deep --sign - --timestamp=none "$APP_PATH" 2>/dev/null || warn "主应用签名警告"
    ok "第三步: WeChat.app 签名完成"
}

sign_app

# ---- 步骤 9: 验证安装 ----
verify_install() {
    info "验证安装..."

    # 检查注入
    if otool -L "$APP_EXECUTABLE_PATH" 2>/dev/null | grep -q "$FRAMEWORK_NAME"; then
        ok "LC_LOAD_DYLIB 已注入"
        info "加载命令详情:"
        otool -L "$APP_EXECUTABLE_PATH" 2>/dev/null | grep -A1 "$FRAMEWORK_NAME" || true
    else
        die "LC_LOAD_DYLIB 未找到，注入可能失败"
    fi

    # 检查签名
    if codesign -vvv --deep --strict "$APP_PATH" >/dev/null 2>&1; then
        ok "代码签名验证通过"
    else
        warn "签名验证未完全通过，但调试运行不一定受影响"
    fi
}

verify_install

# ---- 完成 ----
echo ""
echo -e "${GREEN}==============================${NC}"
echo -e "${GREEN}✅ ${FRAMEWORK_NAME} 安装完成${NC}"
echo -e "${GREEN}==============================${NC}"
echo ""
echo "启动微信并查看日志："
echo "  open -a WeChat"
echo "  tail -f ~/Library/Application\\ Support/WeChatAssistant/Logs/wechat-assistant.log"
echo ""
echo "卸载："
echo "  sudo bash ${SCRIPT_DIR}/uninstall.sh"
echo ""
