import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Provider-neutral errors surfaced by the backend client.
public enum DVKBackendError: Error, Equatable, Sendable {
    case unauthorized
    case networkUnavailable
    case invalidConfiguration
    case server(String)
    case invalidResponse
}

/// Minimal POST client for the neutral chat contract.
///
/// Never logs the message body, the token, or the Authorization header.
public struct DVKBackendClient: Sendable {
    public let baseURL: URL
    public let deviceID: String
    public let session: URLSession
    private let tokenStore: any DVKTokenStoring

    public init(
        baseURL: URL,
        tokenStore: any DVKTokenStoring,
        deviceID: String,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.deviceID = deviceID
        self.session = session
    }

    /// Builds a POST request with the frozen neutral contract:
    /// Content-Type, Authorization Bearer, and X-Device-ID headers.
    public func makeRequest<Input: Encodable>(path: String, body: Input) throws -> URLRequest {
        guard let token = tokenStore.load(), !token.isEmpty else {
            throw DVKBackendError.unauthorized
        }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    public func post<Input: Encodable, Output: Decodable>(
        path: String,
        body: Input
    ) async throws -> Output {
        let request = try makeRequest(path: path, body: body)
        let (data, response) = try await performData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DVKBackendError.networkUnavailable
        }
        if http.statusCode == 401 { throw DVKBackendError.unauthorized }
        guard 200..<300 ~= http.statusCode else {
            throw DVKBackendError.server("http_\(http.statusCode)")
        }
        return try JSONDecoder().decode(Output.self, from: data)
    }

    /// Cross-platform async data task wrapper. Linux FoundationNetworking does
    /// not expose the Darwin async `URLSession.data(for:)` API.
    private func performData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: DVKBackendError.networkUnavailable)
                }
            }
            .resume()
        }
    }
}
