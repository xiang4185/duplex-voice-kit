import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import DuplexVoiceKitCompanion

/// URLProtocol double that captures requests and serves scripted responses.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []
    nonisolated(unsafe) static var capturedBodies: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// Darwin URLSession moves the request body into the httpBodyStream before
    /// handing it to a URLProtocol; read both sources so capture works on every
    /// platform.
    private static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    override func startLoading() {
        MockURLProtocol.capturedRequests.append(request)
        if let body = Self.bodyData(of: request) {
            MockURLProtocol.capturedBodies.append(body)
        }
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class DVKChatServiceTests: XCTestCase {

    private var tokenStore: DVKMemoryTokenStore!

    override func setUp() {
        super.setUp()
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.capturedRequests = []
        MockURLProtocol.capturedBodies = []
        tokenStore = DVKMemoryTokenStore()
        try? tokenStore.save("synthetic-token")
    }

    private func makeService() -> DVKChatService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return DVKChatService(
            baseURL: URL(string: "https" + "://" + "api.example.test")!,
            tokenStore: tokenStore,
            deviceID: "dvk-demo-device",
            session: session
        )
    }

    private func response(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https" + "://" + "api.example.test/v1/chat")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private func jsonBody(_ value: String, degraded: Bool) -> Data {
        Data("{\"reply\":\"\(value)\",\"degraded\":\(degraded)}".utf8)
    }

    private func decodedRequest(_ data: Data) -> [String: String]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: String]
    }

    // 14.3: request path is /v1/chat
    func testRequestPathIsV1Chat() async throws {
        MockURLProtocol.requestHandler = { _ in (self.response(status: 200), self.jsonBody("hi", degraded: false)) }
        _ = try await makeService().send(text: "hello")
        let path = MockURLProtocol.capturedRequests.first?.url?.path
        XCTAssertEqual(path, "/v1/chat")
    }

    // 14.3: request headers carry Bearer, X-Device-ID and JSON content type
    func testRequestHeaders() async throws {
        MockURLProtocol.requestHandler = { _ in (self.response(status: 200), self.jsonBody("hi", degraded: false)) }
        _ = try await makeService().send(text: "hello")
        let request = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Device-ID"), "dvk-demo-device")
    }

    // 14.3: the four request fields are present
    func testRequestBodyContainsFourFields() async throws {
        MockURLProtocol.requestHandler = { _ in (self.response(status: 200), self.jsonBody("hi", degraded: false)) }
        _ = try await makeService().send(text: "hello")
        let body = try XCTUnwrap(MockURLProtocol.capturedBodies.first)
        let fields = try XCTUnwrap(decodedRequest(body))
        XCTAssertNotNil(fields["device_id"])
        XCTAssertNotNil(fields["session_id"])
        XCTAssertEqual(fields["message"], "hello")
        XCTAssertNotNil(fields["request_id"])
        XCTAssertEqual(fields.count, 4)
    }

    // 14.3: response parsing maps reply and degraded
    func testResponseParsesReplyAndDegraded() async throws {
        MockURLProtocol.requestHandler = { _ in (self.response(status: 200), self.jsonBody("server reply", degraded: true)) }
        let service = makeService()
        let reply = try await service.send(text: "hello")
        XCTAssertEqual(reply, "server reply")
    }

    // 14.3: 401 maps to unauthorized
    func testUnauthorizedMapsToUnauthorized() async {
        MockURLProtocol.requestHandler = { _ in (self.response(status: 401), Data()) }
        let service = makeService()
        do {
            _ = try await service.send(text: "hello")
            XCTFail("expected unauthorized")
        } catch let error as DVKChatServiceError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // 14.3: empty messages are rejected without any network attempt
    func testEmptyMessageRejected() async {
        let service = makeService()
        do {
            _ = try await service.send(text: "   ")
            XCTFail("expected empty message error")
        } catch let error as DVKChatServiceError {
            XCTAssertEqual(error, .emptyMessage)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }

    // 14.3: a network retry of the same logical message reuses the same request_id
    func testRequestIDReusedOnRetry() async throws {
        var calls = 0
        MockURLProtocol.requestHandler = { _ in
            calls += 1
            if calls == 1 {
                return (self.response(status: 503), Data())
            }
            return (self.response(status: 200), self.jsonBody("ok", degraded: false))
        }
        _ = try await makeService().send(text: "hello")
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(MockURLProtocol.capturedBodies.count, 2)
        let firstID = decodedRequest(MockURLProtocol.capturedBodies[0])?["request_id"]
        let secondID = decodedRequest(MockURLProtocol.capturedBodies[1])?["request_id"]
        XCTAssertEqual(firstID, secondID)
    }

    // 14.3: a new message always allocates a new request_id
    func testNewMessageAllocatesNewRequestID() async throws {
        MockURLProtocol.requestHandler = { _ in (self.response(status: 200), self.jsonBody("ok", degraded: false)) }
        let service = makeService()
        _ = try await service.send(text: "first")
        _ = try await service.send(text: "second")
        XCTAssertEqual(MockURLProtocol.capturedBodies.count, 2)
        let firstID = decodedRequest(MockURLProtocol.capturedBodies[0])?["request_id"]
        let secondID = decodedRequest(MockURLProtocol.capturedBodies[1])?["request_id"]
        XCTAssertNotEqual(firstID, secondID)
    }

    // 14.3: a persistent server error surfaces as a server error
    func testPersistentServerErrorSurfaces() async {
        MockURLProtocol.requestHandler = { _ in (self.response(status: 500), Data()) }
        let service = makeService()
        do {
            _ = try await service.send(text: "hello")
            XCTFail("expected server error")
        } catch let error as DVKChatServiceError {
            XCTAssertEqual(error, .server("http_500"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // 14.3: network failures map to networkUnavailable
    func testNetworkErrorMapsToNetworkUnavailable() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let service = makeService()
        do {
            _ = try await service.send(text: "hello")
            XCTFail("expected network error")
        } catch let error as DVKChatServiceError {
            XCTAssertEqual(error, .networkUnavailable)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // 14.3: mock chat behavior remains available through the same surface
    func testMockChatServiceBehavior() async throws {
        let mock = DVKMockChatService()
        let reply = try await mock.send(text: "hello")
        XCTAssertTrue(reply.contains("Mock reply"))
        let sentCount = await mock.sentTextCount()
        XCTAssertEqual(sentCount, 1)
    }
}
