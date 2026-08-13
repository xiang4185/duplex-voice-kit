import Foundation
import XCTest
@testable import XiaomaoApp

@MainActor
final class CompanionModeTests: XCTestCase {
    func testCompanionTypesUseOnlyPublicStableIdentifiersAndVisualModes() {
        XCTAssertEqual(
            CompanionType.allCases.map(\.rawValue),
            ["warm", "assertive", "romantic", "mystery"]
        )
        XCTAssertEqual(CompanionType.warm.visualMode, .warm)
        XCTAssertEqual(CompanionType.assertive.visualMode, .warm)
        XCTAssertEqual(CompanionType.romantic.visualMode, .warm)
        XCTAssertEqual(CompanionType.mystery.visualMode, .mystery)
        XCTAssertEqual(CompanionType.warm.portraitAssetName, "Character")
        XCTAssertEqual(CompanionType.warm.thumbnailAssetName, "CharacterAvatar")
        XCTAssertEqual(CompanionType.assertive.portraitAssetName, "CompanionAssertive")
        XCTAssertEqual(CompanionType.romantic.portraitAssetName, "CompanionRomantic")
        XCTAssertEqual(CompanionType.mystery.portraitAssetName, "CompanionMystery")
        XCTAssertNil(CompanionType.warm.sceneBackgroundAssetName)
        XCTAssertEqual(CompanionType.assertive.sceneBackgroundAssetName, "CompanionAssertiveBackground")
        XCTAssertEqual(CompanionType.romantic.sceneBackgroundAssetName, "CompanionRomanticBackground")
        XCTAssertEqual(CompanionType.mystery.sceneBackgroundAssetName, "CompanionMysteryBackground")
    }

