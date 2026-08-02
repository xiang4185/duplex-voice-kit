import DuplexVoiceKit
import DuplexVoiceKitCompanion

public enum DVKCompanionAccessibilityID {
    public static let startupInitializing = "companion.startup.initializing"
    public static let modePicker = "companion.modePicker"
    public static let chatInput = "companion.chatInput"
    public static let chatSend = "companion.chatSend"
    public static let chatSending = "companion.chatSending"
    public static let chatPlanFailure = "companion.chatPlanFailure"
    public static let chatRetry = "companion.chatRetry"
    public static let voiceState = "companion.voiceState"
    public static let voiceStart = "companion.voiceStart"
    public static let voiceAdvance = "companion.voiceAdvance"
    public static let voiceEnd = "companion.voiceEnd"
    public static let privacyAllowed = "companion.privacyAllowed"
    public static let privacyLimited = "companion.privacyLimited"
    public static let reauthorize = "companion.reauthorize"
    public static let cards = "companion.cards"
    public static let reviewList = "companion.reviewList"
    public static let reviewDetail = "companion.reviewDetail"
    public static let reviewDelete = "companion.reviewDelete"
}

#if canImport(SwiftUI)
import SwiftUI
import Combine
import DuplexVoiceKitCompanion

@MainActor
public final class DVKCompanionStoreAdapter: ObservableObject {
    @Published public private(set) var revision = 0
    public let store: DVKCompanionStore
    public let playbackAmplitudeRelay: DVKPlaybackAmplitudeRelay
    public init(store: DVKCompanionStore) {
        self.store = store
        let relay = DVKPlaybackAmplitudeRelay()
        self.playbackAmplitudeRelay = relay
        relay.setOnChange { [weak self, weak store] amplitude in
            Task { @MainActor in
                store?.receivePlaybackAmplitude(amplitude)
                self?.refresh()
            }
        }
        store.setPlaybackAmplitudeInput { [weak relay] amplitude in
            relay?.playbackAmplitudeDidChange(amplitude)
        }
    }

    public convenience init() {
        self.init(store: DVKCompanionStore())
    }
    public func refresh() {
        store.receivePlaybackAmplitude(playbackAmplitudeRelay.currentAmplitude)
        revision += 1
    }
}

@MainActor
public struct DVKCompanionStartupView: View {
    @StateObject private var adapter: DVKCompanionStoreAdapter

    public init(store: DVKCompanionStore) {
        _adapter = StateObject(wrappedValue: DVKCompanionStoreAdapter(store: store))
    }

    public init() {
        self.init(store: DVKCompanionStore())
    }
    public var body: some View {
        Group {
            if adapter.store.initializationState == .ready {
                NavigationStack { DVKCompanionView(store: adapter.store) }
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Preparing local showcase").font(.headline)
                    Text("Initializing the in-memory Companion store.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier(DVKCompanionAccessibilityID.startupInitializing)
                .task {
                    adapter.store.initializeLocally()
                    adapter.refresh()
                }
            }
        }
        .accessibilityIdentifier("companion.startup")
    }
}

public struct DVKPrivacyLimitedView: View {
    private let onReauthorize: () -> Void
    public init(onReauthorize: @escaping () -> Void) { self.onReauthorize = onReauthorize }
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Voice is limited", systemImage: "lock.shield").font(.headline)
            Text("Browsing and configured text demos remain available. Voice actions stay paused until you re-authorize.").font(.subheadline).foregroundStyle(.secondary)
            Button("Re-authorize", action: onReauthorize).buttonStyle(.borderedProminent).accessibilityIdentifier(DVKCompanionAccessibilityID.reauthorize)
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial).clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityIdentifier(DVKCompanionAccessibilityID.privacyLimited)
    }
}

