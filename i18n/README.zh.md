# LaunchNG

**语言**: [English](../README.md) | [简体中文](README.zh.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

macOS Tahoe（26）彻底移除了 Launchpad。LaunchNG 把它作为一个原生应用带了回来：首次运行时直接从 macOS 自身的数据库读取你原有的 Launchpad 布局，然后在基于 Core Animation 渲染的网格之上，自行实现分页、文件夹、搜索和拖拽排序，并集成 Dock、内置 CLI/TUI，以及应用内的签名自动更新。

## 下载

**[获取最新版本](https://github.com/moonmig/LaunchNG/releases/latest)**

如果这个应用对你有帮助，欢迎点个 star。LaunchNG 最初是 RoversX 的 [LaunchNext](https://github.com/RoversX/LaunchNext) 的一个分支——原项目也值得一个 star。

<!-- 截图将放在这里——如果你愿意提供最新截图，请见「贡献」部分。 -->

### 如果 macOS 阻止应用启动

本项目发布的是未签名 / ad-hoc 构建（这个分支没有使用付费的 Apple 开发者账号），因此 Gatekeeper 会拒绝打开应用，直到你手动清除一次隔离标记：

```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNG.app
```

请只对你信任的应用执行此命令——它会关闭 macOS 对该应用的下载隔离检查。

从源码构建？请见下方的[配置本地代码签名](#configure-local-code-signing)，你不需要这条命令。

## LaunchNG 能做什么

- **一键从真实 Launchpad 数据库导入** —— 直接读取 `/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db`，精确还原你现有的文件夹、位置和分页
- **经典的分页网格体验** —— 搜索、键盘导航、拖拽排序，把一个图标拖到另一个上即可创建文件夹
- **全程基于 Core Animation 渲染**，包括直接拖拽到 Dock，以及 macOS 26 上原生的 Liquid Glass 文件夹图标
- **文件夹布局**：分页（如原版）或垂直滚动，任你选择
- **模糊搜索**，支持 CJK（拼音等）转写匹配，即使输入不完整或不准确也能找到应用
- **热角和触控板手势激活**，包括实验性的四指/五指捏合与点按支持
- **CLI 和 TUI**，可在终端中查看或操作你的布局
- **通过 [Sparkle](https://sparkle-project.org) 实现的签名自动更新**，应用内提供普通的「检查更新」按钮
- **本地备份**到你指定的文件夹，并保留可供恢复的历史记录
- **隐藏图标标签、调整图标大小与间距** —— 主网格与文件夹内容可分别设置
- **13 种语言**的完整界面翻译（见上方语言列表）
- **更强的右键菜单** —— 在 Finder 中显示、复制应用路径、重命名文件夹，以及（可选）为其他受信任应用解除 Gatekeeper 隔离的快捷操作
- **手柄与语音反馈支持**，照顾无障碍使用场景

## macOS Tahoe 拿走了什么

- 没有用户自建文件夹，也无法自由组织
- 无法拖拽调整顺序
- 完全没有可视化的应用管理——只有一个自动生成、按字母排序、你动不了的网格

LaunchNG 之所以存在，是因为这确实是一种倒退，而不是合理的默认设计。

## 数据存放在哪里

LaunchNG 自身的布局、偏好设置和缓存保存在：

```
~/Library/Application Support/LaunchNG/Data.store
```

不会向任何地方发送数据。唯一的网络活动是检查更新源，以及——当你主动触发时——读取 Apple 自己的 Launchpad 数据库：

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## 安装

### 环境要求

- macOS 26（Tahoe）或更新版本
- Apple Silicon 或 Intel 处理器
- 如需从源码构建，需要 Xcode 26

### 从源码构建

```bash
git clone https://github.com/moonmig/LaunchNG.git
cd LaunchNG
open LaunchNG.xcodeproj
```

<a name="configure-local-code-signing"></a>**配置本地代码签名**（不需要付费的 Apple 开发者账号）：

- 选择 **LaunchNG** target → **Signing & Capabilities** → 将 **Team** 设为 `None`，签名证书选择 `Sign to Run Locally`。保持 Hardened Runtime 开启。
- 修改后 Xcode 会将工程文件标记为已修改——请不要把仅与签名相关的改动放进 pull request。

要用 `⌘R` 运行，目标设备必须是 **My Mac**——通用 /「Any Mac」目标可以构建和归档，但无法用于调试运行。仅需构建时按 `⌘B`。

### 命令行构建

```bash
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release

# 通用二进制文件（Apple Silicon + Intel）：
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## 使用方法

1. **首次启动**时会自动扫描已安装的应用。
2. **设置 → General → Import System Launchpad**，一键导入你现有的布局、文件夹和位置。
3. 单击选中，双击（或按 Return）启动；随时输入即可搜索。
4. 把一个应用拖到另一个上创建文件夹；拖动应用可调整顺序。
5. 如果想在终端脚本化操作布局，可在设置中启用 CLI。

### 全屏与紧凑模式

- **全屏**模式占满整个屏幕，最接近原版 Launchpad。
- **紧凑**模式是一个可调整大小、带圆角的浮动窗口。
- 外观设置（图标缩放、间距、分页指示器位置等）在两种模式下分别记录。
- 全屏模式下可选隐藏菜单栏；开启后 macOS 会自动隐藏 Dock。

## 值得关注的设置

- **外观**：图标缩放、标签大小与显示与否、网格间距——文件夹内容可单独设置——以及背景样式（模糊、原生 Liquid Glass，或基于动态壁纸的背景）
- **搜索**：模糊匹配开关与搜索防抖延迟
- **隐藏应用**：无需卸载即可把特定应用从网格中隐藏
- **备份**：选择文件夹、创建带时间戳的备份，并可从列表中恢复或删除旧备份
- **快捷键与手势**：全局热键、热角，以及（实验性的）触控板手势绑定
- **更新**：自动检查开关与手动「检查更新」按钮，均基于 Sparkle

## 疑难解答

**应用无法启动。** 请确认系统是 macOS 26.0 或更新版本，并且已清除隔离标记（见上文）。

**「检查更新」提示出错。** LaunchNG 使用带签名更新源的 Sparkle；手动检查应该总能在几分钟内反映最新发布的版本。

**终端里没有 `launchng` 命令。** 这是可选功能——请先在设置中启用命令行接口，LaunchNG 会自动安装（之后也能自行移除）受管理的命令。

## 参与贡献

1. Fork 本仓库
2. 创建功能分支（`git checkout -b feature/your-feature`）
3. 提交清晰的改动说明
4. 推送分支并打开 pull request

有助于顺利通过审查的几点建议：
- 不要把仅与签名相关的 Xcode 工程改动带入 diff（见上方本地代码签名部分）
- 如果改动 Core Animation 网格，先看看 `GridReorderPlan.swift`——排序/分页逻辑应该集中在那里，而不是在各个视图里重复实现
- 提交 PR 前先跑一遍测试：
  ```bash
  xcodebuild test -scheme LaunchNG -destination 'platform=macOS'
  ```

提供新鲜、准确的截图（主网格、几个设置页面）同样是很有价值的贡献——见本文件开头的占位说明。

### 更多文档

- [Folder Liquid Glass](../Documentation/FolderLiquidGlass.md) —— 文件夹玻璃图标背后的设计约束、已验证内容，以及仍待验收的部分
- [Grid diagnostics](../scripts/diagnostics/README.md) —— 网格与玻璃叠层的手动探针，及其确切覆盖范围与限制

## 许可与致谢

LaunchNG 是 RoversX 的 [LaunchNext](https://github.com/RoversX/LaunchNext) 的分支，而后者又源自更广泛的 Launchpad 替代方案社区项目。两者均采用 GPL-3.0 许可，LaunchNG 遵循相同条款——详见 [LICENSE](../LICENSE)。

实验性触控板手势支持基于 [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) 及 [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport) 的分支构建。

---

![GitHub downloads](https://img.shields.io/github/downloads/moonmig/LaunchNG/total)
