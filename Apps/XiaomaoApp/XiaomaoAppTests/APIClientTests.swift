import Foundation
import XCTest
@testable import XiaomaoApp

final class APIClientTests: XCTestCase {
    private struct Body: Encodable { let value: String }

    func testRequestIncludesBearerTokenAndMatchingDeviceHeader() throws {
        let tokenStore = MemoryAuthTokenStore()
        try tokenStore.save("synthetic-unit-token")
        let client = APIClient(
            baseURL: try XCTUnwrap(URL(string: "https://example.invalid")),
            tokenStore: tokenStore,
            deviceID: "synthetic-device"
        )

        let request = try client.makeRequest("v1/chat", body: Body(value: "synthetic"))

        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer synthetic-unit-token"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Device-ID"), "synthetic-device")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testChatServiceUsesAlphaSendOnlyContractAndLocalHistoryClear() async throws {
        let captured = CapturedRequests()
        let client = try makeStubbedClient { request in
            captured.append(request)
            XCTAssertEqual(request.url?.path, "/v1/chat")
            let data = Data(#"""
            {
                "trace_id":"opaque-trace-send",
                "session_id":"server-session",
                "reply":"合成回复",
                "route":"direct",
                "degraded":false
            }
            """#.utf8)
            return try Self.response(for: request, statusCode: 200, data: data)
        }
        let credentials = KeychainCredentialProviderAdapter(tokenStore: client.tokenStore)
        let deviceBinding = InjectedDeviceBindingProviderAdapter(deviceID: client.deviceID)
        let backend = try ProductionBackendAdapter(
            baseURL: client.baseURL,
            credentials: credentials,
            deviceBinding: deviceBinding,
            session: client.session
        )
        let service = ChatService(backend: backend)

        let history = try await service.loadHistory()
        let sent = try await service.send(
            message: "合成发送",
            sessionID: history.sessionID,
            requestID: "opaque-send-request"
        )
        let cleared = try await service.clear(
            sessionID: history.sessionID,
            requestID: "opaque-clear-request"
        )

        XCTAssertTrue(history.messages.isEmpty)
        XCTAssertFalse(history.sessionID.isEmpty)
        XCTAssertEqual(sent.sessionID, "server-session")
        XCTAssertEqual(sent.userMessage.content, "合成发送")
        XCTAssertEqual(sent.assistantMessage.content, "合成回复")
        XCTAssertEqual(cleared.sessionID, history.sessionID)
        XCTAssertTrue(cleared.cleared)

        let requests = captured.values
        XCTAssertEqual(requests.map { $0.url?.path }, ["/v1/chat"])
        for request in requests {
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer synthetic-unit-token"
            )
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "X-Device-ID"),
                "synthetic-device"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        }

        let sendBody = try jsonBody(try XCTUnwrap(requests.first))
        XCTAssertEqual(sendBody["device_id"] as? String, "synthetic-device")
        XCTAssertEqual(sendBody["session_id"] as? String, history.sessionID)
        XCTAssertEqual(sendBody["request_id"] as? String, "opaque-send-request")
        XCTAssertEqual(sendBody["message"] as? String, "合成发送")
    }

    func testNon2xxResponseIsNotDecodedAsSuccess() async throws {
        let client = try makeStubbedClient { request in
            try Self.response(
                for: request,
                statusCode: 503,
                data: Data(#"{"session_id":"must-not-decode","messages":[]}"#.utf8)
            )
        }

        do {
            let _: SyntheticResponse = try await client.post(
                "/v1/chat/history",
                body: Body(value: "synthetic")
            )
            XCTFail("Expected non-2xx response to fail")
        } catch let error as AppError {
            XCTAssertEqual(error, .server("http_503"))
        }
    }

    func testSessionMismatchErrorCodeIsDecodedFrom409() async throws {
        let client = try makeStubbedClient { request in
            try Self.response(
                for: request,
                statusCode: 409,
                data: Data(#"{"error":"session_mismatch"}"#.utf8)
            )
        }

        do {
            let _: SyntheticResponse = try await client.post(
                "/v1/chat",
                body: Body(value: "synthetic")
            )
            XCTFail("Expected session mismatch response to fail")
        } catch let error as AppError {
            XCTAssertEqual(error, .server("session_mismatch"))
        }
    }

    func testInvalidErrorJSONFallsBackToHTTPStatusCode() async throws {
        let client = try makeStubbedClient { request in
            try Self.response(
                for: request,
                statusCode: 409,
                data: Data(#"{"detail":"synthetic-error"}"#.utf8)
            )
        }

        do {
            let _: SyntheticResponse = try await client.post(
                "/v1/chat",
                body: Body(value: "synthetic")
            )
            XCTFail("Expected invalid error payload to fail")
        } catch let error as AppError {
            XCTAssertEqual(error, .server("http_409"))
        }
    }

    func testJSONBodyReadsHTTPBodyStream() throws {
        let expectedData = Data(#"{"device_id":"synthetic-device"}"#.utf8)
        var request = URLRequest(
            url: try XCTUnwrap(URL(string: "https://example.invalid/v1/chat/history"))
        )
        request.httpBodyStream = InputStream(data: expectedData)

        let body = try jsonBody(request)

        XCTAssertEqual(body["device_id"] as? String, "synthetic-device")
    }

    private struct SyntheticResponse: Decodable {
        let value: String
    }

    private func makeStubbedClient(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) throws -> APIClient {
        URLProtocolStubState.shared.setHandler(handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let tokenStore = MemoryAuthTokenStore()
        try tokenStore.save("synthetic-unit-token")
        return APIClient(
            baseURL: try XCTUnwrap(URL(string: "https://example.invalid")),
            tokenStore: tokenStore,
            deviceID: "synthetic-device",
            session: URLSession(configuration: configuration)
        )
    }

    private func syntheticEnvironment() -> AppEnvironment {
        AppEnvironment(
            apiBaseURL: URL(string: "https://example.invalid"),
            voiceWebSocketURL: nil,
            deviceID: "synthetic-device",
            appEnvironment: "unit-test",
            enableMockVoice: false,
            enableMemory: false,
            defaultVoiceRoute: .b,
            appBuildSHA: "synthetic-sha",
            appBuildTime: "synthetic-time"
        )
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let httpBody = request.httpBody {
            data = httpBody
        } else if let stream = request.httpBodyStream {
            data = try readBodyStream(stream)
        } else {
            throw RequestBodyReadError.missingBody
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func readBodyStream(_ stream: InputStream) throws -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while true {
            let readCount = stream.read(&buffer, maxLength: buffer.count)
            if readCount > 0 {
                data.append(contentsOf: buffer.prefix(readCount))
            } else if readCount == 0 {
                return data
            } else {
                throw stream.streamError ?? RequestBodyReadError.streamReadFailed
            }
        }
    }

    private static func response(
        for request: URLRequest,
        statusCode: Int,
        data: Data
    ) throws -> (HTTPURLResponse, Data) {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(request.url),
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
        return (response, data)
    }
}

private enum RequestBodyReadError: Error {
    case missingBody
    case streamReadFailed
}

private final class CapturedRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        lock.lock()
        requests.append(request)
        lock.unlock()
    }

    var values: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}

private final class URLProtocolStubState: @unchecked Sendable {
    static let shared = URLProtocolStubState()

    private let lock = NSLock()
    private var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    func setHandler(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        guard let handler else { throw URLProtocolStubError.missingHandler }
        return try handler(request)
    }
}

private enum URLProtocolStubError: Error {
    case missingHandler
}

private final class URLProtocolStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try URLProtocolStubState.shared.response(for: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
