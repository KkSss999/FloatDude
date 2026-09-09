# FloatDude

<div align="center">

**一个快捷键。一个常驻小浮窗。随时继续每段对话。**

随叫随到的 Mac AI 浮窗助手。

[English](README.md) · [简体中文](README.zh-CN.md)

</div>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/design/floatdude-dark-glass-reference.png">
  <img alt="FloatDude 出现在 macOS 选中文本旁" src="docs/design/floatdude-light-glass-reference.png">
</picture>

FloatDude 是一款原生 macOS 菜单栏 Agent，围绕一个克制、常驻的交互界面构建：

> 选中内容或添加文档 → 呼出 FloatDude → 随时继续对话。

FloatDude 利用 macOS 原生快捷键、选区读取、窗口行为与系统权限，把一个轻量 AI 工作区留在你正在处理的内容旁边。

## 它能做什么

- 使用全局快捷键 `⌥ Space` 呼出。
- 在条件允许时，通过 macOS 辅助功能读取当前文本选区。
- 安全回退到剪贴板或直接输入。
- 在选区附近展示一个可拖拽、始终置顶的浮窗。
- 切换应用、空间、全屏或台前调度时继续显示，直到用户明确关闭。
- 默认回到上次活动会话的最新位置，提供回到底部按钮和悬停展开的消息跳转导航。
- 面板常驻时同步待发送的选中文本；新建会话会带入这份实时上下文，但不会在发送前持久化选区。
- 飞书在 Electron 类渲染器未暴露辅助功能选区时，会回退为快捷键触发瞬间的剪贴板保留快照；该路径不是实时选区同步。其他受支持应用继续使用实时 AX 选区更新。
- 菜单栏页面、对话浮窗和设置页可即时切换 English / 简体中文，并在本机保存选择。
- 可在浮窗中添加 PDF、Markdown/文本、Word、XLSX、CSV 和 TSV。
- 模型只有两个受限原生工具：读取当前会话附件、写入托管 Markdown/文本产物。
- 提供 **解释**、**翻译**、**改写**和**自由提问**四种操作。
- 仅当当前辅助功能选区支持直接替换时显示 **改写**。
- 支持 OpenAI Chat Completions 与 Anthropic Messages 兼容接口的流式响应。
- 原生呈现 Markdown 标题、强调、链接、列表、引用、代码块、分隔线和表格。
- 一键复制结果，按 `Esc` 或关闭按钮明确关闭。
- 使用自适应玻璃界面，自动跟随 macOS 浅色或深色外观。

## 为什么选择原生 macOS

FloatDude 使用 Swift 编写，因为它最重要的能力本就属于 Mac：

- **SwiftUI** 负责界面、设置和应用状态。
- **AppKit** 负责 `NSPanel`、焦点、窗口层级、定位、菜单栏行为和辅助功能集成。
- **URLSession** 负责模型请求和服务器发送事件流。
- **PDFKit、AppKit 文档导入和原生 ZIP/XML 解析**负责用户选中文档的文本提取。
- **ServiceManagement** 负责可选的登录时启动。
- **Keychain Services** 可在用户明确选择后，将 API Key 保存在当前 Mac 上。

项目没有第三方运行时依赖，也没有 FloatDude 账号、同步服务或自建应用服务器。

## 环境要求

- macOS 14 Sonoma 或更高版本
- Xcode 26 或更高版本
- 一个兼容 OpenAI Chat Completions 或 Anthropic Messages 的模型接口

GitHub Release 中提供 v0.1.0 的 ad-hoc 签名、未公证 DMG，供本地体验。如果
Gatekeeper 阻止首次启动，请按住 Control 点按 FloatDude 并选择**打开**。请为
已安装的 `/Applications/FloatDude.app` 授予辅助功能权限；由于开发版没有稳定的
Developer ID 身份，后续替换构建时可能需要重新授权。

## 构建与运行

