#if canImport(SwiftUI)
import SwiftUI
import DuplexVoiceKitCompanion

public protocol DVKLive2DCharacterHosting {
    func makeCharacterView(profile: DVKCompanionProfileSnapshot, state: DVKCompanionCharacterPresentationState) -> AnyView?
}

public struct DVKStaticCharacterAdapter: DVKLive2DCharacterHosting {
    public init() {}
    public func makeCharacterView(profile: DVKCompanionProfileSnapshot, state: DVKCompanionCharacterPresentationState) -> AnyView? { nil }
}

@MainActor
public struct DVKCharacterPresentationView: View {
    public let profile: DVKCompanionProfile
    public let state: DVKCompanionCharacterPresentationState
    public let reduceMotion: Bool
    public let staticMode: Bool
    public let host: (any DVKLive2DCharacterHosting)?
    public init(profile: DVKCompanionProfile, state: DVKCompanionCharacterPresentationState = .idle, reduceMotion: Bool = false, staticMode: Bool = false, host: (any DVKLive2DCharacterHosting)? = nil) {
        self.profile=profile; self.state=state; self.reduceMotion=reduceMotion; self.staticMode=staticMode; self.host=host
    }
    public var body: some View {
        if !staticMode, let host, let hosted = host.makeCharacterView(profile: profile.snapshot, state: state) {
            hosted
        } else {
            DVKProgrammaticCatView(profile: profile, state: state, reduceMotion: reduceMotion || staticMode)
        }
    }
}

@MainActor
public struct DVKProgrammaticCatView: View {
    public let profile: DVKCompanionProfile
    public let state: DVKCompanionCharacterPresentationState
    public let reduceMotion: Bool
    @State private var breathing = false

    public init(profile: DVKCompanionProfile, state: DVKCompanionCharacterPresentationState = .idle, reduceMotion: Bool = false) {
        self.profile=profile; self.state=state; self.reduceMotion=reduceMotion
    }

    private var accent: Color {
        switch profile.themeKey { case .warmCreamRose: return Color(hex:0xD9486B); case .coralGold: return Color(hex:0xE36C4D); case .mistBlue: return Color(hex:0x7897AC); case .lavenderNight: return Color(hex:0xA58BC4) }
    }
    private var fur: Color {
        switch profile.characterVisualKey { case "coral-gold": return Color(hex:0xF2B58D); case "silver-mist": return Color(hex:0xBCC8D0); case "lavender-night": return Color(hex:0xC8B4D7); default: return Color(hex:0xF6E4D7) }
    }
    private var earMark: Color {
        switch profile.characterVisualKey { case "coral-gold": return Color(hex:0xC65A42); case "silver-mist": return Color(hex:0x6C8EA4); case "lavender-night": return Color(hex:0x6E568E); default: return Color(hex:0xC87886) }
    }
    private var mouthWidth: CGFloat {
        switch state { case .speaking(let amplitude): return 20 + CGFloat(min(1, max(0, amplitude))) * 16; case .listening: return 30; case .thinking: return 12; case .error: return 24; default: return 18 }
    }
    private var mouthHeight: CGFloat {
        switch state { case .speaking(let amplitude): return 4 + CGFloat(min(1, max(0, amplitude))) * 11; case .listening: return 4; case .thinking: return 3; case .error: return 8; default: return 4 }
    }
    private var stateAccent: Color {
        switch state { case .celebrating: return Color(hex:0xF5C84B); case .error: return Color(hex:0xC94343); case .unavailable: return Color(hex:0x8B8B8B); case .listening: return accent.opacity(0.95); case .thinking: return Color(hex:0x7897AC); default: return accent }
    }
    private var stateScale: CGFloat {
        switch state { case .celebrating: return 1.05; case .unavailable: return 0.92; case .error: return 0.98; default: return 1 }
    }

    public var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [stateAccent.opacity(state == .speaking(amplitude: 0) ? 0.24 : 0.20), .clear], center: .center, startRadius: 18, endRadius: 132)).frame(width:250,height:250)
            ZStack {
                Circle().fill(fur).frame(width:116,height:108)
                HStack(spacing:54) { Circle().fill(Color.black.opacity(0.72)).frame(width:8,height:11); Circle().fill(Color.black.opacity(0.72)).frame(width:8,height:11) }.offset(y: 2)
                Capsule().fill(earMark).frame(width: mouthWidth, height: mouthHeight).offset(y: 30)
                HStack(spacing:72) {
                    Triangle().fill(earMark).frame(width:28,height:34)
                    Triangle().fill(earMark).frame(width:28,height:34)
                }.rotationEffect(state == .listening ? .degrees(-5) : .zero).offset(y:-64)
                if profile.characterVisualKey == "coral-gold" {
                    Circle().fill(Color(hex:0xF5C84B)).frame(width:18,height:18).offset(x:42,y:-22)
                } else if profile.characterVisualKey == "silver-mist" {
                    RoundedRectangle(cornerRadius:5).fill(earMark.opacity(0.8)).frame(width:22,height:8).offset(x:-38,y:-20)
                } else if profile.characterVisualKey == "lavender-night" {
                    Circle().fill(Color(hex:0xE8D8F7)).frame(width:13,height:13).offset(x:40,y:-26)
                } else {
                    Capsule().fill(earMark.opacity(0.6)).frame(width:22,height:3).offset(x:-37,y:-19)
                }
                if state == .thinking { Text("…").font(.title.bold()).foregroundStyle(stateAccent).offset(x:48,y:-70) }
                if state == .celebrating { HStack(spacing:34) { Text("✦"); Text("✧") }.font(.title2).foregroundStyle(stateAccent).offset(y:-82) }
                if state == .error { Circle().stroke(stateAccent,lineWidth:4).frame(width:140,height:132); Text("!").font(.headline.bold()).foregroundStyle(stateAccent).offset(x:44,y:-42) }
                if state == .unavailable { Color.gray.opacity(0.28).frame(width:140,height:132).clipShape(Capsule()); Image(systemName:"lock.fill").foregroundStyle(.secondary) }
            }
            .saturation(state == .unavailable ? 0.15 : 1)
            .scaleEffect(stateScale * (reduceMotion ? 1 : (breathing ? 1.02 : 0.985)))
            .offset(y: reduceMotion ? 0 : (breathing ? -3 : 2))
            .animation(reduceMotion ? nil : .easeInOut(duration:4.2).repeatForever(autoreverses:true), value: breathing)
            .onAppear { if !reduceMotion { breathing = true } }
        }
        .overlay(alignment: .bottom) {
            Text(state.accessibilityDescription.capitalized).font(.caption2).padding(.horizontal,8).padding(.vertical,4).background(.thinMaterial, in: Capsule()).opacity(state == .idle ? 0.0 : 0.9)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(profile.accessibilityDescription)
        .accessibilityValue(state.accessibilityDescription)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p=Path(); p.move(to: CGPoint(x:rect.midX,y:rect.minY)); p.addLine(to: CGPoint(x:rect.maxX,y:rect.maxY)); p.addLine(to: CGPoint(x:rect.minX,y:rect.maxY)); p.closeSubpath(); return p
    }
}
private extension DVKCompanionCharacterPresentationState {
    var accessibilityDescription: String {
        switch self { case .idle:return "resting"; case .listening:return "listening"; case .thinking:return "thinking"; case .speaking:return "speaking"; case .celebrating:return "celebrating"; case .unavailable:return "unavailable"; case .error:return "error" }
    }
}
private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}
#endif
