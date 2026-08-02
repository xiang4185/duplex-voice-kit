# DVK Companion Showcase

This public, provider-neutral iOS Simulator showcase uses a Store-driven SwiftUI experience with local mock text chat, deterministic mock voice states, privacy callbacks, five public cards, and in-memory reviews. It does not connect to a production service, request microphone permission, use real audio, or include credentials.

Generate the Xcode project with XcodeGen:

    xcodegen generate
    xcodebuild -project DVKCompanionShowcase.xcodeproj -scheme DVKCompanionShowcase -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