```sh
git clone https://github.com/KkSss999/FloatDude.git
cd FloatDude
open FloatDude.xcodeproj
```

在 Xcode 中选择 **FloatDude** Scheme 并运行。FloatDude 常驻菜单栏，不占用 Dock。

随后：

1. 从菜单栏打开 **FloatDude → Settings…**。
2. 配置 Base URL、模型、凭据模式、API Key 和可选的用户系统提示词。
3. 使用 **Test /models** 在对话前检查服务连通性。
4. 在 **系统设置 → 隐私与安全性 → 辅助功能** 中授权 FloatDude；macOS 27 中该入口名为“设备控制和数据访问”。
5. 在其他应用中选中文字并按 `⌥ Space`，或使用回形针按钮添加文档。

全新配置默认使用 DeepSeek 的 Anthropic 兼容接口、`deepseek-v4-flash` 模型和 **This Session Only** 凭据模式。所有服务商字段均可替换为其他兼容服务。

## 本地应用包

可直接生成并安装用于日常试用的 Release `.app`，无需保持 Xcode 运行：

```sh
bash Scripts/install-local-app.sh
```

脚本会构建 Release 包、替换 `/Applications/FloatDude.app`、删除其他 FloatDude
构建副本和旧链接、清理 Launch Services 的旧注册，然后打开唯一的安装版本。
应用常驻菜单栏，不显示 Dock 图标；
菜单栏的 **Ask FloatDude…** 或再次打开应用都可以呼出任务浮窗。
本地构建使用 ad-hoc 签名，尚非签名公证发行版。

## 凭据与隐私

FloatDude 以本地优先为原则，但模型请求会被发送到你配置的服务商。

- **No Authentication**：不发送认证请求头。
- **This Session Only**：API Key 只保留在内存中，退出 FloatDude 或清理模型会话后消失。
- **Remember on This Mac**：仅在用户明确选择后，将 API Key 保存到 macOS 登录钥匙串。
- API Key 不会写入 `UserDefaults`、源代码、应用日志或接口 URL。
- 疑似凭据的选区或剪贴板内容会在成为模型上下文之前被拦截。
- 只有在你主动执行操作时，选中文本和提示词才会直接发送到配置的模型接口。
- 用户输入和模型回答会在本机保存用于多轮会话；选区与剪贴板上下文不会持久化。
- 主动添加的附件会复制到 FloatDude 的 Application Support 目录，并随会话删除。
- 模型只能按当前会话的附件 ID 读取内容，只能在托管 Exports 目录写入 `.md`/`.txt`。
- FloatDude 不包含遥测，也没有项目方运营的服务器。

你仍需自行了解所选模型服务商的数据处理和保留政策。

## 项目结构

```text
Sources/FloatDude/
├── Agent/     会话、软件级 Root、附件和 read/write 工具
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

更多实现细节参见[架构说明](docs/ARCHITECTURE.md)、[研究记录](docs/AGENT_ENGINE_RESEARCH.md)、[界面方向](docs/UI_DIRECTION.md)、[开发交接](docs/DEVELOPMENT_HANDOFF.md)和[质量门槛](docs/QUALITY_GATES.md)。

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

欢迎提交 Issue 和边界清晰的 Pull Request。界面应保持轻量，所有模型能力都必须由 Harness 机械约束。

提交代码前，请运行上述本地验证，并确认改动中不包含 API Key、选中文本或其他隐私内容。

## 作者

FloatDude 由 **Kerye（凯毅）** 构思、设计并开发——[@KkSss999](https://github.com/KkSss999)。

它既是一款开源 macOS 工具，也是一次关于 AI 如何变得原生、短暂且尊重用户当前上下文的产品探索。

## 开源协议

FloatDude 使用 [Apache License 2.0](LICENSE) 开源，作者归属信息参见 [NOTICE](NOTICE)。

除描述项目来源及复现归属声明所必需的合理使用外，该协议不授予 FloatDude 名称和视觉识别的使用权。
