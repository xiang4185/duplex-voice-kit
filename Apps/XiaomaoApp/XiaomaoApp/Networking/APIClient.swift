import Foundation

struct APIClient: Sendable {
    private struct ServerErrorResponse: Decodable {
        let error: String
    }

    private static let allowedServerErrorCodes: Set<String> = [
        "session_mismatch",
        "invalid_session_id",
        "idempotency_conflict"
    ]

    let baseURL: URL
    let tokenStore: AuthTokenStoring
    let deviceID: String
    let session: URLSession

    init(
        baseURL: URL,
        tokenStore: AuthTokenStoring,
        deviceID: String,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.deviceID = deviceID
        self.session = session
    }

    func makeRequest<Input: Encodable>(_ path: String, body: Input) throws -> URLRequest {
        guard let token = tokenStore.load() else { throw AppError.unauthorized }
        let normalizedPath = path.drop(while: { $0 == "/" })
        var request = URLRequest(url: baseURL.appending(path: String(normalizedPath)))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    func post<Input: Encodable, Output: Decodable>(_ path: String, body: Input) async throws -> Output {
        let request = try makeRequest(path, body: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError.networkUnavailable }
        if http.statusCode == 401 { throw AppError.unauthorized }
        guard 200..<300 ~= http.statusCode else {
            let decoded = try? JSONDecoder().decode(ServerErrorResponse.self, from: data)
            let safeCode = decoded.flatMap {
                Self.allowedServerErrorCodes.contains($0.error) ? $0.error : nil
            }
            throw AppError.server(safeCode ?? "http_\(http.statusCode)")
        }
        return try JSONDecoder().decode(Output.self, from: data)
    }
}
