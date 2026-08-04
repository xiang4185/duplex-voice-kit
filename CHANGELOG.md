# Changelog

All notable changes to DuplexVoiceKit will be documented in this file.

The project follows Keep a Changelog conventions. Versioned release history will begin when the first Git tag is created.

## [Unreleased]

### Added

- Provider-neutral Swift Package baseline for iOS 17+.
- Full-duplex audio capture and playback using one `AVAudioEngine`.
- Serial audio upload with bounded ingress, backpressure, generation validation, monotonic `chunk_index`, stale packet rejection, and partial PCM cleanup.
- VAD, automatic commit, interrupt, response filtering, reconnect policy, and privacy-safe diagnostics.
- Public transport and transport-factory boundaries.
- Apache License 2.0 and public repository governance documentation.
- GitHub Actions workflow for static checks and iOS Simulator tests.
- Complete single-source `Apps/XiaomaoApp` target with chat, small-things, voice, Widget, app tests, and manual unsigned IPA packaging through the local DVK package.

### Security

- Public diagnostics exclude credentials, transcripts, raw audio, and message bodies.
- Static checks reject common secret, binary, Provider, product, and production-endpoint artifacts.
## Unreleased public Showcase R2

- Added a complete Store-driven public Companion experience with deterministic mock text and voice flows.
- Added privacy states, five public cards, local reviews, playback energy visualization, accessibility contracts, and behavior tests.

## Unreleased public Showcase R3A

- Added four fictional public mock cats, a Store-driven Home/Cats/Conversation/Reviews/Settings flow, and a snapping profile carousel.
- Added neutral host-injected profile routing, review/profile snapshots, deterministic Mock Lab scenarios, procedural character states, and a Live2D adapter boundary.
- Added explicit accessibility, Dynamic Type, dark-mode, and Reduce Motion contracts without third-party character, font, audio, or model assets.
- Kept the public Core boundary provider-neutral while moving the runnable Xiaomao application into the same repository with empty Release endpoints and no committed credential or private deployment material.
