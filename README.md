# DuplexVoiceKit

[![CI](https://github.com/xiang4185/duplex-voice-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/xiang4185/duplex-voice-kit/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

A provider-neutral realtime voice framework for iOS.

面向 iOS 的实时双向语音交互核心。

## 项目定位

DuplexVoiceKit Core Target is the provider-neutral realtime voice core. Core contains no product UI; the optional DuplexVoiceKitUI Target provides public SwiftUI components and the Showcase.

DVK 不绑定具体 Provider。宿主应用负责注入 Provider transport、认证材料和服务端协议映射，并决定如何把会话状态、音频振幅和诊断信息接入自己的产品层。

本项目来源于实际实时语音 App 中经过运行验证的通用核心提取，并在公开边界内保留关键并发、上传顺序、音频图恢复和隐私诊断语义。

## 当前能力

- 单一全双工 `AVAudioEngine`
- 实时音频采集与播放
- `AVAudioSession` 的 `playAndRecord` / `voiceChat` 配置
- 蓝牙与扬声器路由
- 串行音频上传
- bounded queue 与 backpressure
- `chunk_index` 连续性
- connection generation 与 capture generation
- stale packet 丢弃与 partial PCM 清理
- VAD、自动 commit 与 interrupt
- `responseID` 过滤与 server sequence 过滤
- reconnect policy
- 音频中断恢复、Media Services Reset 恢复与音频图重建
- 不包含正文、Token 或原始音频的隐私安全诊断

## 系统要求

- iOS 17+
- Swift 5.10+
- Xcode 15.3，或兼容 Swift 5.10 与 iOS 17 SDK 的更高版本
- Swift Package Manager

## Swift Package Manager 接入

在 `Package.swift` 中添加：

```swift
dependencies: [
    .package(
        url: "https://github.com/xiang4185/duplex-voice-kit.git",
        branch: "main"
    )
]
```

然后将产品添加到目标依赖：

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "DuplexVoiceKit", package: "duplex-voice-kit")
    ]
)
```

代码中导入模块：

```swift
import DuplexVoiceKit
```

当前仓库尚未创建版本 Tag，因此示例使用 `main` 分支。生产项目应在后续正式版本发布后固定到明确版本范围。

## Provider 接入边界

宿主应用可以通过 `DVKTransport` 提供完整连接生命周期，也可以在保留现有 WebSocket 生命周期时仅实现 `DVKOutboundTransport`：

```swift
public protocol DVKOutboundTransport: Sendable {
    func send(_ message: DVKOutboundMessage) async throws
}

public protocol DVKTransport: DVKOutboundTransport {
    func connect() async throws
    func events() -> AsyncStream<DVKInboundEvent>
    func disconnect() async
}
```

Provider adapter 应在宿主项目中完成：

1. 获取和刷新认证信息。
2. 建立具体 Provider 的 WebSocket 或其他实时连接。
3. 将 Provider 入站协议映射为 `DVKInboundEvent`。
4. 将 `DVKOutboundMessage` 映射为 Provider 出站协议。
5. 对认证失败、限流和网络错误进行分类。

DVK 本身不保存 Provider Token、不包含生产域名，也不依赖任何 Provider SDK。

详见 [Provider integration](docs/provider-integration.md)。

## Backend requirements

DuplexVoiceKit 是 iOS 客户端实时语音核心，本仓库**不包含可直接运行的语音后端**。宿主应用需要提供兼容的 `DVKTransport`，或使用 `DVKOutboundTransport` 把上传管线接入现有连接，也可以连接兼容的 Voice Gateway。

兼容 Gateway 通常负责：

- 客户端鉴权与授权；
- Provider 连接与凭据保管；
- Provider 事件和协议字段映射；
- server-push 音频下发；
- Provider 特有协议转换、限流和错误分类。

Provider Key 不应下发到 iOS App。未来计划提供独立关联项目 `duplex-voice-gateway`；该仓库尚未创建，因此当前不添加链接。

详见 [Backend requirements](docs/backend-requirements.md)。

## 架构概览

```text
Host App / Product UI
        │
        ├── Authentication and product configuration
        │