public struct DVKEasterEggCard: View {
    public let egg: DVKCompanionEasterEgg
    private let onClose: () -> Void
    public init(egg: DVKCompanionEasterEgg, onClose: @escaping () -> Void) { self.egg=egg; self.onClose=onClose }
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(egg.title).font(.headline); Spacer(); Button("Close", action: onClose).accessibilityLabel("Close \(egg.title) card") }
            Text(egg.detail).font(.body).foregroundStyle(.secondary)
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityElement(children: .contain)
    }
}

public struct DVKReviewListView: View {
    @ObservedObject private var adapter: DVKCompanionStoreAdapter
    public init(adapter: DVKCompanionStoreAdapter) { self.adapter=adapter }
    public var body: some View {
        Group {
            if adapter.store.reviews.isEmpty {
                ContentUnavailableView("No reviews yet", systemImage: "waveform", description: Text("Complete a mock voice demo to create a local review")).accessibilityIdentifier("companion.reviews.empty")
            } else {
                List(adapter.store.reviews) { review in
                    Button {
                        adapter.store.selectReview(id: review.id); adapter.refresh()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) { Text(review.title).font(.headline); Text(review.summary).font(.subheadline).foregroundStyle(.secondary) }
                    }.accessibilityIdentifier("companion.review.\(review.id)")
                }
            }
        }.navigationTitle("Reviews")
        .sheet(isPresented: Binding(get: { adapter.store.selectedReview() != nil }, set: { if !$0 { adapter.store.clearSelectedReview(); adapter.refresh() } })) {
            if let review = adapter.store.selectedReview() {
                DVKReviewDetailView(review: review, onDelete: { adapter.store.deleteReview(id: review.id); adapter.refresh() }, onClose: { adapter.store.clearSelectedReview(); adapter.refresh() })
            }
        }
    }
}

public struct DVKReviewDetailView: View {
    public let review: DVKCompanionReview
    private let onDelete: () -> Void
    private let onClose: () -> Void
    public init(review: DVKCompanionReview, onDelete: @escaping () -> Void, onClose: @escaping () -> Void) { self.review=review; self.onDelete=onDelete; self.onClose=onClose }
    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(review.title).font(.largeTitle.bold()); Text(review.summary).font(.body)
                LabeledContent("Duration", value: "\(Int(review.duration)) seconds")
                LabeledContent("Session", value: String(review.sessionKey.prefix(8)))
                Spacer()
                Button("Delete review", role: .destructive, action: onDelete).accessibilityIdentifier(DVKCompanionAccessibilityID.reviewDelete)
                Button("Close", action: onClose)
            }.padding().navigationTitle("Review detail").accessibilityIdentifier(DVKCompanionAccessibilityID.reviewDetail)
        }
    }
}

@MainActor
public struct DVKCompanionView: View {
    @StateObject private var adapter: DVKCompanionStoreAdapter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(store: DVKCompanionStore) {
        _adapter = StateObject(wrappedValue: DVKCompanionStoreAdapter(store: store))
    }

