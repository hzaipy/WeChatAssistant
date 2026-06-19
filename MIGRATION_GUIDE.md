# 从 WeChatExtension-ForMac (3.9.2) 迁移到 WeChatAssistant (4.1.x)

## 适用场景

- 当前：微信 3.9.2 + WeChatExtension-ForMac 老助手
- 目标：微信 4.1.x + WeChatAssistant 新助手

---

## 第一步：备份聊天记录（重要！）

微信 3.x → 4.x 是架构重构，数据存储位置变了。虽然微信会自动迁移，但**务必先手动备份**。

### 备份方法

```bash
# 1. 完全退出微信
# 2. 备份整个微信数据目录
cp -r ~/Library/Containers/com.tencent.xinWeChat/Data/Library/Application\ Support/com.tencent.xinWeChat \
      ~/Desktop/微信数据备份_$(date +%Y%m%d)

# 3. 确认备份大小（一般几GB到几十GB）
du -sh ~/Desktop/微信数据备份_*
```

> ⚠️ 聊天记录对你很重要的话，**这一步绝对不能跳过**！

---

## 第二步：卸载 WeChatExtension-ForMac

### 方式一：用原始卸载脚本（推荐）

如果你还保留着 WeChatExtension-ForMac 的项目目录：

```bash
cd /path/to/WeChatExtension-ForMac/WeChatExtension/Rely
sudo bash Uninstall.sh
```

看到 `卸载成功, 重启微信生效!` 即完成。

### 方式二：手动清理

```bash
# 1. 完全退出微信
# 2. 恢复原始微信二进制
WECHAT_APP="/Applications/WeChat.app"
WECHAT_BIN="$WECHAT_APP/Contents/MacOS/WeChat"
BACKUP="$WECHAT_APP/Contents/MacOS/WeChat_backup"

if [ -f "$BACKUP" ]; then
    sudo cp "$BACKUP" "$WECHAT_BIN"
    sudo rm "$BACKUP"
    echo "✅ 已恢复原始微信二进制"
else
    echo "⚠️ 未找到备份文件"
fi

# 3. 删除插件框架
sudo rm -rf "$WECHAT_APP/Contents/MacOS/WeChatExtension.framework"
sudo rm -rf "$WECHAT_APP/Contents/MacOS/WeChatExtension"

# 4. 重新签名
sudo codesign --force --deep --sign - "$WECHAT_APP"
echo "✅ 清理完成"
```

---

## 第三步：升级微信到 4.1.x

### 下载最新版微信

从官网下载：https://mac.weixin.qq.com/

或者直接下载最新版：
```
https://dldir1v6.qq.com/weixin/Universal/Mac/WeChatMac_4.1.9.dmg
```

### 安装

1. 打开下载的 DMG 文件
2. 将微信拖入 `/Applications` 覆盖旧版
3. **首次启动微信 4.x 时，会自动检测并导入 3.x 的聊天记录**
   - 如果没自动导入：微信菜单 → 左下角「三」→「导入历史聊天记录」

### 验证聊天记录

- 确认聊天记录完整
- 确认文件/图片可以打开
- 如有问题，使用第一步的备份恢复

---

## 第四步：安装 WeChatAssistant

### 前提条件

```bash
# 确认芯片架构（必须是 arm64）
uname -m
# 输出应为: arm64

# 确认微信版本
defaults read /Applications/WeChat.app/Contents/Info.plist CFBundleVersion
# 应输出类似: 36559 (对应 4.1.9)
```

### 安装步骤

```bash
# 1. 进入项目目录
cd /path/to/WeChatAssistant

# 2. 编译（需要 Xcode Command Line Tools）
make all
# 如果提示缺少 xcrun，先安装:
# xcode-select --install

# 3. 安装到微信
sudo make install

# 4. 看到 "✅ WeChatAssistant 安装完成!" 即成功
```

### 如果 make 编译遇到问题

```bash
# 确保有 Xcode Command Line Tools
xcode-select --install

# 确保有 insert_dylib
brew install insert_dylib

# 然后重试
make clean && make all
```

---

## 第五步：验证新助手是否正常工作

1. **重启微信**
2. 查看菜单栏是否出现 **「微信助手」** 菜单
3. 点击「微信助手」→「关于微信助手」确认版本信息
4. 测试功能：
   - **防撤回**：让朋友发消息后撤回，看是否保留
   - **退群监控**：加入一个测试群，让成员退出看通知
   - **主题**：微信助手 → 主题 → 选择 Dark，重启微信看效果

---

## 第六步：如果出问题，如何回滚

### 回滚到原始微信

```bash
cd /path/to/WeChatAssistant
sudo make uninstall
```

这会：
- 恢复原始微信二进制（从备份）
- 删除 WeChatAssistant.dylib
- 重新签名微信

### 回滚到 3.9.2 + WeChatExtension-ForMac

1. 从 Time Machine 或备份恢复微信 3.9.2
2. 从第一步的备份恢复聊天记录
3. 重新安装 WeChatExtension-ForMac

---

## 快速检查清单

| 步骤 | 命令 | 预期结果 |
|------|------|----------|
| 芯片 | `uname -m` | `arm64` |
| 微信版本 | `defaults read /Applications/WeChat.app/Contents/Info.plist CFBundleVersion` | `3xxxx` 以上 |
| 老插件已清理 | `ls /Applications/WeChat.app/Contents/MacOS/WeChatExtension*` | No such file |
| 备份存在 | `ls ~/Desktop/微信数据备份_*` | 有目录 |
| 编译成功 | `ls .build/products/WeChatAssistant.dylib` | 文件存在 |
| 注入成功 | `otool -L /Applications/WeChat.app/Contents/MacOS/WeChat \| grep WeChatAssistant` | 显示 dylib 路径 |

---

## 注意事项

1. **聊天记录是第一优先级**，升级前一定备份
2. 微信 4.x 初次启动可能较慢（在迁移数据），耐心等待
3. 如果微信 4.x 启动崩溃，可能是老插件没卸干净，重新执行第二步
4. 新助手目前是开发版本，如果遇到问题请反馈
