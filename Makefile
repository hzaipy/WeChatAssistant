# WeChatAssistant Makefile
# macOS 微信助手构建系统
# 仅在 macOS 上可编译，目标: Apple Silicon (arm64) + 微信 4.1.x

ARCHS := arm64
TARGET_DYLIB := WeChatAssistant.dylib
TARGET_CLI := wechat-assistant
BUILD_DIR := .build
PRODUCTS_DIR := $(BUILD_DIR)/products

# 检测构建环境
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  SDKROOT := $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null)
  CC := $(shell xcrun --sdk macosx -f clang 2>/dev/null)
  SWIFTC := $(shell xcrun -f swiftc 2>/dev/null)
  CAN_BUILD := true
else
  CAN_BUILD := false
endif

OBJC_FLAGS := -ObjC -fobjc-arc -mmacosx-version-min=12.0 \
              -I Sources/WeChatAssistant \
              -I Sources/WeChatAssistant/Hook \
              -I Sources/WeChatAssistant/Managers \
              -I Sources/WeChatAssistant/Models \
              -I Sources/WeChatAssistant/Views \
              -I Sources/WeChatAssistant/WindowControllers \
              -I Sources/WeChatAssistant/Utils
ifdef SDKROOT
  OBJC_FLAGS += -isysroot $(SDKROOT)
endif

WARNING_FLAGS := -Wall -Wextra -Wno-unused-parameter
DYLIB_FLAGS := -dynamiclib \
               -install_name @executable_path/../Frameworks/WeChatAssistant.dylib \
               -framework Foundation \
               -framework AppKit \
               -framework UserNotifications \
               -lsqlite3

SOURCES := $(shell find Sources/WeChatAssistant -name '*.m' -type f 2>/dev/null)
HEADERS := $(shell find Sources/WeChatAssistant -name '*.h' -type f 2>/dev/null)
OBJECTS := $(patsubst Sources/WeChatAssistant/%.m,$(BUILD_DIR)/obj/%.o,$(SOURCES))

.PHONY: all clean dylib cli install uninstall help check info

all: check-platform dylib cli

# === 平台检查 ===
check-platform:
ifeq ($(CAN_BUILD),false)
	@echo "⚠️  当前环境不是 macOS，无法编译此项目"
	@echo ""
	@echo "WeChatAssistant 是 macOS 原生项目，需要在 Apple Silicon Mac 上构建。"
	@echo "请将项目复制到 M 芯片 Mac 上执行:"
	@echo ""
	@echo "  make all           # 构建全部"
	@echo "  sudo make install  # 安装到微信"
	@echo ""
	@echo "可用的非构建命令:"
	@echo "  make check         # 检查代码文件"
	@echo "  make info          # 查看项目信息"
	@exit 0
endif

# === 动态库构建 ===
dylib: check-platform $(PRODUCTS_DIR)/$(TARGET_DYLIB)

$(PRODUCTS_DIR)/$(TARGET_DYLIB): $(OBJECTS)
	@mkdir -p $(PRODUCTS_DIR)
	$(CC) $(OBJC_FLAGS) $(DYLIB_FLAGS) -o $@ $(OBJECTS)
	@echo "✅ Built $@"
	@lipo -info $@ 2>/dev/null || file $@

$(BUILD_DIR)/obj/%.o: Sources/WeChatAssistant/%.m
	@mkdir -p $(dir $@)
	$(CC) $(OBJC_FLAGS) $(WARNING_FLAGS) -c $< -o $@

# === CLI 安装工具构建 ===
cli: check-platform $(PRODUCTS_DIR)/$(TARGET_CLI)

$(PRODUCTS_DIR)/$(TARGET_CLI): Sources/WeChatAssistantInstaller/main.swift
	@mkdir -p $(PRODUCTS_DIR)
	$(SWIFTC) -target $(ARCHS)-apple-macos12.0 -o $@ $<
	@echo "✅ Built $@"

# === 安装到本地微信 ===
install: dylib
	@echo "🔧 Installing WeChatAssistant..."
	@bash Scripts/install.sh

uninstall:
	@echo "🗑 Uninstalling WeChatAssistant..."
	@bash Scripts/uninstall.sh

# === 代码检查（跨平台） ===
check:
	@echo "📋 检查项目文件..."
	@echo ""
	@echo "=== 源文件统计 ==="
	@echo "Objective-C 文件: $$(find Sources/WeChatAssistant -name '*.m' | wc -l)"
	@echo "头文件:          $$(find Sources/WeChatAssistant -name '*.h' | wc -l)"
	@echo "Swift 文件:      $$(find Sources -name '*.swift' | wc -l)"
	@echo "主题文件:        $$(find Resources -name '*.json' | wc -l)"
	@echo "脚本文件:        $$(find Scripts -name '*.sh' | wc -l)"
	@echo "总行数:          $$(find Sources -name '*.m' -o -name '*.h' -o -name '*.swift' | xargs wc -l 2>/dev/null | tail -1)"
	@echo ""
	@echo "=== 关键功能覆盖 ==="
	@grep -rn "revoke\|撤回" Sources/WeChatAssistant/Hook/WARevokeHook.m | head -3 || echo "  ⚠️ 防撤回 Hook"
	@grep -rn "group.*monitor\|群.*监控\|退群" Sources/WeChatAssistant/Hook/WAGroupMonitorHook.m | head -3 || echo "  ⚠️ 退群监控 Hook"
	@grep -rn "theme\|主题\|color" Sources/WeChatAssistant/Hook/WAThemeHook.m | head -3 || echo "  ⚠️ 主题 Hook"

# === 项目信息 ===
info:
	@echo "WeChatAssistant - macOS 微信助手"
	@echo "================================"
	@echo "目标平台:  macOS 12+ / Apple Silicon (arm64)"
	@echo "微信版本:  4.1.x 系列"
	@echo "开发语言:  Objective-C + Swift"
	@echo "构建系统:  Makefile + xcodebuild"
	@echo "分发方式:  Homebrew"
	@echo ""
	@echo "功能: 消息防撤回 | 退群监控 | 主题更换"

# === 清理 ===
clean:
	rm -rf $(BUILD_DIR)

# === 帮助 ===
help:
	@echo "WeChatAssistant 构建系统"
	@echo ""
	@echo "构建命令 (仅 macOS):"
	@echo "  make all       - 构建 dylib + CLI 工具"
	@echo "  make dylib     - 仅构建动态库"
	@echo "  make cli       - 仅构建 CLI 安装器"
	@echo "  make install   - 安装到微信 (需 sudo)"
	@echo "  make uninstall - 从微信卸载 (需 sudo)"
	@echo ""
	@echo "通用命令:"
	@echo "  make check     - 检查代码文件"
	@echo "  make info      - 查看项目信息"
	@echo "  make clean     - 清理构建产物"
