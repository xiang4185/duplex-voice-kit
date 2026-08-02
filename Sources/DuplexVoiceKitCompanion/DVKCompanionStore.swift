import Foundation

@MainActor public final class DVKCompanionStore {
    public private(set) var mode:DVKCompanionMode = .text
    public private(set) var draft=""
    public private(set) var messages:[DVKCompanionMessage]=[]
    public private(set) var privacy:DVKCompanionPrivacyState = .allowed
    public private(set) var sending=false
    public private(set) var lastFailure=false
    public private(set) var activeEasterEgg:DVKCompanionEasterEgg?
    public private(set) var reviews:[DVKCompanionReview]=[]
    public private(set) var generating:DVKReviewGenerating = .idle
    public private(set) var mockVoiceState="idle"
    public private(set) var playbackAmplitude:Float=0
    private let chat:any DVKChatServicing
    private let reviewGenerator:DVKMockReviewGenerator
    private var key:String?
    private var started:Date?
    public init(chat:any DVKChatServicing = DVKMockChatService(), reviewGenerator:DVKMockReviewGenerator = DVKMockReviewGenerator()){self.chat=chat;self.reviewGenerator=reviewGenerator}
    public func setMode(_ value:DVKCompanionMode){mode=value}
    public func setDraft(_ value:String){draft=value}
    public var canSend:Bool{!draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && !sending && privacy == .allowed}
    public func sendDraft() async {
        guard canSend else{return}
        let text=draft.trimmingCharacters(in:.whitespacesAndNewlines)
        let message=DVKCompanionMessage(role:.user,text:text,deliveryState:.pending)
        messages.append(message); draft=""; sending=true; lastFailure=false
        do { let reply=try await chat.send(text); update(message.id,.sent); messages.append(DVKCompanionMessage(role:.assistant,text:reply,deliveryState:.sent)) }
        catch { update(message.id,.failed); draft=text; lastFailure=true }
        sending=false
    }
    public func retryLastMessage() async { guard let failed=messages.last(where:{$0.role == .user && $0.deliveryState == .failed}) else{return}; messages.removeAll{$0.id == failed.id}; draft=failed.text; await sendDraft() }
    public func setPrivacy(_ value:DVKCompanionPrivacyState){privacy=value}
    public func reauthorize(){privacy = .allowed}
    public func present(_ value:DVKCompanionEasterEgg){activeEasterEgg=value}
    public func dismissEasterEgg(){activeEasterEgg=nil}
    public func beginVoiceDemo(){guard privacy == .allowed && key == nil else{return};key=UUID().uuidString;started=Date();mockVoiceState="connecting"}
    public func advanceVoiceDemo(){guard key != nil else{return};switch mockVoiceState{case "connecting":mockVoiceState="listening";case "listening":mockVoiceState="processing";case "processing":mockVoiceState="speaking";case "speaking":mockVoiceState="ended";default:break};playbackAmplitude=mockVoiceState == "speaking" ? 0.72 : 0}
    public func endVoiceDemo() async {guard let key,let started else{return};mockVoiceState="ended";generating=.generating;if let review=await reviewGenerator.generate(sessionKey:key,startedAt:started,endedAt:Date()){reviews.insert(review,at:0)};generating=.idle;self.key=nil;self.started=nil;playbackAmplitude=0}
    public func deleteReview(id:UUID){reviews.removeAll{$0.id == id}}
    private func update(_ id:UUID,_ state:DVKCompanionDeliveryState){guard let i=messages.firstIndex(where:{$0.id == id}) else{return};messages[i].deliveryState=state}
}
