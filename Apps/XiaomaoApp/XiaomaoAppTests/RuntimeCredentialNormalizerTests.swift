import XCTest
@testable import XiaomaoApp

final class RuntimeCredentialNormalizerTests: XCTestCase {
    func testTokenTrimsWhitespaceAndBearerPrefix() {
        XCTAssertEqual(
            RuntimeCredentialNormalizer.token("  Bearer synthetic-token\n"),
            "synthetic-token"
        )
        XCTAssertEqual(
            RuntimeCredentialNormalizer.token("\n synthetic-token \t"),
            "synthetic-token"
        )
    }

    func testDeviceIDTrimsWhitespaceAndNewlines() {
        XCTAssertEqual(
            RuntimeCredentialNormalizer.deviceID("  synthetic-device\n"),
            "synthetic-device"
        )
    }
}
