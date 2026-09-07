# FloatDude

<div align="center">

**一个快捷键。一个小浮窗。完成一件事。**

随叫随到的 Mac AI 浮窗助手。

[English](README.md) · [简体中文](README.zh-CN.md)

</div>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/design/floatdude-dark-glass-reference.png">
  <img alt="FloatDude 出现在 macOS 选中文本旁" src="docs/design/floatdude-light-glass-reference.png">
</picture>

FloatDude 是一款原生 macOS 菜单栏工具，围绕一个克制而完整的交互构建：

> 选中内容 → 呼出 FloatDude → 完成一件事 → 消失。

它不是被塞进浮窗里的聊天客户端。FloatDude 利用 macOS 原生快捷键、选区读取、窗口行为与系统权限，把一个轻量 AI 操作界面带到你正在处理的内容旁边。

## 它能做什么

- 使用全局快捷键 `⌥ Space` 呼出。
- 在条件允许时，通过 macOS 辅助功能读取当前文本选区。
- 安全回退到剪贴板或直接输入。
- 在选区附近展示一个可拖拽、始终置顶的浮窗。
- 提供 **解释**、**翻译**、**改写**和**自由提问**四种操作。
- 支持 OpenAI Chat Completions 与 Anthropic Messages 兼容接口的流式响应。
- 一键复制结果，按 `Esc` 或点击浮窗外部即可离开。
- 使用自适应玻璃界面，自动跟随 macOS 浅色或深色外观。

## 为什么选择原生 macOS

FloatDude 使用 Swift 编写，因为它最重要的能力本就属于 Mac：

- **SwiftUI** 负责界面、设置和应用状态。
- **AppKit** 负责 `NSPanel`、焦点、窗口层级、定位、菜单栏行为和辅助功能集成。
- **URLSession** 负责模型请求和服务器发送事件流。
- **Keychain Services** 可在用户明确选择后，将 API Key 保存在当前 Mac 上。

项目没有第三方运行时依赖，也没有 FloatDude 账号、同步服务或自建应用服务器。

## 环境要求

- macOS 14 Sonoma 或更高版本
- Xcode 16 或更高版本
- 一个兼容 OpenAI Chat Completions 或 Anthropic Messages 的模型接口

FloatDude 目前以开发构建形式提供，尚未发布经过签名和公证的 DMG 安装包。

## 构建与运行

```sh
git clone https://github.com/KkSss999/FloatDude.git
cd FloatDude
open FloatDude.xcodeproj
```

在 Xcode 中选择 **FloatDude** Scheme 并运行。FloatDude 常驻菜单栏，不占用 Dock。

随后：

1. 从菜单栏打开 **FloatDude → Settings…**。
2. 配置模型服务的 Base URL、模型、凭据模式和 API Key。
3. 在 **系统设置 → 隐私与安全性 → 辅助功能** 中授权 FloatDude。
4. 在其他应用中选中文字，然后按下 `⌥ Space`。

全新配置默认使用 DeepSeek 的 Anthropic 兼容接口、`deepseek-v4-flash` 模型和 **This Session Only** 凭据模式。所有服务商字段均可替换为其他兼容服务。

## 凭据与隐私

FloatDude 以本地优先为原则，但模型请求会被发送到你配置的服务商。

- **No Authentication**：不发送认证请求头。
- **This Session Only**：API Key 只保留在内存中，退出 FloatDude 或清理模型会话后消失。
- **Remember on This Mac**：仅在用户明确选择后，将 API Key 保存到 macOS 登录钥匙串。
- API Key 不会写入 `UserDefaults`、源代码、应用日志或接口 URL。
- 疑似凭据的选区或剪贴板内容会在成为模型上下文之前被拦截。
- 只有在你主动执行操作时，选中文本和提示词才会直接发送到配置的模型接口。
- FloatDude 不包含遥测，也没有项目方运营的服务器。

你仍需自行了解所选模型服务商的数据处理和保留政策。

## 项目结构

```text
Sources/FloatDude/
├── App/       应用生命周期与任务协调
├── UI/        SwiftUI 界面与 AppKit 浮窗边界
├── System/    快捷键、选区、剪贴板与窗口定位
├── AI/        服务商请求、SSE 流与操作定义
├── Storage/   偏好设置与钥匙串集成
└── Core/      公共领域类型
```

依赖方向为：

```text
App / UI → System / AI / Storage → Core
```

更多实现细节参见[架构说明](docs/ARCHITECTURE.md)、[界面方向](docs/UI_DIRECTION.md)、[开发交接](docs/DEVELOPMENT_HANDOFF.md)和[质量门槛](docs/QUALITY_GATES.md)。

## 本地验证

```sh
swift build
swift test
./Scripts/run-local-validation.sh
./Scripts/secret-scan.sh
xcodebuild -project FloatDude.xcodeproj -scheme FloatDude -destination 'platform=macOS' build
xcodebuild -project FloatDude.xcodeproj -scheme FloatDude -destination 'platform=macOS' test
```

Xcode 构建和 XCTest 测试需要完整安装 Xcode。开发构建使用 ad-hoc 签名，因此在构建路径或代码身份发生变化后，macOS 可能要求重新授予辅助功能权限。

## 参与贡献

欢迎提交 Issue 和边界清晰的 Pull Request。任何改动都应尊重 FloatDude 的核心约束：一次呼出、一个轻量界面、完成一件事。

提交代码前，请运行上述本地验证，并确认改动中不包含 API Key、选中文本或其他隐私内容。

## 作者

FloatDude 由 **Kerye（凯毅）** 构思、设计并开发——[@KkSss999](https://github.com/KkSss999)。

它既是一款开源 macOS 工具，也是一次关于 AI 如何变得原生、短暂且尊重用户当前上下文的产品探索。

## 开源协议

FloatDude 使用 [Apache License 2.0](LICENSE) 开源，作者归属信息参见 [NOTICE](NOTICE)。

除描述项目来源及复现归属声明所必需的合理使用外，该协议不授予 FloatDude 名称和视觉识别的使用权。
