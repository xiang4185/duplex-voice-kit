#if canImport(SwiftUI)
import SwiftUI
import DuplexVoiceKitCompanion

public struct DVKPrivacyLimitedView: View {
    public let onReauthorize: () -> Void
    public init(onReauthorize: @escaping () -> Void) { self.onReauthorize = onReauthorize }
    public var body: some View { VStack(alignment: .leading) { Text("Voice access is limited"); Text("The showcase remains browsable while voice actions are paused."); Button("Re-authorize", action: onReauthorize).accessibilityIdentifier("privacy.reauthorize") }.padding() }
}
public struct DVKEasterEggCard: View {
    public let egg: DVKCompanionEasterEgg; public let onClose: () -> Void
    public init(egg: DVKCompanionEasterEgg, onClose: @escaping () -> Void) { self.egg=egg; self.onClose=onClose }
    public var body: some View { VStack { Text(egg.rawValue.capitalized); Button("Close", action: onClose).accessibilityIdentifier("easter-egg.close") }.padding() }
}
public struct DVKCompanionView: View {
    @State private var mode: DVKCompanionMode = .text
    @State private var draft = ""
    @State private var messages: [DVKCompanionMessage] = []
    public init() {}
    public var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            Text("DVK Companion Showcase").font(.largeTitle.bold())
            Text("Public, provider-neutral, mock-only experience").foregroundStyle(.secondary)
            Picker("Mode", selection: $mode) { Text("Text").tag(DVKCompanionMode.text); Text("Voice").tag(DVKCompanionMode.voice) }.pickerStyle(.segmented).accessibilityIdentifier("mode.picker")
            if mode == .text {
                ForEach(messages) { Text($0.text).padding(10).accessibilityIdentifier("chat.message") }
                HStack { TextField("Write a message", text: $draft).accessibilityIdentifier("chat.input"); Button("Send") { let text=draft.trimmingCharacters(in:.whitespacesAndNewlines); guard !text.isEmpty else{return}; messages.append(DVKCompanionMessage(role:.user,text:text,deliveryState:.sent)); messages.append(DVKCompanionMessage(role:.assistant,text:"Mock reply: \(text)",deliveryState:.sent)); draft="" }.disabled(draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("chat.send") }
            } else { Text("Mock voice state: idle").accessibilityIdentifier("voice.state"); DVKPlaybackAmplitudeView(amplitude: 0) }
        }.padding() }.navigationTitle("Showcase")
    }
}
#endif
