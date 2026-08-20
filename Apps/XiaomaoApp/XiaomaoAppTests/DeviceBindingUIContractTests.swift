import Foundation
import XCTest
@testable import XiaomaoApp

final class DeviceBindingUIContractTests: XCTestCase {
    func testReconfigurePrefillsExistingRuntimeConfigurationAndPreservesStoredToken() throws {
        let source = try bindingSource()

        XCTAssertTrue(source.contains("runtimeConfigurationStore.load()"))
        XCTAssertTrue(source.contains("apiBaseURL = existing.apiBaseURL.absoluteString"))
        XCTAssertTrue(source.contains("voiceWebSocketURL = existing.voiceWebSocketURL.absoluteString"))
        XCTAssertTrue(source.contains("deviceIDInput = existing.deviceID"))
        XCTAssertTrue(source.contains("chatTargetDeviceIDInput = existing.chatTargetDeviceID ?? \"\""))
        XCTAssertTrue(source.contains("tokenStore.load()"))
        XCTAssertTrue(source.contains("访问 Token（留空则保留现有）"))
        XCTAssertTrue(source.contains("hasStoredToken || !normalizedToken.isEmpty"))
        XCTAssertTrue(source.contains("if !normalizedToken.isEmpty"))
        XCTAssertFalse(source.contains("token = tokenStore.load()"),
                       "Existing secret material must never be copied into the visible form state")
    }

    func testBundledConfigurationIsMigratedIntoKeychainBeforeEnvironmentLoads() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("XiaomaoApp/App/AppCoordinator.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("installBundledRuntimeConfigurationIfNeeded()"))
        XCTAssertTrue(source.contains("RUNTIME_CONNECTION_BUNDLE"))
        XCTAssertTrue(source.contains("existing?.chatTargetDeviceID"))
        XCTAssertTrue(source.contains("configurationStore.save(merged)"))
        XCTAssertTrue(source.contains("tokenStore.save(imported.token)"))
    }

    private func bindingSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent("XiaomaoApp/App/DeviceBindingView.swift"),
            encoding: .utf8
        )
    }
}
