import XCTest
@testable import DuplexVoiceKitCompanion

final class DVKTokenStoreTests: XCTestCase {

    // 14.2: memory store round trip
    func testMemoryStoreRoundTrip() throws {
        let store = DVKMemoryTokenStore()
        XCTAssertNil(store.load())
        try store.save("synthetic-token")
        XCTAssertEqual(store.load(), "synthetic-token")
    }

    // 14.2: memory store clear behavior
    func testMemoryStoreClear() throws {
        let store = DVKMemoryTokenStore()
        try store.save("synthetic-token")
        try store.clear()
        XCTAssertNil(store.load())
    }

    // 14.2: saving again overwrites
    func testMemoryStoreOverwrites() throws {
        let store = DVKMemoryTokenStore()
        try store.save("unit-token")
        try store.save("synthetic-token")
        XCTAssertEqual(store.load(), "synthetic-token")
    }

    // 14.2: the protocol is constructible with the memory implementation
    func testTokenStoringProtocolConstructible() throws {
        let store: any DVKTokenStoring = DVKMemoryTokenStore()
        try store.save("synthetic-token")
        XCTAssertEqual(store.load(), "synthetic-token")
        try store.clear()
        XCTAssertNil(store.load())
    }

    #if canImport(Security)
    // 14.2: the Keychain implementation exists and conforms to the protocol.
    // Simulator unit test bundles have no keychain entitlement, so the test is
    // skipped there and fully asserts on macOS hosts and real devices.
    func testKeychainStoreConstructible() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Keychain entitlement is unavailable in this simulator test bundle.")
        #else
        let store: any DVKTokenStoring = DVKKeychainTokenStore()
        try store.save("synthetic-token")
        XCTAssertEqual(store.load(), "synthetic-token")
        try store.clear()
        XCTAssertNil(store.load())
        #endif
    }
    #endif

    // 14.2: no token appears in configuration status or diagnostics strings
    func testTokenIsNotExposedInStatusText() throws {
        let store = DVKMemoryTokenStore()
        try store.save("synthetic-token")
        let configuration = DVKRuntimeConfiguration(
            apiBaseURL: URL(string: "https" + "://" + "api.example.test/v1"),
            voiceWebSocketURL: URL(string: "wss" + "://" + "voice.example.test/v1/voice/ws"),
            deviceID: "dvk-demo-device"
        )
        XCTAssertFalse(configuration.statusDescription.contains("synthetic-token"))
        XCTAssertFalse(String(describing: store).contains("synthetic-token"))
    }

    // 14.2: the backend request never places the token in the URL
    func testTokenIsNotPlacedInRequestURL() throws {
        let store = DVKMemoryTokenStore()
        try store.save("synthetic-token")
        let client = DVKBackendClient(
            baseURL: URL(string: "https" + "://" + "api.example.test/v1")!,
            tokenStore: store,
            deviceID: "dvk-demo-device"
        )
        struct Body: Encodable { let value = "hello" }
        let request = try client.makeRequest(path: "v1/chat", body: Body())
        let url = request.url?.absoluteString ?? ""
        XCTAssertFalse(url.contains("synthetic-token"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Device-ID"), "dvk-demo-device")
    }
}
