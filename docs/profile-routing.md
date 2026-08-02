# Public profile routing

The Showcase exposes only a public profile ID. The host injects DVKCompanionProfileRouteResolving, which resolves that ID to an opaque DVKCompanionRouteToken and creates a DVKCompanionSessionContext for the mock text or voice service.

A message captures the profile snapshot at send start. A voice session freezes the profile snapshot for its lifetime. Sending and active voice sessions reject profile confirmation. A route failure remains visible and does not silently select another profile. The opaque route token is not displayed, logged, serialized into a review, or copied into ordinary diagnostics.

The public sample resolver is deterministic and local. It contains no real persona ID, private prompt, production address, credentials, or backend mapping. A private host such as XiaomaoApp can replace the catalog, theme, copy, resolver, and backend mapping without changing DuplexVoiceKit Core or the Foundation-only Companion boundary.
