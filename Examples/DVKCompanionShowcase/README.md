# DVK Companion Showcase

This public, provider-neutral iOS Simulator showcase uses a Store-driven SwiftUI experience with local mock text chat, deterministic mock voice states, privacy callbacks, five public cards, and in-memory reviews. It does not connect to a production service, request microphone permission, use real audio, or include credentials.

Generate the Xcode project with XcodeGen:

    xcodegen generate
    xcodebuild -project DVKCompanionShowcase.xcodeproj -scheme DVKCompanionShowcase -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build

## R3A public multi-cat experience

The Showcase has four fictional mock cats with independent summaries, greetings, tags, visual keys, and text/voice/review capabilities:

- Mellow — gentle, steady, warm
- Sunny — cheerful, curious, uplifting
- Sage — thoughtful, clear, patient
- Luna — imaginative, playful, dreamy

The Cats page uses a horizontal snapping carousel with centered 156:190 cards, neighboring card peeks, a preview bar, confirmation action, and VoiceOver previous/next controls. Home has a compact carousel; complete profile selection happens on Cats. Home, Conversation, Reviews, and Settings all read the same Companion Store.

Routing is intentionally neutral: a host resolver maps a public profile ID to an opaque route token. The token is not displayed, logged, or written to a review. The public repository contains no real persona ID, private prompt, production endpoint, credential, or third-party character/font/model asset. XiaomaoApp can later inject its private catalog, theme, route mapping, copy, and final character resources.

Mock Lab scenarios are deterministic and local: text success, slow response, next text failure, route failure, unavailable profile, voice connection failure, voice interruption, review generation failure, limited privacy, multiple reviews, empty reviews, appearance, Reduce Motion, procedural character states, and playback amplitude.

## V7.1-R4 character artwork

The default companion character artwork (`DVKCatPortrait`, 1024×1536 PNG, and `DVKCatAvatar`, 512×512 PNG) is AI-generated for this project and approved by the project owner for public redistribution. It ships under public resource names inside the DuplexVoiceKitUI target, using `.process("Resources")` in Package.swift and `Image(_:bundle: .module)` lookups. The private source asset names are intentionally not reused to avoid collisions with host apps. The App Icon and any other branded assets are not included. The procedural mock cats remain the fallback for the other three public roles and for resource-load failures.
