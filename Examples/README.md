# Examples

DuplexVoiceKit intentionally does not ship a Provider-specific implementation in the core package.

Start with the neutral transport contract in [`docs/provider-integration.md`](../docs/provider-integration.md). Downstream examples should use synthetic credentials and endpoints, keep Provider SDKs outside the core target, and avoid production data.

Versioned sample applications may be added later without changing the Provider-neutral boundary.
## DVK Companion Showcase

The existing examples remain documented here. DVKCompanionShowcase is an independent iOS Simulator app demonstrating the public Companion and SwiftUI layers. It is Store-driven, mock-only, and does not connect to a production service.
