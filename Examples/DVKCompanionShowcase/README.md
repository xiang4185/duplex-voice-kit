# DVK Companion Showcase

A public, provider-neutral iOS Simulator showcase using local mock chat, mock voice states, privacy callbacks, public cards, and in-memory reviews. It does not connect to a production service, request microphone permission, use real audio, or include credentials.

Generate with XcodeGen:

    xcodegen generate
    xcodebuild -project DVKCompanionShowcase.xcodeproj -scheme DVKCompanionShowcase -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