    func testPublicSampleCompanionPortraitAssetsExist() throws {
        let appRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let assetsRoot = appRoot.appendingPathComponent("XiaomaoApp/Resources/Assets.xcassets")

        for path in [
            "CompanionAssertive.imageset/companion-assertive.png",
            "CompanionRomantic.imageset/companion-romantic.png",
            "CompanionMystery.imageset/companion-mystery.png",
            "CompanionAssertiveBackground.imageset/companion-assertive-background.png",
            "CompanionRomanticBackground.imageset/companion-romantic-background.png",
            "CompanionMysteryBackground.imageset/companion-mystery-background.png"
        ] {
            let url = assetsRoot.appendingPathComponent(path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing public sample asset: \(path)")
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            XCTAssertGreaterThan(values.fileSize ?? 0, 1_024, "Sample asset must contain a real portrait image")
        }
    }

    func testCompanionSelectionPersistsAndRestoresMysteryMode() {
        let suite = "CompanionModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = CompanionModeStore(defaults: defaults)
        XCTAssertEqual(first.current, .warm)
        first.select(.mystery)
        XCTAssertEqual(first.current, .mystery)
        XCTAssertEqual(first.visualMode, .mystery)

        let restored = CompanionModeStore(defaults: defaults)
        XCTAssertEqual(restored.current, .mystery)
        XCTAssertEqual(restored.visualMode, .mystery)

        restored.select(.romantic)
        XCTAssertEqual(restored.visualMode, .warm)
    }

    func testMockCompanionSwitchEndsAndRebuildsSessionWithoutLeavingCall() async {
        let suite = "CompanionModeTests.Mock.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = CompanionModeStore(defaults: defaults)
        let socket = MockVoiceAdapter()
        let environment = AppEnvironment(
            apiBaseURL: nil,
            voiceWebSocketURL: nil,
            deviceID: "",
            appEnvironment: "test",
            enableMockVoice: true,
            enableMemory: false,
            defaultVoiceRoute: .b,
            appBuildSHA: "",
            appBuildTime: "",
            requestedHostAdapterMode: .mock,
            hostAdapters: .mock
        )
        let controller = VoiceSessionController(
            environment: environment,
            socket: socket,
            capture: MockAudioCapture(),
            playback: MockAudioPlayback(),
            audioSession: MockAudioSessionController(),
            networkMonitor: MockNetworkMonitor()
        )
        let viewModel = VoiceCallViewModel(controller: controller, companionStore: store)

        await controller.startNewCall()
        XCTAssertEqual(controller.state, .ready)
        for type in [CompanionType.assertive, .romantic, .mystery, .warm] {
            let previousSessionID = controller.sessionIDForTesting
            let before = await socket.snapshot()

            await viewModel.switchCompanion(to: type)

            let after = await socket.snapshot()
            XCTAssertEqual(store.current, type)
            XCTAssertEqual(store.visualMode, type.visualMode)
            XCTAssertTrue(controller.callIsActive)
            XCTAssertEqual(controller.state, .ready)
            XCTAssertTrue(controller.isRecording)
            XCTAssertNotEqual(controller.sessionIDForTesting, previousSessionID)
            XCTAssertGreaterThan(after.connectCallCount, before.connectCallCount)
            XCTAssertGreaterThan(after.disconnectCallCount, before.disconnectCallCount)
            XCTAssertFalse(viewModel.isSwitchingCompanion)
        }

        await controller.endCurrentCall()
    }

    func testCompanionUIAndSessionPayloadKeepPublicBoundary() throws {
        let call = try source("XiaomaoApp/Call/VoiceCallView.swift")
        let uploader = try source("XiaomaoApp/Voice/AudioUploadActor.swift")
        let store = try source("XiaomaoApp/Design/CompanionModeStore.swift")
        let theme = try source("XiaomaoApp/Design/Theme.swift")
        let root = try source("XiaomaoApp/App/XiaomaoApp.swift")
        let tabs = try source("XiaomaoApp/App/MainTabView.swift")
        let home = try source("XiaomaoApp/App/CompanionHomeView.swift")
        let components = try source("XiaomaoApp/Design/Components/VisualComponents.swift")

        XCTAssertTrue(call.contains("var identifierPrefix: String = \"call.companion\""))
        XCTAssertTrue(call.contains("\\(identifierPrefix).\\(type.rawValue)"))
        XCTAssertTrue(call.contains("正在切换陪伴方式…"))
        XCTAssertTrue(uploader.contains("\"companion_type\": .string(companionTypeID)"))
        XCTAssertTrue(theme.contains("static func visual(_ mode: AppVisualMode) -> VisualTokens"))
        XCTAssertTrue(theme.contains("case .mystery:"))
        XCTAssertTrue(root.contains(".environment(\\.appVisualMode, companionStore.visualMode)"))
        XCTAssertTrue(root.contains(".environment(\\.companionType, companionStore.current)"))
        XCTAssertTrue(root.contains(".preferredColorScheme(companionStore.visualMode == .mystery ? .dark : .light)"))
        XCTAssertTrue(tabs.contains("toolbarColorScheme(visualMode == .mystery ? .dark : .light"))
        XCTAssertTrue(theme.contains("let dangerSoft: Color"))
        XCTAssertTrue(call.contains("Color(uiColor: .systemRed)"),
                      "挂断按钮必须保持与 iOS 电话一致的系统危险红色")
        XCTAssertTrue(call.contains("visual.glassTint"))
        XCTAssertTrue(home.contains("sceneBackgroundAssetName"))
        XCTAssertTrue(call.contains("sceneBackgroundAssetName"))
        XCTAssertTrue(home.contains("Image(assetName)"))
        XCTAssertTrue(call.contains("Image(assetName)"))
        XCTAssertTrue(components.contains("visualMode == .mystery ? tokens.primarySoft : tokens.primary"))
        XCTAssertTrue(call.contains("Image(type.thumbnailAssetName)"))

        for label in ["温柔陪伴", "强势偏爱", "黏人浪漫", "未知", "尚未被定义"] {
            XCTAssertTrue(store.contains(label))
        }
        for forbidden in ["persona_prompt", "system_prompt", "voice_profile", "provider_prompt"] {
            XCTAssertFalse(store.lowercased().contains(forbidden))
            XCTAssertFalse(uploader.lowercased().contains(forbidden))
        }
    }

    func testPublicCoreDoesNotContainXiaomaoCompanionTypes() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let coreRoot = repositoryRoot.appendingPathComponent("Sources/DuplexVoiceKit")
        let files = try FileManager.default.contentsOfDirectory(
            at: coreRoot,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        let core = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")

        XCTAssertFalse(core.contains("CompanionType"))
        XCTAssertFalse(core.contains("CompanionModeStore"))
        XCTAssertFalse(core.contains("温柔陪伴"))
        XCTAssertFalse(core.contains("强势偏爱"))
        XCTAssertFalse(core.contains("黏人浪漫"))
    }

    private func source(_ relativePath: String) throws -> String {
        let appRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: appRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
