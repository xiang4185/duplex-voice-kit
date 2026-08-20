import SwiftUI
import UIKit

struct ChatAvatarProfile: Equatable, Sendable {
    let participant: ChatParticipant
    let mimeType: String
    let imageData: Data
}

actor ChatAvatarService {
    private struct StateRequest: Encodable {
        let targetDeviceID: String?

        private enum CodingKeys: String, CodingKey {
            case targetDeviceID = "target_device_id"
        }
    }

    private struct UpdateRequest: Encodable {
        let targetDeviceID: String?
        let mimeType: String
        let imageData: Data

        private enum CodingKeys: String, CodingKey {
            case targetDeviceID = "target_device_id"
            case mimeType = "mime_type"
            case imageData = "data_base64"
        }
    }

    private struct ServerAvatar: Decodable {
        let participant: ChatParticipant
        let mimeType: String
        let imageData: Data

        private enum CodingKeys: String, CodingKey {
            case participant
            case mimeType = "mime_type"
            case imageData = "data_base64"
        }

        var profile: ChatAvatarProfile {
            ChatAvatarProfile(
                participant: participant,
                mimeType: mimeType,
                imageData: imageData
            )
        }
    }

    private struct StateResponse: Decodable { let avatars: [ServerAvatar] }
    private struct UpdateResponse: Decodable { let avatar: ServerAvatar }

    private let backend: any BackendAdapter
    private let targetDeviceID: String?

    init(backend: any BackendAdapter, targetDeviceID: String?) {
        self.backend = backend
        self.targetDeviceID = targetDeviceID
    }

    func load() async throws -> [ChatAvatarProfile] {
        let response: StateResponse = try await execute(
            route: "/v1/chat/avatars",
            body: StateRequest(targetDeviceID: targetDeviceID)
        )
        return response.avatars.map(\.profile)
    }

    func update(imageData: Data, mimeType: String) async throws -> ChatAvatarProfile {
        let response: UpdateResponse = try await execute(
            route: "/v1/chat/avatar/update",
            body: UpdateRequest(
                targetDeviceID: targetDeviceID,
                mimeType: mimeType,
                imageData: imageData
            )
        )
        return response.avatar.profile
    }

    private func execute<Request: Encodable, Response: Decodable>(
        route: String,
        body: Request
    ) async throws -> Response {
        let payload = try JSONEncoder().encode(body)
        let response = try await backend.execute(
            BackendAdapterRequest(route: route, payload: payload)
        )
        guard 200..<300 ~= response.statusCode else {
            throw AppError.server("http_\(response.statusCode)")
        }
        return try JSONDecoder().decode(Response.self, from: response.payload)
    }
}

@MainActor
final class ChatAvatarStore: ObservableObject {
    @Published private(set) var imageDataByParticipant: [ChatParticipant: Data]
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    let localParticipant: ChatParticipant
    private let service: ChatAvatarService
    private let defaults: UserDefaults

    init(
        service: ChatAvatarService,
        localParticipant: ChatParticipant,
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.localParticipant = localParticipant
        self.defaults = defaults
        var cached: [ChatParticipant: Data] = [:]
        for participant in [ChatParticipant.user, .developer] {
            if let data = defaults.data(forKey: Self.cacheKey(participant)) {
                cached[participant] = data
            }
        }
        imageDataByParticipant = cached
    }

    func imageData(for participant: ChatParticipant) -> Data? {
        imageDataByParticipant[participant]
    }

    func load() async {
        do {
            let profiles = try await service.load()
            for profile in profiles where profile.participant != .xiaomao {
                cache(profile.imageData, for: profile.participant)
            }
            errorMessage = nil
        } catch {
            // Keep the last local copy available when the network is temporarily offline.
        }
    }

    func update(with sourceData: Data) async {
        guard let prepared = Self.preparedJPEG(from: sourceData) else {
            errorMessage = "图片读取失败，请换一张再试。"
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let profile = try await service.update(
                imageData: prepared,
                mimeType: "image/jpeg"
            )
            guard profile.participant == localParticipant else {
                throw AppError.protocolError("avatar_participant_mismatch")
            }
            cache(profile.imageData, for: profile.participant)
        } catch {
            errorMessage = "头像保存失败，请检查网络后重试。"
        }
    }

    private func cache(_ data: Data, for participant: ChatParticipant) {
        imageDataByParticipant[participant] = data
        defaults.set(data, forKey: Self.cacheKey(participant))
    }

    private static func cacheKey(_ participant: ChatParticipant) -> String {
        "xiaomao.chat.avatar.\(participant.rawValue).v1"
    }

    private static func preparedJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        let outputSize = CGSize(width: 256, height: 256)
        let scale = max(outputSize.width / image.size.width, outputSize.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(
            x: (outputSize.width - drawSize.width) / 2,
            y: (outputSize.height - drawSize.height) / 2
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: outputSize, format: format).image { context in
            UIColor.systemBackground.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: outputSize))
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }
}

struct ChatParticipantAvatar: View {
    let participant: ChatParticipant
    let imageData: Data?
    var size: CGFloat = 32

    var body: some View {
        Group {
            if participant == .xiaomao {
                PrivacyAvatar(size: size, tappable: false, style: .thumbnail)
            } else if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.43, weight: .semibold))
                    .foregroundStyle(participant == .developer ? Theme.v2InkSurface : Theme.v2Ink.opacity(0.66))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(participant == .developer ? Theme.v2Lavender.opacity(0.72) : Theme.v2CoralSoft)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.v2Line, lineWidth: 0.7))
        .accessibilityHidden(true)
    }
}
