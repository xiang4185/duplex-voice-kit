import XCTest
import DuplexVoiceKitCompanion

struct ExternalRouteResolver: DVKCompanionProfileRouteResolving {
    func resolve(publicProfileID: String) async throws -> DVKCompanionRouteToken {
        DVKCompanionRouteToken(opaqueValue: "external-route")
    }
}
struct ExternalChatService: DVKChatServicing {
    func send(text: String) async throws -> String { "external" }
    func send(text: String, context: DVKCompanionSessionContext) async throws -> String {
        _ = context.routeToken.value
        return "external"
    }
}
struct ExternalVoiceService: DVKVoiceServicing {
    func connect(context: DVKCompanionSessionContext) async throws { _ = context.profile.publicID; _ = context.routeToken.value }
}

final class DVKCompanionPublicAPIContractTests: XCTestCase {
    func testExternalHostCanReadContextRouteTokenAndImplementServices() async throws {
        let profile = DVKCompanionProfileCatalog().profiles[0].snapshot
        let token = DVKCompanionRouteToken(opaqueValue: "host-token")
        let context = DVKCompanionSessionContext(profile: profile, routeToken: token)
        XCTAssertEqual(context.routeToken.value, "host-token")
        let resolver = ExternalRouteResolver()
        let resolved = try await resolver.resolve(publicProfileID: profile.publicID)
        XCTAssertEqual(resolved.value, "external-route")
        _ = try await ExternalChatService().send(text: "hello", context: context)
        try await ExternalVoiceService().connect(context: context)
    }
}
