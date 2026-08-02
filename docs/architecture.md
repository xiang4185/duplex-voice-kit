# Architecture

Host App
- DuplexVoiceKitUI
- DuplexVoiceKitCompanion
- DuplexVoiceKit Core

Core remains provider-neutral realtime voice infrastructure. Companion is a Foundation-only state and mock layer. UI is an optional SwiftUI layer consumed by the host app. Showcase never changes Core audio, queue, generation, reconnect, or privacy semantics.
