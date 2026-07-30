# Examples

DuplexVoiceKit intentionally does not ship a Provider-specific implementation in the core package.

Start with the neutral transport contract in [`docs/provider-integration.md`](../docs/provider-integration.md). Downstream examples should use synthetic credentials and endpoints, keep Provider SDKs outside the core target, and avoid production data.

Versioned sample applications may be added later without changing the Provider-neutral boundary.