    public init() {
        self.init(store: DVKCompanionStore())
    }
    public var body: some View {
        let store=adapter.store
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("DVK Companion Showcase").font(.largeTitle.bold())
                    Text("Public, provider-neutral, mock-only experience").font(.headline).foregroundStyle(.secondary)
                    Text("No production service, account, microphone, or network is used.").font(.subheadline).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
                Picker("Mode", selection: Binding(get: { store.mode }, set: { store.setMode($0); adapter.refresh() })) { Text("Text").tag(DVKCompanionMode.text); Text("Voice").tag(DVKCompanionMode.voice) }.pickerStyle(.segmented).accessibilityIdentifier(DVKCompanionAccessibilityID.modePicker)
                if store.privacy == .limited {
                    DVKPrivacyLimitedView { store.reauthorize(); adapter.refresh() }
                } else {
                    HStack {
                        Label("Privacy allowed", systemImage: "checkmark.shield")
                        Spacer()
                        Button("Preview limited") { store.setPrivacy(.limited); adapter.refresh() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier(DVKCompanionAccessibilityID.privacyAllowed)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                if store.mode == .text { textExperience(store) } else { voiceExperience(store) }
                cardsExperience(store)
                NavigationLink("Open reviews") { DVKReviewListView(adapter: adapter) }.buttonStyle(.bordered).accessibilityIdentifier(DVKCompanionAccessibilityID.reviewList)
            }.padding()
        }.navigationTitle("Companion").onAppear { adapter.refresh() }
    }

    @ViewBuilder private func textExperience(_ store: DVKCompanionStore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.messages) { message in
                HStack { if message.role == .assistant { messageBubble(message) }; Spacer(minLength: message.role == .user ? 34 : 0); if message.role == .user { messageBubble(message) } }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Write a message", text: Binding(get: { store.draft }, set: { store.setDraft($0); adapter.refresh() }), axis: .vertical).textFieldStyle(.roundedBorder).accessibilityIdentifier(DVKCompanionAccessibilityID.chatInput)
                Button("Send") { guard let operation = store.beginSendDraft() else { return }; adapter.refresh(); Task { await operation.value; adapter.refresh() } }.buttonStyle(.borderedProminent).disabled(!store.canSend).accessibilityIdentifier(DVKCompanionAccessibilityID.chatSend)
            }
            if store.sending {
                ProgressView("Sending...")
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.chatSending)
            }
            HStack {
                Button("Plan next send failure") {
                    Task {
                        await store.planNextMockFailure()
                        adapter.refresh()
                    }
                }
                .disabled(!store.canPlanMockFailure)
                .accessibilityIdentifier(DVKCompanionAccessibilityID.chatPlanFailure)
                if store.mockFailurePlanned {
                    Text("Next send will fail").font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.lastFailure {
                Button("Retry failed message") {
                    guard let operation = store.beginRetryFailedMessage() else { return }
                    adapter.refresh()
                    Task {
                        await operation.value
                        adapter.refresh()
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(DVKCompanionAccessibilityID.chatRetry)
            }
        }
    }

    private func messageBubble(_ message: DVKCompanionMessage) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(message.role == .user ? "You" : "Assistant").font(.caption.bold()); Text(message.text).font(.body); Text(message.deliveryState.rawValue.capitalized).font(.caption2).foregroundStyle(.secondary) }
            .padding(12).background(message.role == .user ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityElement(children: .combine)
    }

    @ViewBuilder private func voiceExperience(_ store: DVKCompanionStore) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mock voice demo").font(.title2.bold())
            Text("State: \(store.voiceState.rawValue.capitalized)").font(.headline).accessibilityIdentifier(DVKCompanionAccessibilityID.voiceState)
            DVKPlaybackAmplitudeView(amplitude: store.playbackAmplitude, reduceMotion: reduceMotion)
            HStack {
                Button("Start") { store.beginVoiceDemo(); adapter.refresh() }.disabled(!store.canStartVoice).accessibilityIdentifier(DVKCompanionAccessibilityID.voiceStart)
                Button("Advance") { store.advanceVoiceDemo(); adapter.refresh() }.disabled(store.voiceState == .idle || store.voiceState == .ended).accessibilityIdentifier(DVKCompanionAccessibilityID.voiceAdvance)
                Button("End") { Task { await store.endVoiceDemo(); adapter.refresh() } }.disabled(!store.canEndVoice).accessibilityIdentifier(DVKCompanionAccessibilityID.voiceEnd)
            }.buttonStyle(.borderedProminent)
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial).clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder private func cardsExperience(_ store: DVKCompanionStore) -> some View {
        DisclosureGroup("Public cards") {
            ForEach(DVKCompanionEasterEgg.allCases, id: \.self) { egg in Button(egg.title) { store.presentEasterEgg(egg); adapter.refresh() }.accessibilityLabel("\(egg.title) public card") }
        }.accessibilityIdentifier(DVKCompanionAccessibilityID.cards)
        if let egg=store.activeEasterEgg { DVKEasterEggCard(egg: egg) { store.dismissEasterEgg(); adapter.refresh() } }
    }
}
#endif