Provider Adapter implementing DVKTransport
        │
DuplexVoiceKit core
        ├── Session and response filtering
        ├── VAD / commit / interrupt
        ├── Serial upload and generation checks
        └── Privacy-safe diagnostics
        │
iOS AVAudioSession + full-duplex AVAudioEngine
```

更完整的模块边界和数据流见 [Architecture](docs/architecture.md)。

## Live2D 边界

DVK 不依赖、渲染或管理 Live2D。宿主应用可以通过状态事件和 `DVKPlaybackAmplitudeSink` 驱动角色表现，但模型资产、渲染生命周期、动作映射和 UI 均位于 Package 之外。

详见 [Live2D boundary](docs/live2d-boundary.md)。

## 安全与隐私

- 不要把 Provider Token、私钥、真实音频或聊天正文提交到仓库。
- 认证材料应由宿主应用或服务端安全注入。
- DVK 诊断结构只记录顺序、计数、状态、短 hash 和健康信息。
- 公共 issue、日志和 CI 输出不得包含用户内容或生产凭据。

详见 [Security and privacy](docs/security-and-privacy.md) 与 [SECURITY.md](SECURITY.md)。

## 本地验证

```bash
python3 Scripts/static_check.py
swift test
swift test -c release
```

公共 CI 还会在 GitHub 托管的 macOS runner 上选择可用 iPhone Simulator，并执行真实 iOS Simulator 测试。

## 当前限制

- 不包含任何具体语音 Provider 实现。
- 不包含认证服务、Voice Gateway 或服务端部署方案。
- Core Target contains no product UI; the optional DuplexVoiceKitUI Target provides public components and the Showcase. The complete runnable application is kept separately under `Apps/XiaomaoApp` and consumes Core through a local package dependency.
- 不包含 Live2D SDK、第三方模型或来源不明的字体与人物资产。
- 尚未发布稳定版本 Tag 或 Release。

## 参与贡献

提交变更前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。架构或公共 API 变更应保持 Provider-neutral，并为关键行为补充测试。

## License

Apache License 2.0。详见 [LICENSE](LICENSE)。

## Public Companion Showcase R2

The public Companion layer is an optional, Foundation-only state and mock layer. The optional SwiftUI UI renders that Store without creating a second business state. The Showcase app is local-only: it does not include authentication, production provider adapters, a Voice Gateway, real chat, real audio, persistent reviews, private character assets, or credentials.

The R2 public experience includes text success/failure/retry, deterministic voice state progression, allowed/limited privacy callbacks, five public cards, in-memory review generation/list/detail/delete, a deterministic assistant playback energy view, programmatic startup, Dynamic Type, VoiceOver identifiers, and Reduce Motion-safe rendering.

## Public Companion Showcase R3A

The R3A Showcase expands the optional public layer into four fictional mock cats: Mellow, Sunny, Sage, and Luna. It provides Home, Cats, Conversation, Reviews, Settings, a deterministic Mock Lab, a horizontal snapping profile carousel, accessibility identifiers, Dynamic Type, dark mode, VoiceOver, and Reduce Motion paths.

The public route boundary carries a selected public profile ID into an opaque host-resolved route token. The token is never shown or written to reviews. The public repository contains no real persona ID, private prompt, production address, or credential.

## Single-source Xiaomao app

`Apps/XiaomaoApp` is the complete iOS application target, including the current chat tab, offline small-things tab, voice UI, Widget, tests, and unsigned IPA packaging. It consumes this checkout through `path: ../..`; no second DVK copy or pinned remote revision is used.

The committed Release configuration contains empty endpoint and device values. Debug uses loopback-only endpoints and offline mock voice. Runtime credentials are entered by the user and stored in Keychain, while CI may receive non-secret endpoint and device values only as manual workflow inputs. See [`Apps/XiaomaoApp/README.md`](Apps/XiaomaoApp/README.md).
