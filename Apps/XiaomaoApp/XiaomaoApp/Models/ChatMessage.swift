import Foundation

struct ChatMessage: Identifiable, Equatable, Sendable, Decodable {
    enum Role: String, Equatable, Sendable, Decodable {
        case user
        case assistant
    }

    let id: String
    let role: Role
    let content: String
    let createdAt: Date

    var text: String { content }

    init(id: String, role: Role, content: String, createdAt: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        let timestamp = try container.decode(String.self, forKey: .createdAt)
        guard let parsedDate = Self.parseUTCISO8601(timestamp) else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt,
                in: container,
                debugDescription: "created_at must be an ISO 8601 UTC timestamp"
            )
        }
        createdAt = parsedDate
    }

    private static func parseUTCISO8601(_ value: String) -> Date? {
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: value) {
            return date
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }
}
