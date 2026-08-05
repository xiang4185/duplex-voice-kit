import XCTest
@testable import XiaomaoApp

final class AuthIntegrationShellTests: XCTestCase {
    func testCredentialsExposeOnlyExplicitAccessState() {
        XCTAssertFalse(AuthCredentials(accessToken: "", refreshToken: nil).hasAccessToken)
        XCTAssertTrue(AuthCredentials(accessToken: "synthetic-token", refreshToken: nil).hasAccessToken)
    }

    func testEmptyCredentialProviderDoesNotCreateCredentials() async throws {
        let provider = EmptyCredentialProvider()
        XCTAssertNil(try await provider.obtainCredentials())
        XCTAssertNil(try await provider.refreshCredentials(
            AuthCredentials(accessToken: "synthetic-token", refreshToken: nil)
        ))
        try await provider.clearCredentials()
    }

    func testEmptyBindingProviderRemainsUnbound() async throws {
        let provider = EmptyDeviceBindingProvider()
        let current = await provider.currentState()
        let bound = try await provider.bind()
        let unbound = try await provider.unbind()
        XCTAssertEqual(current, .unbound)
        XCTAssertEqual(bound, .unbound)
        XCTAssertEqual(unbound, .unbound)
    }
}
